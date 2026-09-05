#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
release_dir="${1:-$PWD/.build/release-assets}"
case "$release_dir" in
  /*) ;;
  *) printf 'release output directory must be absolute\n' >&2; exit 1 ;;
esac
arch=$(uname -m)
case "$arch" in
  arm64|x86_64) ;;
  *) printf 'unsupported release architecture: %s\n' "$arch" >&2; exit 1 ;;
esac

swift build -c release --product wift --force-resolved-versions
wift_binary="$(swift build -c release --show-bin-path)/wift"
version=$(tr -d '\r\n' < VERSION)
test "$("$wift_binary" --version)" = "wift $version"
test "$(lipo -archs "$wift_binary")" = "$arch"
xcrun vtool -show-build "$wift_binary" | awk '
  $1 == "minos" { found = 1; if ($2 != "13.0") exit 1 }
  END { if (!found) exit 1 }
'

task_temp=$(mktemp -d "${TMPDIR:-/tmp}/wift-release.XXXXXX")
trap 'rm -rf -- "$task_temp"' EXIT
mkdir -p "$task_temp/package/licenses" "$task_temp/unpacked" "$release_dir"
install -m 755 "$wift_binary" "$task_temp/package/wift"
install -m 644 LICENSE "$task_temp/package/LICENSE"
# Include the licenses of the libraries linked into the CLI.
install -m 644 .build/checkouts/swift-argument-parser/LICENSE.txt "$task_temp/package/licenses/ArgumentParser.txt"
install -m 644 .build/checkouts/XcodeProj/LICENSE.md "$task_temp/package/licenses/XcodeProj.txt"
install -m 644 .build/checkouts/PathKit/LICENSE "$task_temp/package/licenses/PathKit.txt"
install -m 644 .build/checkouts/AEXML/LICENSE "$task_temp/package/licenses/AEXML.txt"

archive="wift-v$version-macos-$arch.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$task_temp/$archive" -C "$task_temp/package" wift LICENSE licenses
tar -xzf "$task_temp/$archive" -C "$task_temp/unpacked"
test "$("$task_temp/unpacked/wift" --version)" = "wift $version"
cat > "$task_temp/smoke.swift" <<'SWIFT'
import Wift
print(try cmd("/usr/bin/printf", "%s", "wift-release").text())
SWIFT
export WIFT_CACHE_DIR="$task_temp/cache"
test "$("$task_temp/unpacked/wift" "$task_temp/smoke.swift")" = 'wift-release'
test "$("$task_temp/unpacked/wift" "$task_temp/smoke.swift")" = 'wift-release'
mv "$task_temp/$archive" "$release_dir/$archive"
printf 'Release archive: %s/%s\n' "$release_dir" "$archive"
