# Research → parity board

1. **Collect raw sources**: the product itself (install it, open every settings page), its site's feature index and
   demo, the user's screenshots, and a screen recording of every settings page and main interaction.
2. **Recording → frames** (no ffmpeg needed): `swift scripts/frames.swift <video> <outdir> <seconds-step>`
   (AVAssetImageGenerator), drop near-duplicates by thumbnail difference, tile 3 per sheet, read the sheets.
3. **Inventory** every page/control into `docs/ROADMAP.md` as rows: Area | Feature | Status | Priority | How (API).
   Status: ✅ done (user-tested) · 🟡 partial · ⏳ due · ❌ out of scope **with the reason**.
4. **Priorities**: P1 = cheap, high value, public API; P2 = next; P3 = nice to have. Pick rounds by priority.
5. **Owner bugs** go in the same doc as a table (bug → fix → status) so nothing gets lost between rounds.
6. Re-audit after each round; the reference app keeps changing.
