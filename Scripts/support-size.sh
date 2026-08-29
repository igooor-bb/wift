#!/bin/sh
set -eu

task_temp=$(mktemp -d "${TMPDIR:-/tmp}/wift-support-size.XXXXXX")
case "$task_temp" in
  "${TMPDIR:-/tmp}"/wift-support-size.*) ;;
  *) printf 'unexpected temporary directory: %s\n' "$task_temp" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$task_temp"' EXIT

swift build >/dev/null
wift_binary="$(swift build --show-bin-path)/wift"
cache="$task_temp/cache"
minimal="$task_temp/minimal.swift"
representative="$task_temp/representative.swift"

cat > "$minimal" <<'SWIFT'
import Wift
print("minimal")
SWIFT

cat > "$representative" <<'SWIFT'
import Wift
let lines = try cmd("/usr/bin/printf", "beta\nalpha\n")
    .pipe(to: cmd("/usr/bin/sort"))
    .lines()
print(lines.joined(separator: ","))
SWIFT

cold_time=$(
  { /usr/bin/time -p env WIFT_CACHE_DIR="$cache" "$wift_binary" "$minimal" >/dev/null; } 2>&1
)
env WIFT_CACHE_DIR="$cache" "$wift_binary" "$representative" >/dev/null

support_object=$(find "$cache/support" -name Wift.o -type f -print -quit)
context_count=$(find "$cache/module-cache" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

printf 'Source: '
source_bytes=$(wc -c < Sources/WiftLibrary/Wift.swift | tr -d '[:space:]')
printf '%s bytes\n' "$source_bytes"
printf 'Support object: %s bytes\n' "$(stat -f '%z' "$support_object")"
size -m "$support_object" | tail -3
printf 'Cached executables:\n'
find "$cache/executables" -name executable -type f -exec stat -f '  %z bytes %N' {} \;
printf 'Cold compile:\n%s\n' "$cold_time"
printf 'Module cache contexts: %s\n' "$context_count"

if [ "$context_count" -ne 1 ]; then
  printf 'expected exactly one compiler module cache context\n' >&2
  exit 1
fi
