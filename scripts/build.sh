#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo 'Usage: build.sh [debug|release]' >&2; exit 2;; esac
cd "$repo_dir"
swift build -c "$configuration" --product OpenSketch
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
bundle_dir="$repo_dir/build/OpenSketch.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$binary_dir/OpenSketch" "$bundle_dir/Contents/MacOS/OpenSketch"
cp "$repo_dir/Resources/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$repo_dir/Resources/AppIcon/AppIcon.icns" "$bundle_dir/Contents/Resources/AppIcon.icns"
resource_bundle="OpenSketch_OpenSketchUI.bundle"
if [ ! -d "$binary_dir/$resource_bundle" ]; then
    echo "Missing localization resource bundle: $binary_dir/$resource_bundle" >&2
    exit 1
fi
ditto "$binary_dir/$resource_bundle" "$bundle_dir/Contents/Resources/$resource_bundle"
for language in en zh-Hans; do
    ditto "$repo_dir/Resources/$language.lproj" "$bundle_dir/Contents/Resources/$language.lproj"
done
rm -rf "$bundle_dir/Contents/Resources/Licenses"
codesign --force --sign - "$bundle_dir"
codesign --verify --strict "$bundle_dir"
echo "$bundle_dir"
