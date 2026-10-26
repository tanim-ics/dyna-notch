# Contract-first parallel work

When to parallelise: ≥ 3 independent slices of real size. Otherwise work inline — agents cost more than they look
(hand-off loss, re-reading context, burst usage).

**Before spawning**
- Contract written + compiling: Core types with tests, settings generated, service/view stubs with final signatures,
  placeholder views for new screens so every switch is exhaustive.
- Ownership table in the contract doc: role → files. No two agents own the same file. Shared files (app delegate,
  test driver) stay with the lead; agents ask the lead for hooks.
- Back up the tree (tarball in the scratchpad) — nothing uncommitted should be unrecoverable.
- One shared brief file (rules every agent reads) + one short per-role prompt with its item list.

**Each agent**
- Builds with its own directory (`swift build --scratch-path .build-<role>`) — one build dir can't be shared.
- Takes the app lock (`scripts/applock.sh`) for install + UI tests, holds it ≤ 10 min, releases it.
- Tests every item like a user; restores every setting it changed; never touches the user's real data irreversibly.
- Reports per item: built · user test run · result · not tested + why · requests for other owners.

**Lead during the wave**: route cross-owner requests (relay, don't edit their files), add requested test hooks,
keep the build green. **After**: integrate, full build + tests, own user-test pass, flip roadmap rows, list leftovers
honestly (e.g. things changed on the user's machine during tests).

**Recovery** (rate limit / crash): check remaining stubs, build status, stale lock (release it), then resume the agent
by message with the current state; never redo finished work.
