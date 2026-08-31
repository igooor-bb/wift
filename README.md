# wift

[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)

**A lightweight, fast, and minimal runner for single-file Swift scripts.**

Swift already supports scripting: you can run a source file directly with `swift script.swift`. However, Swift compiles that source on every launch and does not cache the resulting executable. For scripts used repeatedly by developers or CI jobs, that compilation quickly becomes noticeable overhead.

Shell is a great fit for small command chains. As automation grows, Swift offers compelling advantages: static types, structured error handling, modern concurrency, and rich platform APIs can make scripts easier to evolve and safer to maintain, while keeping the convenience of a single source file.

`wift` keeps the same simple scripting workflow, but compiles each script once and stores the executable in a content-addressed cache. Cache hits launch the existing executable directly, making repeated runs fast. The tool deliberately stays small: no generated projects, package management, daemon, or background service.

## Requirements

- macOS 13 or newer
- Swift 6.2 or newer from the active Xcode toolchain
- [`mise`](https://mise.jdx.dev/) for the repository commands below

## Installation

From a local checkout:

```bash
mise run install
wift --version
```

This installs `wift` into `~/.local/bin` without `sudo`. Make sure that directory is on your `PATH`. To remove it later, run `mise run uninstall`.

## Quick start

Create `hello.swift`:

```swift
let name = CommandLine.arguments.dropFirst().first ?? "world"

print("Hello, \(name)!")
```

Run it:

```console
$ wift hello.swift Swift
Hello, Swift!
```

The first run compiles the script. Later runs launch the cached executable directly while the script and toolchain remain unchanged.

## Usage

Everything after the script path is passed to the script unchanged:

```bash
wift script.swift one --two three
```

### Shebang scripts

Add a shebang to run a script directly:

```swift
#!/usr/bin/env wift

print("Hello from wift!")
```

Then make it executable and launch it:

```bash
chmod +x script.swift
./script.swift
```

Shebang scripts may also use extensionless names such as `scripts/add`.

### Built-in scripting API

Swift's standard APIs are intentionally general-purpose, while scripts often repeat a small set of process-oriented tasks. The built-in `Wift` module reduces that boilerplate with focused APIs for launching commands, capturing output, composing pipelines, and accessing script context. It keeps Swift's explicit, typed model while making common automation concise.

Every script can import the built-in `Wift` module without a `Package.swift` or additional dependencies:

```swift
#!/usr/bin/env wift

import Wift

try cmd("git", "--version").run()

let branch = try cmd("git", "branch", "--show-current").text()
let files = try cmd("find", ".", "-name", "*.swift")
    .pipe(to: cmd("sort"))
    .lines()
```

Commands use argument arrays rather than shell parsing and are checked by default. Shell evaluation is available through the explicit `shell(...)` and `shell(raw:)` APIs. The module also supports captured output, pipelines, async execution, streaming, cancellation, script metadata, and stderr helpers.

See [`Examples/Wift.swift`](Examples/Wift.swift) for a complete example.

## Diagnostics and cache

Normal execution is silent apart from compiler diagnostics and script output. Use verbose mode to inspect compiler resolution, cache activity, and execution:

```bash
wift --verbose script.swift one two
```

`wift` diagnostics use the `wift:` prefix and go to stderr. Options after the script path still belong to the script.

| Command | Purpose |
| --- | --- |
| `wift cache` | Show a cache summary and logical sizes |
| `wift cache path` | Print the cache directory |
| `wift cache info script.swift` | Inspect cached variants without compiling |
| `wift cache clean script.swift` | Remove cached variants associated with one script path |
| `wift cache clean` | Remove the complete managed cache |

The default cache is `~/Library/Caches/wift`. Set `WIFT_CACHE_DIR` to use a dedicated cache directory, for example in tests or CI.

### Reusing cache across paths

The cache is content-addressed rather than tied to a source path. Two identical scripts share the same cached executable even when they live in different checkout directories, provided their compiler, target, SDK, and other compilation inputs also match.

This makes the cache effective in CI environments with multiple runners: a runner can restore the managed cache under a different checkout or cache-root path and reuse executables compiled by another runner. The script still receives its own launch-specific path at runtime.

## How it works

`wift` fingerprints the script contents together with the active compiler, target, SDK, compiler configuration, and built-in `Wift` API. Source and cache-storage paths are not part of that identity. A matching fingerprint reuses the existing executable; a new fingerprint triggers compilation and creates a new cache entry.

When the executable is ready, it replaces the `wift` process. The script therefore keeps the current arguments, environment, working directory, standard streams, signals, and exit status, just like a directly launched executable.

Cache entries are private to the current user and validated before execution. Because `swiftc` is selected from `PATH`, use a trusted `PATH` as you would when invoking the compiler directly.

## Current limitations

`wift` is a single-file script runner, not a package or dependency manager. It currently does not support:

- SwiftPM dependencies or generated `Package.swift` files
- user-supplied compiler flags
- multi-file scripts
- automatic cache eviction
- remote caching or background services

## Development

Install the pinned development tools and run the project checks:

```bash
mise install
mise run check
```

For a manual end-to-end run from a checkout:

```bash
mise run wift Examples/Hello.swift
mise run wift Examples/Arguments.swift one --two three
```

## Benchmarks

The end-to-end benchmark suite compares release builds of `wift`, cached executables, ordinary Swift scripts, and shell scripts. See [Benchmarks](Benchmarks/README.md) for scenarios, methodology, and commands.

## Contributing

Contributions are welcome through the usual fork-and-pull workflow:

1. Fork the repository and create a focused branch.
2. Make your changes and run `mise run check`.
3. Open a pull request with a short explanation of what changed and why.

Please keep contributions small and aligned with `wift`'s lightweight, fast, and minimal design.

## License

**wift** is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
