#!/bin/sh

set -eu

jq -e '
  .manifest_version == 2 and
  .id == "koreader-tategumi" and
  (.packages | keys | sort == ["koreader-tategumi", "koreader-tategumi-nightly"])
' kpm/manifest.json >/dev/null

for package_id in koreader-tategumi koreader-tategumi-nightly; do
    source_dir="kpm/source/${package_id}"
    package="kpm/packages/${package_id}/artifacts/${package_id}_1.0.0_kindlehf-kindlepw2.kpkg"

    test -f "$package"
    jq -e --arg id "$package_id" '
      .manifest_version == 2 and
      .id == $id and
      (.supported_platforms | sort == ["kindlehf", "kindlepw2"])
    ' "$source_dir/manifest.json" >/dev/null

    for file in "$source_dir"/channel "$source_dir"/*.sh "$source_dir"/scriptlets/*.sh; do
        relative_path=${file#"$source_dir"/}
        tar -tzf "$package" | grep -Fx "$relative_path" >/dev/null
        tar -xOzf "$package" "$relative_path" | cmp -s - "$file"
        case "$file" in
            *.sh) sh -n "$file" ;;
        esac
    done
done
