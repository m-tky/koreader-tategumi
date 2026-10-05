#!/usr/bin/env python3
"""Exercise publish-time ZIP conversion with small, realistic device payloads."""

import os
import pathlib
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONVERTER = ROOT / ".github/scripts/convert-ota-assets.sh"
MODELS = (
    "kindle", "kindle-legacy", "kindlehf", "kindlepw2", "kobo", "kobov5",
    "pocketbook", "pocketbookhf", "cervantes", "remarkable", "remarkable-aarch64",
)


def write_zip(path, model, version):
    pocketbook = model.startswith("pocketbook")
    reader = "applications/koreader" if pocketbook else "koreader"
    manifest = f"{reader}/ota/package.index"
    files = {
        f"{reader}/git-rev": f"{version}_{model}\n",
        f"{reader}/koreader.sh": "#!/bin/sh\nexit 0\n",
        f"{reader}/reader.lua": "-- fixture\n",
    }
    if model.startswith("kindle"):
        files["extensions/koreader/bin/launcher"] = "launcher\n"
        if model == "kindle-legacy":
            files["launchpad/launcher"] = "launcher\n"
    elif model.startswith("kobo"):
        files["koreader.png"] = "icon\n"
    elif pocketbook:
        files["applications/koreader.app"] = "launcher\n"
        files["system/bin/koreader.app"] = "launcher\n"
    index = "".join(f"{name}\n" for name in sorted((*files, manifest))
                    if name != "koreader.png" and not name.startswith("system/"))
    files[manifest] = index
    with zipfile.ZipFile(path, "w") as archive:
        for name, content in files.items():
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 4, 12, 0, 0))
            info.external_attr = (0o100755 if name.endswith(".sh") else 0o100644) << 16
            archive.writestr(info, content)
    return files, manifest


class OTAAssets(unittest.TestCase):
    def convert(self, directory, channel, version):
        return subprocess.run(
            ["bash", str(CONVERTER), str(directory), channel, version], cwd=ROOT,
            env={**os.environ, "PARALLEL_JOBS": "1"}, capture_output=True, text=True,
        )

    def test_both_channels(self):
        for channel, version in (("nightly", "v2026.10.04-144"), ("stable", "v2026.10")):
            with self.subTest(channel=channel), tempfile.TemporaryDirectory() as tmp:
                artifacts = pathlib.Path(tmp)
                sources = {}
                for model in MODELS:
                    directory = artifacts / model
                    directory.mkdir()
                    path = directory / f"koreader-{model}-latest-{channel}.zip"
                    sources[model] = write_zip(path, model, version)
                # Android APK/link updates must not be converted as device ZIPs.
                android = artifacts / "android-arm"
                android.mkdir()
                (android / f"koreader-android-latest-{channel}.zip").write_bytes(b"ignored")
                result = self.convert(artifacts, channel, version)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(list(artifacts.rglob("*.tar.xz"))), len(MODELS))
                self.assertEqual(len(list(artifacts.rglob("*.targz"))), len(MODELS))
                for model in MODELS:
                    with self.subTest(model=model):
                        directory = artifacts / model
                        files, manifest = sources[model]
                        # New OTA keeps the ZIP payload and embedded manifest intact.
                        txz = directory / f"koreader-{model}-{version}.tar.xz"
                        with tarfile.open(txz) as archive:
                            self.assertEqual(set(archive.getnames()), set(files))
                            for name, content in files.items():
                                self.assertEqual(archive.extractfile(name).read(), content.encode())
                            script = next(name for name in files if name.endswith(".sh"))
                            self.assertEqual(archive.getmember(script).mode, 0o755)
                        tgz = directory / f"koreader-{model}-latest-{channel}.targz"
                        with tarfile.open(tgz) as archive:
                            expected = set(files)
                            if model.startswith("kobo"):
                                expected.remove("koreader.png")
                            elif model.startswith("pocketbook"):
                                expected.remove("system/bin/koreader.app")
                            self.assertEqual(set(archive.getnames()), expected)
                            index = archive.extractfile(manifest).read().decode()
                            if model.startswith("pocketbook"):
                                self.assertEqual(index, "".join(f"../{name}\n" for name in sorted(expected)))
                            elif model.startswith("kobo"):
                                self.assertEqual(index, "".join(f"{name}\n" for name in sorted(expected)))
                            else:
                                self.assertEqual(index, files[manifest])
                # Only publishing changes: the original downloadable ZIPs remain intact.
                for model in MODELS:
                    path = artifacts / model / f"koreader-{model}-latest-{channel}.zip"
                    with zipfile.ZipFile(path) as archive:
                        files, _ = sources[model]
                        self.assertEqual({name: archive.read(name).decode() for name in archive.namelist()}, files)

    def test_missing_and_corrupt_zips_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifacts = pathlib.Path(tmp)
            result = self.convert(artifacts, "nightly", "v2026.10.04-144")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("No device ZIPs found", result.stderr)
            (artifacts / "kobo").mkdir()
            (artifacts / "kobo/koreader-kobo-latest-nightly.zip").write_bytes(b"not a zip")
            self.assertNotEqual(self.convert(artifacts, "nightly", "v2026.10.04-144").returncode, 0)


if __name__ == "__main__":
    unittest.main()
