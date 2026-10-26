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

static MRGetInfoFn      gGetInfo;
static MRIsPlayingFn    gIsPlaying;
static MRGetClientFn    gGetClient;
static MRClientStrFn    gClientBundle;
static MRClientStrFn    gClientParentBundle;
static MRSendCommandFn  gSend;
static MRSetElapsedFn   gSetElapsed;

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

static void refresh(void) {
    if (!gGetInfo) return;
    gGetInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        void (^finish)(BOOL, NSString *, NSString *) = ^(BOOL playing, NSString *bundle, NSString *parent) {
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
