# Legacy OTA migration helper

`otamanager.lua` is a one-time replacement for a legacy vanilla installation's
`frontend/ui/otamanager.lua`. It is based on upstream **v2026.07.1** (commit
`9192014`) and retains the old zsync/tar update protocol. It does not belong in
the normal application package: that package must contain the current updater.

The release and nightly workflows attach this file as `otamanager.lua`. The
helper always downloads the numbered stable release, even when obtained from a
nightly release. The helper is also attached separately to the existing v2026.10
release without rebuilding its application packages or moving its tag.

## Behavior

- Accept only device update type `ota` (legacy zsync), not `kotasync` or `link`.
- Ignore saved vanilla servers/channels without modifying those settings.
- Fetch `koreader-<model>-latest-stable.zsync` from this fork's latest release.
- Use the installed `zsync2`/`spinning_zsync` and tar tooling to prepare
  `ota/koreader.updated.tar`, which the old launch script applies after restart.
- Offer migration even if vanilla and the fork have equal normalized versions;
  retain the old explicit downgrade confirmation for a lower target version.
- Let the installed fork package replace the helper with its normal updater.

If migration is abandoned, restore the original backed-up `otamanager.lua`.
Do not install this helper in an Android APK or a kotasync-based installation.

## Verification record

A legacy fork installation has been updated successfully on a device. Official
vanilla migration remains unverified; do not equate the source baseline or mocked
tests with a completed official-vanilla migration.

| Source version | Verification | Status |
| --- | --- | --- |
| Fork v2026.07.03, Kindle (`kindlepw2` OTA model) | Helper download over SSH; in-app legacy OTA update to fork v2026.10 | Target version confirmed by user, 2026-10-10; see scope below |
| Official v2026.07.1 | Source baseline and isolated mocked updater contract tests | Passed; device migration pending |
| Earlier vanilla versions | Compatibility and device migration | Not tested |

### Device test on 2026-10-10

- The source was **fork v2026.07.03**, not official vanilla. Its existing updater
  already pointed at this fork's GitHub releases and reported update type `ota`.
- The helper was executed over SSH using the installed Lua HTTP stack, real
  Kindle model detection (without a second device/UI initialization), and old
  zsync/tar binaries. UI dependencies were stubbed for this SSH-only probe.
- It detected v2026.10 and produced `ota/koreader.updated.tar` with revision
  `v2026.10_kindlepw2`. Its SHA-1 matched the zsync manifest:
  `233ba816b437f2eda69a34719ff8524ad4773ed3` (87,789,568 bytes).
- The first restart did not change the reported source version. The helper was
  then copied to the normal frontend path, the download repeated, and `sync`
  completed. The reason the first attempt did not apply is unresolved.
- The user subsequently ran **Check for update** in the already-running app and
  confirmed that the restarted app displayed **v2026.10**. That process still had
  the original updater loaded: this confirms legacy OTA installation, not the
  helper's entire replacement-and-UI workflow.
- SSH became unavailable after the update. Replacement of the normal updater,
  subsequent kotasync update checks, and preservation of settings/progress were
  not independently inspected. No backup was made, at the user's request.

Run the isolated tests from the repository root:

```sh
luajit tools/migration/test.lua
```

The tests cover fixed stable routing despite saved vanilla settings, zsync
manifest naming, equal-version migration, newer/lower target versions, legacy
output filename, incremental/full-download command construction, and rejection
of non-legacy update types. Network, filesystem, device APIs, and version parsing
are mocked. LuaJIT syntax loading is also checked during the test.

### Required device checks before declaring a version verified

Record the exact source version, device/model, target fork version, date, and
result. Test at least official v2026.07.1 first; expand the table only after
actually completing each migration.

1. Back up the installation, settings, and book sidecar data; exit KOReader.
2. Install only the helper and restart. Keep a saved vanilla mirror and nightly
   channel to confirm that migration still selects this fork's stable release.
3. Confirm manifest retrieval through GitHub HTTPS redirects using the old Lua
   HTTP stack, and package retrieval with the old zsync binary. Test retry with
   a full download too.
4. Confirm that the old launcher applies `koreader.updated.tar` and restarts into
   the requested fork build, including replacement of the launcher itself.
5. Confirm that settings and reading progress survive, and that the normal
   updater can check for a subsequent fork update using kotasync.
6. Check cancelling the download and restoring the original updater. Check
   equal-version migration when suitable builds are available.

Publishing the helper is not itself evidence that these checks have passed.
