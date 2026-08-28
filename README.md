# wift

`wift` runs single-file Swift scripts and caches their compiled executables, avoiding recompilation when the script
and toolchain have not changed.

The project is under active development.

## Development

Swift is provided by the active Xcode toolchain. The project currently targets Swift 6.2 or newer. `mise` installs
the pinned SwiftFormat and SwiftLint versions:

```bash
mise install
mise run check
```

## License

MIT

