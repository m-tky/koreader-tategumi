# Tategumi upstream-divergence ledger

This fork tracks KOReader and CRengine closely, while adding Japanese vertical
layout. This file is the review ledger for changes that cannot be carried by
upstream unchanged. Keep it short and update it whenever a fork-only change is
added, moved, or retired.

## Rules for new changes

1. Prefer a narrow, upstream-neutral fix. Send it upstream when it does not
   require vertical Japanese behavior.
2. Keep tategumi-only code in a `*_vert.cpp` file where possible. Do not mix
   it into a large upstream file unless a small call site is unavoidable.
3. At every call site into fork-only code, add a `FORK (tategumi)` comment
   explaining the behavior difference and name the corresponding regression
   fixture or spec.
4. Do not combine an upstream merge and a tategumi behavior change in one
   commit. Merge first; make the fork change in a separate commit.
5. Each fork-only behavior needs a regression test under `spec/unit/vertical_*`
   or an isolated CRengine test under `tests/`; use a documented manual fixture
   when automated assertions are impractical.

## CRengine boundary

| Area | Fork-only owner | Why it remains local | Regression coverage |
| --- | --- | --- | --- |
| Page direction, drawing, and coordinate conversion | `crengine/src/lvdocview_vert.cpp` | Vertical-rl has swapped physical axes and right-to-left column progression. It is a standalone translation unit; upstream `lvdocview.cpp` retains only the necessary dispatches. | `vertical_horizontal_rtl_spec.lua`, selection and coordinate specs |
| Font metrics, glyph placement, and vertical decorations | `crengine/src/lvfntman_vert.cpp` | Japanese vertical metrics and fallback positioning are not part of upstream's horizontal renderer. The painter for vertical text decorations also lives here; the shared font manager retains only its run-level calls. | vertical glyph, ruby, TCY, and decoration specs |
| Text formatting and line construction | `crengine/src/lvtextfm_vert.cpp` | Column building, ruby, punctuation, and tate-chu-yoko require a vertical formatting path. It is deliberately included into `lvtextfm.cpp`: its helpers depend on the private `LVFormatter` implementation and must not be made public merely to create a separate translation unit. | `vertical_*` layout specs |
| Final-cascade logical CSS sides | `crengine/include/lvlogical_cascade.h`, a private `setNodeStyle` helper in `lvrend.cpp`, and logical-side dispatch in `lvstsheet.cpp` | Replay the cascade only when logical declarations' applied axes disagree with the final cascaded writing mode; preserve physical/logical order and importance without changing common stylesheet APIs. | `vertical_logical_cascade_spec.lua` (rendered geometry, including horizontal and generated-content cases), `tests/fork_render_helpers_test.cpp` (transient flags) |
| Collapsed-table border lookup | `crengine/include/lvrend_table_edges.h`, called from `lvrend.cpp` | Index boundary intervals rather than scan every cell pair; prefix maxima handle overlapping spans and insertion order preserves border ties. | `tests/fork_render_helpers_test.cpp`, vertical table specs |
| Rotated-run buffer growth | `crengine/include/lvfntman_vert_buffer.h`, called from `lvfntman.cpp` | Preserve rows while allowing a rotated run's advance to exceed its measured allocation; retain the existing shaping/drawing loop. | `tests/fork_render_helpers_test.cpp`, vertical rotation specs |
| Ordinary vertical glyph origin (experimental) | `LVFontVertBodyMetricsCache` in `lvfntman_vert.cpp`, called from `lvfntman.cpp` | Preserve the unhinted vertical origin and subtract the raster bitmap bearing, rather than using hinted vertical bearings as bitmap positions. Punctuation and missing-vertical-metrics fallback are unchanged. | TBMincho runtime capsule trace at 22/32/40px; existing vertical layout specs (not a dedicated origin regression) |
| Rendering diagnostics | `crengine/src/lvrend_vert_diag.cpp` | Debug-only instrumentation for tategumi rendering. | manual diagnostic use |

