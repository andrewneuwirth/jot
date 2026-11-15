# Contributing

Thanks for helping. Read [AGENTS.md](AGENTS.md) first: it explains every source file, where data lives and the rules.

## Build and check

Jot uses MacToolsKit from the [mac-tools-kit](https://github.com/andrewneuwirth/mac-tools-kit) repository. Clone it next to
this folder (`../Kit`) to work on both; otherwise SwiftPM fetches it.

```sh
swift build && .build/debug/Jot --self-check   # must end with "self-check ok"
swift test                                      # unit tests (transcript logic, Space hold, WebM, cleanup guards)
.build/debug/Jot --ui-preview /tmp/jot-shots    # every page and walkthrough step as PNGs, light and dark, made-up data
./build.sh                                      # build/Jot.app
```

The self-check never records, downloads or touches your library: model downloads are tested against a fake backend in a
temporary folder. Don't download large models in tests or CI. New non-trivial logic gets a check or a test. CI runs the
build, the self-check and the tests on every push and pull request.

## Style

- No third-party dependencies beyond MacToolsKit and FluidAudio. Apple frameworks otherwise.
- Small, focused code. No speculative abstractions or options nobody asked for.
- A one-line comment for each non-obvious *why*; skip comments that restate the code.
- Colours, radii, spacing and motion come from MacToolsKit (`MT.*`, `Color.mt*`) or `Look` in `JotUI.swift`.
- Swift 5 language mode.
- Never put real names, paths, email addresses or credentials in code, tests or docs; use `/Users/me`, `example.com`.
- Audio stays on the Mac. A change that would send audio or text anywhere needs an explicit opt-in and a PRIVACY.md update.

## Pull requests

Keep them focused on one change, describe what you checked, and include a `--ui-preview` screenshot for UI changes.
