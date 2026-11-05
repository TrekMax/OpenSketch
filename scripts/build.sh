#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
case "$configuration" in debug|release) ;; *) echo 'Usage: build.sh [debug|release]' >&2; exit 2;; esac
cd "$repo_dir"
swift build -c "$configuration" --product openSketch
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
bundle_dir="$repo_dir/build/openSketch.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$binary_dir/openSketch" "$bundle_dir/Contents/MacOS/openSketch"
cp "$repo_dir/Resources/Info.plist" "$bundle_dir/Contents/Info.plist"
codesign --force --sign - "$bundle_dir"
codesign --verify --strict "$bundle_dir"
echo "$bundle_dir"
