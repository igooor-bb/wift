# Repository guide

`wift` is a macOS command-line runner for single-file Swift scripts. It compiles a script once, caches the executable by a deterministic fingerprint, and replaces itself with that executable on every run. Its defining experience should be fast and seamless, as close as possible to running the script directly. Keep the tool small, predictable, and Unix-like; it is not a package manager or a general build system.

## Stable contracts

- Use Swift 6.2 or newer and keep the declared macOS deployment target working.
- Parse `wift` options with Swift Argument Parser. After the script path, pass every argument through unchanged.
- Normal execution is silent except for compiler diagnostics and script output. Verbose diagnostics use the `wift:` prefix and stderr only.
- Preserve stdin, stdout, stderr, environment, working directory, signals, `argv[0]`, and exit status when handing control to the cached executable.
- Derive cache identity from every content input that can change the executable: source bytes, compiler/toolchain identity, target/SDK, semantic compiler configuration, support fingerprint, and fingerprint schema. Canonical source and cache-storage paths are not identity inputs.
- Compile verified source bytes as the relative input `script.swift` from private staging storage. `#filePath` is therefore stable, while the launch-specific canonical path remains available through `argv[0]` and `Script.path`.
- Build in private staging storage and publish complete entries atomically. Concurrent callers must coordinate, recheck after locking, and never observe partial artifacts.
- Associate canonical paths with shared content-addressed entries under the entry lock. Inspection commands do not compile; script-specific cleanup removes only that path's associations and retains an entry until its last association is removed. Full cleanup affects only a verified managed cache.

## Engineering principles

- Prefer the smallest cohesive change that fully preserves the contracts above. Avoid speculative layers and features outside the requested scope.
- Treat startup latency and transparency as product requirements. Keep the common cache-hit path lean, avoid unnecessary process launches and I/O, and measure before accepting complexity for performance.
- Keep policy separate from filesystem, process, locking, and exec mechanisms so security-sensitive behavior remains reviewable and testable.
- Model invalid or unsafe states explicitly and fail with actionable errors. Do not silently fall back when doing so could execute or delete the wrong file.
- Actively consider modern, stable Swift capabilities and prefer them when they make the design safer, clearer, or more expressive. Use them deliberately rather than for novelty alone.
- Choose value or reference semantics from the identity, ownership, lifetime, and mutation requirements of the case. Keep APIs narrow, dependencies explicit, and output deterministic; avoid uncontrolled shared mutable state and unstructured concurrency.
- Use the repository SwiftFormat and SwiftLint configurations. Match established naming and error-reporting style.

## Built-in scripting API

- Keep the scripting API process-first, compact, cohesive, and free of unnecessary dependencies.
- Prefer immutable values and explicit, readable composition over implicit behavior, operator magic, and abstraction-heavy DSL machinery.
- Make common operations safe and checked by default. Unsafe, unchecked, unbounded, or shell-evaluated behavior must be deliberate and visible at the call site.
- Keep semantics consistent across synchronous, asynchronous, streaming, and composed execution. Cancellation and resource cleanup are part of the API contract.
- Keep public values easy to compose and resilient to evolution. Introduce ownership or layout constraints only when they provide a clear user benefit.
- Apply modern Swift features and performance optimizations selectively, based on measurements of real artifacts and compilation latency rather than source-level assumptions.
- Document every public symbol with valid SwiftDocC comments and keep examples aligned with actual behavior. Test library semantics natively and reserve integration tests for genuine system boundaries.

## Security rules

- Treat script paths, arguments, compiler paths, cache paths, and environment values as data rather than shell syntax. Prefer argument arrays and direct process/exec APIs; when a shell is genuinely required, define the trust boundary and escape or constrain every externally controlled value explicitly.
- Treat `PATH`, the source file, cache contents, metadata, and symlinks as untrusted input. Canonicalize where identity matters and validate ownership, type, permissions, and containment before use.
- Keep cache directories and artifacts private to the current user. Do not follow symlinks while inspecting, executing, or deleting cached files.
- Coordinate cache reads, publication, execution, and cleanup with locks whose lifetime covers the protected operation. Prevent file descriptors from leaking across `exec`.
- Make deletion defensive: resolve the exact target, reject critical or unmanaged directories, and never broaden cleanup because validation failed.

## Tests and workflow

- Add focused unit tests for pure policy and integration tests for observable command behavior. Every bug fix should include a regression test.
- Test real process boundaries where they matter: argument forwarding, stdout/stderr separation, environment and cwd, exit codes, shebangs, cache invalidation, cleanup, and contention. Make concurrency tests deterministic; do not rely on sleeps.
- Install pinned development tools with `mise install`.
- Run `mise run check` before finishing; it covers formatting, linting, and tests. Also run `swift build` when changing package or production build behavior.
- Use `mise run wift Examples/<script>.swift` for a manual end-to-end check when command execution changes.
- Keep documentation and examples aligned with user-visible behavior. Do not claim an unrun check passed.
- Preserve unrelated local changes. Use small Conventional Commits that describe one logical change; do not rewrite published history unless explicitly requested.
