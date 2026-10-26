---
name: app-dev-playbook
description: >-
  End-to-end playbook for building an app with Claude, inherited from project to project: research a reference
  product into a parity board, lock a contract (pure-core types + tests, settings, stubs) before building, build in
  slices (inline or parallel agents with file ownership), test every feature like a user through in-app test hooks,
  run a quality pass (energy, sanitizers, regression suite, accessibility, health report) and ship with a scorecard.
  Ends every project with a retrospective that creates a project skill and improves this playbook. Use when starting
  or continuing app development, cloning or matching another app's features, planning a feature round, running a
  quality / performance pass, or when the user says "use my dev playbook".
---

# App development playbook

A proven lifecycle for shipping an app with Claude as the engineering team. It came out of building DynaNotch (a macOS
notch app, SwiftUI + AppKit, ~30 k lines, 224 unit tests, 94 UI checks) and gets better after every project — see
`LESSONS.md` and `CHANGELOG.md`. Platform specifics live in `references/`; this file is the process.

**Version 1.0.0** (bump on every change; log it in `CHANGELOG.md`).

## How to use this skill

1. Read this file, then `LESSONS.md` (short; the most expensive mistakes so far).
2. Find the phase the project is in and follow its checklist. Don't skip gates.
3. Load a `references/` file only when its phase needs it.
4. At the end of every project (and after any big round), run **Phase 8** — it is not optional.

## Phase 0 — Frame the work (before writing code)

- Ask only what changes the plan: target platform/OS, who uses it, the reference product, distribution (personal /
  App Store), hard limits (private APIs allowed? network? budget/usage left?).
- Write the **project CLAUDE.md** from `templates/CLAUDE.md.template` on day one: goals, non-goals, stack,
  architecture, binding rules, definition of done, docs index. Keep it ≤ 200 lines; reference material goes to `docs/`.
- Create `docs/ROADMAP.md`, `docs/CONTRACTS.md`, `docs/DECISIONS.md` (dated), `README.md` (user guide, short).
- Initialise git; commit only when the user asks, but **ask for a checkpoint commit at the end of every slice** —
  a big uncommitted tree is the single biggest risk with parallel agents.

## Phase 1 — Research into a parity board

Start from the rawest source available, not summaries: the reference app itself, its settings screens, a screen
recording (extract frames with AVFoundation, dedupe, tile into contact sheets), the product site's feature index,
the user's own screenshots. Produce in `docs/ROADMAP.md`:

| Area | Reference feature | Status ✅/🟡/⏳/❌ | Priority P1–P3 | How (public API) |

Mark ❌ with the reason (private API, paid data, non-goal). Re-audit after each round; the board is the living
to-do list. Details: `references/research.md`.

## Phase 2 — Contract first

Before any parallel or multi-file work, write the contract into `docs/CONTRACTS.md` and make it compile:

1. **Pure core** (no UI, platform-independent): state machines, layout math, parsers, formatters, schedulers. Write
   unit tests now — they are the cheapest, most durable checks.
2. **Settings**: every new setting with type, default, range, persistence key; generated, not hand-typed.
3. **Service / view APIs** as stubs with the final signatures, so every slice builds against them.
4. **File ownership** per slice (who may edit what) and **test hooks** needed (Phase 4).

Gate: the app builds and all tests pass with stubs in place.

## Phase 3 — Build in slices

- Small/medium work: do it inline (cheaper, no hand-off loss).
- Large independent slices: parallel agents, max 3–5, each with the brief from `templates/agent-brief.md`:
  owned files only, own build directory (`--scratch-path .build-<role>`), shared app lock for install + UI tests,
  "test like a user" rules, per-item report. See `references/orchestration.md`.
- Respect the usage budget: if the user is low on usage, no agents, cut scope explicitly, and say what was cut.
- If an agent dies (rate limit), check what it left (stubs remaining? build green? lock held?), release stale locks,
  and resume it with a message rather than starting over.
- Integrate: full build, full tests, fix contract drift, then Phase 4 yourself — never trust "done" without seeing it.

## Phase 4 — Test every feature like a user

Shell screen capture and synthetic input are usually blocked, so the app tests itself. Build these hooks into
every app from the start (`references/user-testing.md`):

