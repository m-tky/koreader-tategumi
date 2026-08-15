#!/bin/sh

set -eu

for package_id in koreader-tategumi koreader-tategumi-nightly; do
    source_dir="kpm/source/${package_id}"
    artifact_dir="kpm/packages/${package_id}/artifacts"
    artifact="${artifact_dir}/${package_id}_1.0.0_kindlehf-kindlepw2.kpkg"

    mkdir -p "$artifact_dir"
    tar -C "$source_dir" -czf "$artifact" \
        channel install.sh launch.sh manifest.json scriptlets uninstall.sh
done
