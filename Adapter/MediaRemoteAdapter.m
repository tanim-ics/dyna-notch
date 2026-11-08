// MediaRemoteAdapter.m
//
// Since macOS 15.4, third-party processes can no longer read the system
// "Now Playing" state through the private MediaRemote framework. Apple's own
// signed binaries (such as /usr/bin/perl) still can. DynaNotch therefore loads
// this dylib into /usr/bin/perl and talks to it over stdin/stdout:
//
//   stdout: one JSON object per line describing the current Now Playing state
//   stdin : one command per line: play | pause | toggle | next | prev | seek <seconds>
//
// macOS keeps a paused player as "the" now-playing app even when another app starts playing (e.g. a paused
// YouTube Music web app while a YouTube tab plays in the same browser). When the elected app is paused, the
// adapter asks every other now-playing client for its own info and reports one that is actually playing
// ("override": true). Commands for that player cannot be routed to it, so they are not sent to the paused app.
//
// The helper exits as soon as stdin is closed (i.e. when DynaNotch quits).

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRIsPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*MRClientStrFn)(id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFn)(uint32_t, NSDictionary *);
typedef void (*MRSetElapsedFn)(double);
typedef id   (*MRGetOriginFn)(void);
typedef void (*MRGetClientsFn)(dispatch_queue_t, void (^)(NSArray *));
// Argument order found by probing on macOS 27: (client, origin, player or nil, queue, completion).
typedef void (*MRInfoForClientFn)(id, id, id, dispatch_queue_t, void (^)(NSDictionary *));

static MRGetInfoFn      gGetInfo;
static MRIsPlayingFn    gIsPlaying;
static MRGetClientFn    gGetClient;
static MRClientStrFn    gClientBundle;
static MRClientStrFn    gClientParentBundle;
static MRSendCommandFn  gSend;
static MRSetElapsedFn   gSetElapsed;
static MRGetOriginFn    gLocalOrigin;
static MRGetClientsFn   gGetClients;
static MRInfoForClientFn gInfoForClient;
static NSString *gOverrideBundle = nil;   // set while the report is another (playing) client, not the elected one

static NSString *gLastPayload   = nil;
static NSString *gLastArtworkId = nil;
static BOOL      gRefreshQueued = NO;

static void emitLine(NSString *line) {
    @autoreleasepool {
        NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, stdout);
        fflush(stdout);
    }
}

static id jsonSafe(id v) {
    if (v == nil) return [NSNull null];
    if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) return v;
    if ([v isKindOfClass:[NSDate class]]) return @([(NSDate *)v timeIntervalSince1970]);
    return [v description];
}

static void emitInfo(NSDictionary *info, BOOL playing, NSString *bundle, NSString *parent, BOOL override) {

            @autoreleasepool {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"type"] = @"nowPlaying";

                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (info.count == 0 || title.length == 0) {
                    out[@"empty"] = @YES;
                    // Forget the last artwork so it is re-sent if the same track comes back after an
                    // empty state (the app drops its artwork on "empty").
                    gLastArtworkId = nil;
                } else {
                    out[@"empty"]    = @NO;
                    out[@"title"]    = jsonSafe(title);
                    out[@"artist"]   = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
                    out[@"album"]    = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
                    out[@"duration"] = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                    out[@"elapsed"]  = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                    out[@"rate"]     = jsonSafe(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                    id ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    out[@"timestamp"] = jsonSafe(ts ?: [NSDate date]);
                    out[@"playing"]  = @(playing);
                    out[@"bundle"]   = jsonSafe(bundle);
                    out[@"parentBundle"] = jsonSafe(parent);
                    if (override) out[@"override"] = @YES;

                    NSString *artId = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
                    NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    if (artId.length == 0 && art.length > 0) {
                        artId = [NSString stringWithFormat:@"len-%lu-%@", (unsigned long)art.length, title];
                    }
                    out[@"artworkId"] = jsonSafe(artId);
                }

                NSData *json = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
                NSString *payload = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
                if (!payload) return;

                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSString *artId = [out[@"artworkId"] isKindOfClass:[NSString class]] ? out[@"artworkId"] : nil;
                BOOL sendArt = art.length > 0 && artId && ![artId isEqualToString:gLastArtworkId ?: @""];

                if ([payload isEqualToString:gLastPayload] && !sendArt) return;
                gLastPayload = payload;

                if (sendArt) {
                    gLastArtworkId = artId;
                    out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                    NSData *j2 = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                    if (j2) payload = [[NSString alloc] initWithData:j2 encoding:NSUTF8StringEncoding];
                }
                emitLine(payload);
            }
        }

/// The elected app is paused: report another client that is playing, if any (each asked for its own info).
static void findPlayingClient(NSString *electedBundle, void (^done)(NSDictionary *info, NSString *bundle)) {
    if (!gGetClients || !gInfoForClient || !gLocalOrigin || !gClientBundle) { done(nil, nil); return; }
    gGetClients(dispatch_get_main_queue(), ^(NSArray *clients) {
        __block BOOL finished = NO;
        __block NSInteger pending = 0;
        __block NSDictionary *bestInfo = nil;
        __block NSString *bestBundle = nil;
        void (^complete)(void) = ^{
            if (finished) return;
            finished = YES;
            done(bestInfo, bestBundle);
        };
        id origin = gLocalOrigin();
        for (id client in clients) {
            NSString *bundle = gClientBundle(client);
            if (bundle.length == 0 || [bundle isEqualToString:electedBundle ?: @""]) continue;
            pending += 1;
            gInfoForClient(client, origin, nil, dispatch_get_main_queue(), ^(NSDictionary *info) {
                NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (!bestInfo && rate.doubleValue > 0 && title.length > 0) {
                    bestInfo = info;
                    bestBundle = bundle;
                }
                pending -= 1;
                if (pending == 0) complete();
            });
        }
        if (pending == 0) { complete(); return; }
        // Never let a client that does not answer hold up the report.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), complete);
    });
}