- **State dump** (`app://state` → JSON: what's on screen, selected tab, open popovers, test-ID frames).
- **Self-snapshot** (`app://snapshot/<name>` → PNG rendered by the app from its own views).
- **UI driver** (`app://ui/click?id=…`, simulated pointer, pick-next-menu-item, trigger-shortcut actions).
- **Settings setter** (`app://set?key=value`) and **simulators** for events you can't cause (battery, devices…).
- Tag interactive controls with test IDs; every screen gets a check in `scripts/ui-regression.sh`.

Rules: test the real installed build; check edge cases (permission denied, empty, feature off); restore every
setting / volume / clipboard you change; never touch the user's real files irreversibly (test installers on copies).
A row is ✅ only after a user-level test passed — write what couldn't be tested live next to it.

## Phase 5 — Quality pass (before calling it shipped)

Measure first, then fix the top offenders, then measure again (`references/quality.md`):

1. **Energy/CPU baseline** at idle and in the main scenario (`top` POWER + idle wake-ups, `sample` for hot frames,
   Instruments when available); inventory every timer. Targets: idle ≈ 0 % CPU, ≤ 4 wake-ups/s.
2. **Replace polling with events**, move decorative animation to the render server, kill timers stored in views.
3. **Sanitizers**: Thread + Address Sanitizer builds driven through the scenarios.
4. **Regression suite** wired into `scripts/check.sh --ui`; make `check.sh` pass on the real dev machine.
5. **Accessibility**: labels on every icon-only control, a container label, keyboard reachability; VoiceOver walk.
6. **Health script** for the dogfood week: crashes/hangs (installed vs test builds), log errors, idle numbers.
7. **Scorecard** (`templates/SCORECARD.md.template`): before/after numbers, bugs found, tests added, not done + why.

## Phase 6 — Ship hygiene (add even if the user didn't ask)

- Stable code signing identity so OS permissions survive rebuilds; one-command build + install script.
- Version + build number bumped per release; `What's New` / changelog entries.
- Every privacy-sensitive API has its usage string (enforce with a check); no permission prompts at launch for
  features not in use; say where user data lives.
- Settings UX rules (`references/settings-ux.md`); Restore Defaults per page; export/import settings.
- Uninstall path (data, login item, hooks) and a "reset everything" escape hatch; an emergency quit shortcut.
- Crash/hang review with the health script after real use; logs via the platform logger, never print.
- Optional but recommended: CI running `check.sh`, localisation-ready strings, feature flags for risky features,
  a backup of the tree before big agent waves.

## Phase 7 — Dogfood

The user uses the app daily for a week; review `scripts/health.sh 7` output and their notes; fix, re-measure, update
the scorecard. Decide the next round from what they actually used.

## Phase 8 — Retrospective & evolve the playbook (mandatory at the end of every app)

1. Write `docs/RETRO.md` in the project from `templates/retro.md`: what worked, what failed, root causes, the fix,
   numbers (tests, checks, energy), what to do differently.
2. **Create a project skill** at `<project>/.claude/skills/<app>-dev/SKILL.md`: the app's commands, test hooks,
   contracts location, gotchas — so future sessions on that app start fast.
3. **Improve this playbook** (`~/.claude/skills/app-dev-playbook/`):
   - add each reusable lesson to `LESSONS.md` (one line: symptom → cause → rule), newest first, merge duplicates;
   - promote lessons that recur into the phase checklists above or a `references/` file;
   - add any new platform gotcha to the platform reference; add or update templates and scripts that proved useful;
   - remove advice that turned out wrong; bump the version; add a `CHANGELOG.md` entry naming the source project.
4. Tell the user what changed in the playbook (2–5 bullets).

Keep this file the process, not a history: details belong in references, lessons in `LESSONS.md`.

## Files

| File | Use |
|---|---|
| `LESSONS.md` | Hard-won rules, newest first — read at the start of every project |
| `CHANGELOG.md` | Playbook versions and which project taught what |
| `references/research.md` | Turning a reference product / recording into a parity board |
| `references/orchestration.md` | Contract-first parallel agents, ownership, locks, recovery |
| `references/user-testing.md` | In-app test hooks, UI driver, regression script pattern |
| `references/quality.md` | Energy measurement, polling → events, sanitizers, accessibility, health, scorecard |
| `references/settings-ux.md` | Binding rules for settings screens |
| `references/platform-macos.md` | macOS / SwiftUI / AppKit gotchas (TCC, signing, panels, timers…) |
| `templates/` | CLAUDE.md, agent brief, scorecard, retro |
| `scripts/` | `applock.sh`, `measure.sh` (idle energy), `frames.swift` (video → frames) |
