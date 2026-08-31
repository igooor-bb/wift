#!/bin/sh
set -eu

swift build -c release --product wift
wift_binary="$(swift build -c release --show-bin-path)/wift"

printf 'wift benchmark environment\n'
printf '  revision: %s\n' "$(git rev-parse --short HEAD)"
printf '  architecture: %s\n' "$(uname -m)"
sw_vers | sed 's/^/  /'
xcodebuild -version | sed 's/^/  /'
swift --version | sed 's/^/  /'

export WIFT_BENCHMARK_BINARY="$wift_binary"
swift package --allow-writing-to-package-directory benchmark "$@" --target WiftBenchmarks
