# Agent brief (copy into the shared rules file + one short per-role prompt)

You are the **<role> agent** for <App> round <n>. Read <rules file> and CLAUDE.md (§rules, contract §, ownership §).

**You own** (edit only these): <paths>. Anything else: keep going and list the change you need in your report.

**Items** (priority order): 1. <item — API to use, expected behaviour, edge cases> …

**Rules**: <concurrency/code rules>. Build with `--scratch-path .build-<role>`. If an error is in a file you don't own,
wait and rebuild. Install + UI test only inside the app lock (`source scripts/applock.sh; applock <role>` … `appunlock`,
≤ 10 min). Test each item like a user with the test hooks; restore every setting you change; never touch the owner's
real data irreversibly (test installers on copies). Don't commit, don't edit CLAUDE.md.

**Report**: per item — what you built · the exact user test · result · not tested and why; files changed; requests for
other owners.
