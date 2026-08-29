# wift

`wift` runs single-file Swift scripts and caches their compiled executables, avoiding recompilation when the script and toolchain have not changed.

## Usage

```bash
wift script.swift
wift script.swift one --two three
wift --verbose script.swift
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

The shebang also allows extensionless script names such as `scripts/add`. When a shebang script does not have a `.swift` extension, `wift` stages its verified contents under a Swift filename for compilation while preserving the original canonical path as `argv[0]` and `Script.path`.

## Built-in scripting library

Every script can import the built-in `Wift` module without a `Package.swift` or extra installation files:

```swift
#!/usr/bin/env wift

import Wift

try checkRun("git", "--version")
let result = try capture("git", "status", "--short")
print(result.stdout, terminator: "")
```

The public helpers are:

- `run(_:_:...)` and `run(_:arguments:)` to inherit standard streams and return the command status;
- `checkRun(_:_:...)` to throw `CommandFailure` on a nonzero status;
- `capture(_:_:...)` to collect stdout and stderr concurrently without trimming them;
- `which(_:)` to find an executable directly from `PATH`;
- `eprint(_:)` and `die(_:status:)` for stderr diagnostics and termination;
- `Script.path` and `Script.directory` for the canonical source location.

`import Wift` is a small, fixed scripting API bundled into the `wift` executable. It is not a mechanism for importing arbitrary SwiftPM dependencies.

Run the complete example with `mise run wift Examples/Wift.swift`.

> To try a local checkout manually, run `mise run wift Examples/Hello.swift`. This is a convenience wrapper around `swift run wift <script> [arguments...]`; for example, `mise run wift Examples/Arguments.swift one --two three`.

## Installation

From a local checkout, build and install a release executable into `~/.local/bin`:

```bash
mise run install
wift --version
```

The destination is the conventional per-user binary directory and does not require `sudo`. To remove the installed executable, run `mise run uninstall`.

## How it works

`wift` resolves `swiftc` from the current `PATH`, identifies the active compiler, target, and SDK, then derives a deterministic SHA-256 fingerprint:

```text
source + canonical path + toolchain + target/SDK + compiler configuration + Wift support fingerprint
                                  ↓
                            cache key
                                  ↓
                         cached executable
```

The built-in library is maintained separately from the CLI at [`Sources/WiftLibrary/Wift.swift`](Sources/WiftLibrary/Wift.swift). The executable target explicitly compiles only `Sources/Wift`; SwiftPM's `embedInCode` rule packages the library file's bytes directly into the runner without making its declarations part of the CLI module or creating a resource bundle. For each compiler, target, SDK, and support configuration, `wift` atomically builds and caches a static `Wift.swiftmodule` and `Wift.o`. Script compilation receives the module search path and links the object directly, so cached script executables have no dynamic dependency on the support cache or on files beside the installed `wift` binary.

On a cache miss, `swiftc` compiles into a staging directory inside the cache. `wift` writes diagnostic metadata and atomically renames the complete entry into place. A persistent Swift module cache is shared across compilations.

Concurrent misses for the same key use an advisory `flock` and recheck the cache after acquiring it, so only one process compiles. Once an executable is available, `execv` replaces `wift`; stdin, stdout, stderr, environment, working directory, signals, and exit status therefore retain normal Unix semantics.

Successful runs are silent apart from the script's own output and compiler diagnostics.

## Diagnostics

Use `-v` or `--verbose` before the script path to inspect resolution, cache lookup, compilation, lock contention, and the final `exec`:

```bash
wift --verbose script.swift one two
```

Diagnostics from `wift` use the `wift:` prefix and go to stderr. The script's stdout remains unchanged. Once the script path has been parsed, all remaining options belong to the script, so `wift --verbose script.swift --verbose` enables diagnostics and also passes `--verbose` to the script.

## Cache management

```bash
wift cache                         # summary and logical sizes
wift cache path                    # absolute cache path only
wift cache info script.swift       # all variants; marks the current one ACTIVE
wift cache clean script.swift      # remove every variant of this script
wift cache clean                   # remove the entire managed cache
```

`cache info` never compiles the script. It lists every cached variant for the canonical script path, including its compiler, target/SDK, support fingerprint, source freshness, and active state. `cache clean <script>` removes all of those script variants without removing the shared support module. A full `cache clean` removes the support cache as part of the managed cache root.

## Cache semantics

The default cache is the system user cache directory (`~/Library/Caches/wift` on macOS). Entries are sharded by the first two characters of their content-addressed key. Changing any of these values invalidates an entry:

- script contents;
- canonical script path;
- `swiftc` path or version;
- target or SDK;
- compiler arguments used by `wift`;
- the built-in `Wift` support-module fingerprint;
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