static void refresh(void) {
    if (!gGetInfo) return;
    gGetInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        void (^finish)(BOOL, NSString *, NSString *) = ^(BOOL playing, NSString *bundle, NSString *parent) {
            if (playing) {
                gOverrideBundle = nil;
                emitInfo(info, playing, bundle, parent, NO);
                return;
            }
            findPlayingClient(bundle, ^(NSDictionary *other, NSString *otherBundle) {
                if (other) {
                    gOverrideBundle = otherBundle;
                    emitInfo(other, YES, otherBundle, nil, YES);
                } else {
                    gOverrideBundle = nil;
                    emitInfo(info, playing, bundle, parent, NO);
                }
            });
        };

        if (gIsPlaying) {
            gIsPlaying(dispatch_get_main_queue(), ^(BOOL playing) {
                if (gGetClient && gClientBundle) {
                    gGetClient(dispatch_get_main_queue(), ^(id client) {
                        NSString *b = client ? gClientBundle(client) : nil;
                        NSString *p = (client && gClientParentBundle) ? gClientParentBundle(client) : nil;
                        finish(playing, b, p);
                    });
                } else {
                    finish(playing, nil, nil);
                }
            });
        } else {
            NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
            finish(rate.doubleValue > 0, nil, nil);
        }
    });
}

static void scheduleRefresh(void) {
    if (gRefreshQueued) return;
    gRefreshQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gRefreshQueued = NO;
        refresh();
    });
}

static void handleCommand(NSString *line) {
    NSString *cmd = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cmd.length == 0) return;
    enum { kPlay = 0, kPause = 1, kToggle = 2, kNext = 4, kPrev = 5 };
    // Showing another app's playback: the system would send this to the paused elected app and start it again.
    if (gOverrideBundle && ![cmd isEqualToString:@"refresh"]) { scheduleRefresh(); return; }
    if ([cmd isEqualToString:@"play"])        { if (gSend) gSend(kPlay, nil); }
    else if ([cmd isEqualToString:@"pause"])  { if (gSend) gSend(kPause, nil); }
    else if ([cmd isEqualToString:@"toggle"]) { if (gSend) gSend(kToggle, nil); }
    else if ([cmd isEqualToString:@"next"])   { if (gSend) gSend(kNext, nil); }
    else if ([cmd isEqualToString:@"prev"])   { if (gSend) gSend(kPrev, nil); }
    else if ([cmd hasPrefix:@"seek "]) {
        // Accept "12.5" and "12,5" (locale-formatted) alike; -doubleValue is locale-independent and stops at ','.
        NSString *arg = [[cmd substringFromIndex:5] stringByReplacingOccurrencesOfString:@"," withString:@"."];
        double seconds = [arg doubleValue];
        if (gSetElapsed && isfinite(seconds) && seconds >= 0) gSetElapsed(seconds);
    }
    else if ([cmd isEqualToString:@"refresh"]) { gLastPayload = nil; gLastArtworkId = nil; }
    scheduleRefresh();
}

__attribute__((visibility("default"))) void dn_run(void *perlInterpreter, void *cv) {
    (void)perlInterpreter; (void)cv;
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) {
            emitLine(@"{\"type\":\"error\",\"message\":\"MediaRemote unavailable\"}");
            exit(2);
        }
        gGetInfo            = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        gIsPlaying          = (MRIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        gGetClient          = (MRGetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        gClientBundle       = (MRClientStrFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        gClientParentBundle = (MRClientStrFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        gSend               = (MRSendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        gSetElapsed         = (MRSetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        MRRegisterFn reg    = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        gLocalOrigin        = (MRGetOriginFn)dlsym(mr, "MRMediaRemoteGetLocalOrigin");
        gGetClients         = (MRGetClientsFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClients");
        gInfoForClient      = (MRInfoForClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfoForClient");

        if (!gGetInfo) {
            emitLine(@"{\"type\":\"error\",\"message\":\"MRMediaRemoteGetNowPlayingInfo missing\"}");
            exit(2);
        }
        if (reg) reg(dispatch_get_main_queue());

        NSArray *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
            @"kMRNowPlayingPlaybackQueueChangedNotification",
            @"kMRPlaybackQueueContentItemsChangedNotification",
        ];
        for (NSString *n in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:nil
                                                          usingBlock:^(NSNotification *note) { scheduleRefresh(); }];
        }

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(timer, ^{ refresh(); });
        dispatch_resume(timer);

        [NSThread detachNewThreadWithBlock:^{
            char buf[1024];
            while (fgets(buf, sizeof buf, stdin)) {
                NSString *line = [NSString stringWithUTF8String:buf];
                if (line) dispatch_async(dispatch_get_main_queue(), ^{ handleCommand(line); });
            }
            exit(0);
        }];

        emitLine(@"{\"type\":\"ready\"}");
        CFRunLoopRun();
    }
}
