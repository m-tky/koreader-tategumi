# KOReader Tategumi KPM repository

This directory is a static KPM repository. It is deliberately served from the
repository's raw GitHub URL; GitHub Pages is not required.

On a Kindle with KPM, add it once:

```text
;kpm add-repo https://raw.githubusercontent.com/m-tky/koreader-tategumi/master/kpm/manifest.json
```

Then install one channel:

```text
;kpm install koreader-tategumi
;kpm install koreader-tategumi-nightly
```

The packages share `/mnt/us/koreader`; installing either channel replaces the
currently installed program files while leaving user settings intact. Do not
install both channels as separate active copies. Re-run the desired `install`
command to switch channel or fetch a newer build. `uninstall` only removes the
matching KPM launcher scriptlet; it intentionally preserves KOReader and its
settings.

`source/` holds the package sources. The tracked `.kpkg` artifacts are generated
by `build-packages.sh`; it deliberately emits KPM manifest v2 packages, because
the KPM 0.2.x release shipped on current Kindle devices supports v2, not v3.
