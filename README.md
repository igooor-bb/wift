# wift

`wift` runs single-file Swift scripts and caches their compiled executables, avoiding recompilation when the script and toolchain have not changed.

## Usage

```bash
wift script.swift
wift script.swift one --two three
```

Every argument after the script path is passed through without interpretation. The cached executable receives the script's canonical path as `argv[0]`.

For a shebang script:

```swift
#!/usr/bin/env wift

print("Hello")
```

make the file executable and run it directly:

```bash
chmod +x script.swift
./script.swift
```

> To try a local checkout manually, run `mise run wift Examples/Hello.swift`. This is a convenience wrapper around `swift run wift <script> [arguments...]`; for example, `mise run wift Examples/Arguments.swift one --two three`.

## How it works

`wift` resolves `swiftc` from the current `PATH`, identifies the active compiler, target, and SDK, then derives a deterministic SHA-256 fingerprint:

```text
source + canonical path + toolchain + target/SDK + compiler configuration
                                  ↓
                            cache key
                                  ↓
                         cached executable
```

On a cache miss, `swiftc` compiles into a staging directory inside the cache. `wift` writes diagnostic metadata and atomically renames the complete entry into place. A persistent Swift module cache is shared across compilations.

Concurrent misses for the same key use an advisory `flock` and recheck the cache after acquiring it, so only one process compiles. Once an executable is available, `execv` replaces `wift`; stdin, stdout, stderr, environment, working directory, signals, and exit status therefore retain normal Unix semantics.

Successful runs are silent apart from the script's own output and compiler diagnostics.

## Cache semantics

The default cache is the system user cache directory (`~/Library/Caches/wift` on macOS). Entries are sharded by the first two characters of their content-addressed key. Changing any of these values invalidates an entry:

- script contents;
- canonical script path;
- `swiftc` path or version;
- target or SDK;
- compiler arguments used by `wift`;
- fingerprint schema.

`WIFT_CACHE_DIR` can point to a dedicated cache directory, primarily for isolated environments and tests. The cache root must be owned by the current user and inaccessible to group and other users. `wift` rejects symlink executables, non-regular artifacts, foreign ownership, and group/world-writable cache binaries. Compiler and script arguments are passed directly to `Process`/`execv`; no shell evaluates them.

`swiftc` is intentionally selected from `PATH`, so use a trusted `PATH` just as when invoking the compiler directly.

## Current limitations

`wift` is not a package or dependency manager. The current version supports one source file and a fixed compiler configuration. It does not provide:

- SwiftPM dependencies or generated `Package.swift` files;
- user-supplied compiler flags or dependency scanning;
- multi-file scripts;
- cache eviction or automatic size management;
- remote caching or background services.

## Development

Swift is provided by the active Xcode toolchain. The project targets Swift 6.2 or newer. `mise` installs the pinned SwiftFormat and SwiftLint versions:

```bash
mise install
mise run check
```

The underlying checks can also be run directly:

```bash
swift build
swift test
swiftformat --lint .
swiftlint
```

## License

MIT
