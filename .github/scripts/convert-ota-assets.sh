#!/usr/bin/env bash

# Like upstream's .ci/ota_assets_generate.sh, derive OTA archives from the ZIPs
# at publication time. Keep the fork's channel URLs and versioned filenames.
set -euo pipefail

if [[ $# != 3 || ! $2 =~ ^(nightly|stable)$ || ! $3 =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Usage: $0 ARTIFACTS_DIR nightly|stable VERSION" >&2
    exit 1
fi

artifacts_dir=$1
channel=$2
version=$3
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
shopt -s globstar nullglob
converted=0

for zip in "${artifacts_dir}"/**/*-latest-"${channel}".zip; do
    name=${zip##*/}
    model=${name#koreader-}
    model=${model%-latest-"${channel}".zip}
    case "${model}" in
        cervantes | kindle | kindle-legacy | kindlehf | kindlepw2 | kobo | kobov5 | pocketbook | pocketbookhf | remarkable | remarkable-aarch64) ;;
        *) continue ;;
    esac

    stem=${zip%.zip}
    versioned_stem=${stem%-latest-"${channel}"}-${version}
    # Preserve the ZIP's embedded manifest and timestamps for kotasync.
    bash "${repo_dir}/tools/mkrelease.sh" --jobs "${PARALLEL_JOBS:-3}" \
        "${versioned_stem}.tar.xz" "${zip}"

    opts=()
    patterns=()
    # Old updaters have different extraction roots / supported payloads.
    case "${model}" in
        kobo*)
            opts=(--manifest=koreader/ota/package.index)
            patterns=('-x!koreader.png')
            ;;
        pocketbook*)
            opts=(--manifest=applications/koreader/ota/package.index '--manifest-transform=s/^/..\//')
            patterns=('-x!system')
            ;;
    esac
    bash "${repo_dir}/tools/mkrelease.sh" --jobs "${PARALLEL_JOBS:-3}" \
        "${opts[@]}" "${stem}.targz" "${zip}" "${patterns[@]}"
    converted=$((converted + 1))
done

if [[ ${converted} == 0 ]]; then
    echo "No device ZIPs found for channel ${channel} in ${artifacts_dir}" >&2
    exit 1
fi
