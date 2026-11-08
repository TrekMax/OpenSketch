#!/bin/bash
set -euo pipefail
if [ "$#" -ne 0 ]; then
    echo 'Usage: benchmark.sh (writes build/benchmark/geometry-results.json)' >&2
    exit 2
fi
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$repo_dir/build/benchmark"
architecture="$(uname -m)"
case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 2;; esac
target="$architecture-apple-macosx15.0"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
core_sources=()
while IFS= read -r -d '' source_file; do
    core_sources+=("$source_file")
done < <(find "$repo_dir/Sources/OpenSketchCore" -type f -name '*.swift' -print0)
if [ "${#core_sources[@]}" -eq 0 ]; then
    echo 'No OpenSketchCore Swift sources found' >&2
    exit 1
fi
mkdir -p "$output_dir"
xcrun swiftc -swift-version 6 -O -whole-module-optimization \
    -target "$target" -sdk "$sdk_path" \
    "${core_sources[@]}" \
    "$repo_dir/scripts/GeometryBenchmark.swift" -o "$output_dir/geometry-benchmark"
temporary_result="$(mktemp "$output_dir/geometry-results.XXXXXX")"
trap 'rm -f "$temporary_result"' EXIT
"$output_dir/geometry-benchmark" "$target" > "$temporary_result"
mv "$temporary_result" "$output_dir/geometry-results.json"
cat "$output_dir/geometry-results.json"
