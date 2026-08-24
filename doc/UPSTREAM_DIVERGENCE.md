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
   or a documented manual fixture when rendering assertions are impractical.

## CRengine boundary

| Area | Fork-only owner | Why it remains local | Regression coverage |
| --- | --- | --- | --- |
| Page direction, drawing, and coordinate conversion | `crengine/src/lvdocview_vert.cpp` | Vertical-rl has swapped physical axes and right-to-left column progression. It is a standalone translation unit; upstream `lvdocview.cpp` retains only the necessary dispatches. | `vertical_horizontal_rtl_spec.lua`, selection and coordinate specs |
| Font metrics, glyph placement, and vertical decorations | `crengine/src/lvfntman_vert.cpp` | Japanese vertical metrics and fallback positioning are not part of upstream's horizontal renderer. The painter for vertical text decorations also lives here; the shared font manager retains only its run-level calls. | vertical glyph, ruby, TCY, and decoration specs |
| Text formatting and line construction | `crengine/src/lvtextfm_vert.cpp` | Column building, ruby, punctuation, and tate-chu-yoko require a vertical formatting path. It is deliberately included into `lvtextfm.cpp`: its helpers depend on the private `LVFormatter` implementation and must not be made public merely to create a separate translation unit. | `vertical_*` layout specs |
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