Small integration points in upstream-owned files should only dispatch to these
owners; avoid duplicating vertical algorithms there.

The physical separation status is intentional:

- `lvdocview_vert.cpp` and `lvfntman_vert.cpp` are standalone sources and must
  be listed in every supported build manifest (CMake, qmake, Android).
- `lvtextfm_vert.cpp` stays an end-of-file include until a small, internal
  formatter boundary can be introduced without exporting `LVFormatter`.
- Do not move HarfBuzz shaping or per-glyph placement loops out of
  `lvfntman.cpp`: they share fallback and glyph-buffer state with horizontal
  shaping, so a superficial extraction increases both call overhead and merge
  risk.

## Focused regression checks

`vertical_logical_cascade_spec.lua` shares baseline renders and exercises a full
padding cascade matrix, with targeted margin/border, horizontal-order, and
pseudo-element cases. Assertions use character-box geometry rather than native
implementation details. `reader_vertical_navigation_spec.lua` separately covers
reopening explicit LTR and same-value RTL choices, progression/tap-zone direction,
and mixed-page selection with restoration of the initial anchor.

The **Native render helpers** workflow automatically runs the standalone native
regressions when the top-level `base` gitlink or the workflow changes. It checks
out only `base` and its CRengine submodule and compiles only the helper test with
AddressSanitizer and UndefinedBehaviorSanitizer on Linux; neither the full engine
nor the reader is built or sanitizer-instrumented by this job. See
[Unit tests](Unit_tests.md#standalone-native-render-helpers) for the local command.
The native tests cover buffer contents and growth, transient CSS cascade flags,
table adjacency, overlapping spans (prefix maxima), and original-order border
ties. These are correctness tests, not a rendering performance benchmark; no
wall-clock speedup is claimed. Measure real rendering separately before making
performance claims.

## Review at each upstream sync

Run these checks before resolving conflicts and record notable results in the
sync PR description:

```sh
git fetch upstream --prune
git diff --name-only upstream/master...HEAD
git -C base/thirdparty/kpvcrlib/crengine diff --name-only <last-upstream-crengine>...HEAD
rg -n 'FORK \(tategumi\)|FORK:' base/thirdparty/kpvcrlib/crengine/crengine/src
rg -n '#include ".*_vert\.cpp"' base/thirdparty/kpvcrlib/crengine/crengine/src
```

For every conflict in an upstream-owned CRengine file, decide one of:

- move the tategumi behavior into its `*_vert.cpp` owner;
- extract an upstream-neutral prerequisite and propose it upstream; or
- retain the integration point, with a comment and a regression test.

### October 2026 synchronization

- Merged KOReader `b44e9b791` and koreader-base `c7a6ff708`; the fork's
  CRengine already contains upstream `517b8f0a`.
- Retained the fork's release workflow and channel-specific OTA servers.
  Kept the fork's macOS workflow in `build-macos.yml`, leaving `build.yml`
  available for upstream's reusable build workflow and its callers.
- Retained `RELEASE_TAG` for fork releases while adopting upstream's
  `git describe --match='v[0-9]*'` fallback.
- Restored conflicting fork-owned pins directly into the index during automatic
  sync. A clean, non-recursive checkout reproduced the failed `base` merge and
  verified that `git restore` resolves it without initializing the submodule.
- Upstream documentation, translation, and OTA publication jobs run only in
  `koreader/koreader`; this fork uses its existing release publication workflow.

## Candidate upstream contributions

These should be proposed separately from vertical Japanese behavior when they
are generally useful:

- CSS parsing or cascade correctness fixes independent of writing direction;
- EPUB compatibility parsing that remains CSS-overridable;
- cache invalidation/serialization fixes with no vertical-layout semantics;
- font metadata inspection APIs that do not alter font selection or rendering.

Do not upstream Japanese-specific vertical line breaking, punctuation placement,
or page-coordinate behavior without a separately agreed generic writing-mode
design.
