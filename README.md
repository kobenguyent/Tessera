# ✦ Tessera

> **Craft bespoke terminal mosaics & command rituals for macOS.**
> Named after the Latin *tessera* (a tile in a mosaic), **Tessera** lets you visually design pre-defined window/pane layouts, assign startup directories, environment variables, delays, and commands to each tile, and launch them in one click across your favorite terminal emulators.

---

## Features

- **Visual Split-Pane Studio** — Interactive recursive binary split-pane editor with draggable dividers, 1-click structure presets (Single, Dual Columns, Main + Side Stack, 2×2 Quad Mosaic, Command Center, Triple Columns), multi-tab layouts, and live per-pane command/env/directory configuration.
- **Menu Bar Quick-Launcher** — Lives in your macOS Menu Bar for instant 1-click launching of pinned & custom mosaics, with an on-the-fly terminal override picker.
- **Live Script Editor** — Toggle seamlessly between **Mosaic** and **Script** (`⇧⌘I`) with line numbers, Find & Replace (`⌘F`), zero-execution syntax validation (`osacompile`, `zsh -n`, YAML/Kitty checks), on-the-fly execution (`⌘↩`) of unsaved edits, or persistent per-terminal custom script overrides (`⌘S`) with 1-click Reset to Mosaic.
- **8 Terminal Drivers Supported** — Automatic installation detection across iTerm2, Apple Terminal, Warp, WezTerm, Kitty, Ghostty, Alacritty, and tmux.
- **Companion CLI (`tessera`)** — Bundled inside `Tessera.app` (installable to `PATH` from Settings) and shipped as a standalone release archive for Raycast, Alfred, and shell automation.
- **GitHub Releases Auto-Update Checker** — Background + manual SemVer 2.0 release checking against GitHub Releases, release notes viewer, direct `.dmg`/`.zip` download with live progress, cryptographic **SHA-256 verification** against `SHA256SUMS.txt`, pre-release opt-in, and Skip Version support.
- **Native Universal macOS Builds** — Built in pure Swift & SwiftUI (`arm64` + `x86_64`), zero Electron runtime overhead.

---

## Supported Terminals

| Terminal | Native Splits | Multi-Tab | Profiles | Window Bounds | Orchestration Engine |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **iTerm2** | ✅ | ✅ | ✅ | ✅ | AppleScript (`com.googlecode.iterm2`) |
| **Warp** | ✅ | ✅ | — | — | Native Launch Configuration YAML + `warp://launch` |
| **WezTerm** | ✅ (exact %) | ✅ | — | — | `wezterm cli` (`spawn`, `split-pane`, `send-text`) |
| **Kitty** | ✅ (exact %) | ✅ | — | — | Native Kitty Session File (`layout splits`) |
| **tmux** | ✅ (exact %) | ✅ | — | — | `tmux` session builder + automatic terminal attach |
| **Apple Terminal** | Geometric Mosaic | ✅ | ✅ | ✅ | AppleScript precision-tiled window mosaic |
| **Ghostty** | Window Sizing | — | — | ✅ | Ghostty CLI (`--working-directory`, `--title`, dimensions) |
| **Alacritty** | Geometric Mosaic | — | — | ✅ | Alacritty CLI (`window.position`, `window.dimensions`) |

---

## Installation

### Download Native App (GitHub Releases)

1. Open the [**Releases**](https://github.com/kobenguyent/Tessera/releases) page.
2. Download **`Tessera-<version>-macOS-universal.dmg`** (recommended) or **`Tessera-<version>-macOS-universal.zip`**.
3. Open the DMG and drag **Tessera.app** into **Applications**.
4. If the build is ad-hoc signed, right-click **Tessera.app → Open** on first launch (or run `xattr -dr com.apple.quarantine /Applications/Tessera.app`).
5. Grant **Automation** permission when macOS prompts so Tessera can orchestrate iTerm2 / Apple Terminal.

### Build & Package from Source

Requires macOS 14+ and Swift 5.9+ (Xcode 15+ / Swift 6).

```bash
# Run unit tests
swift test

# Build & launch Tessera Studio in development
swift run Tessera

# Package native Tessera.app, DMG, ZIP, CLI tarball, and SHA256SUMS.txt
./scripts/package-app.sh --version 1.0.0 --arch universal
```

Artifacts are written to `build/`:
- `build/Tessera.app`
- `build/Tessera-1.0.0-macOS-universal.dmg`
- `build/Tessera-1.0.0-macOS-universal.zip`
- `build/tessera-cli-1.0.0-macOS-universal.tar.gz`
- `build/SHA256SUMS.txt`

---

## Companion CLI (`tessera`)

Install directly from **Tessera → Settings → CLI & Data → Install `tessera` CLI to PATH**, or extract `tessera-cli-*.tar.gz`.

```bash
# List all configured mosaic layouts
tessera list

# Launch a mosaic by name or slug
tessera run full-stack-foundry

# Override terminal emulator or working directory
tessera run tessera-quad-mosaic --terminal wezterm --cwd ~/Projects/myapp

# Dry-run: inspect generated AppleScript / YAML / shell script without executing
tessera run full-stack-foundry --terminal iterm2 --dry-run

# List detected terminals on this Mac
tessera terminals

# Check GitHub Releases for updates
tessera check-update

# Export / import layout libraries
tessera export ~/Desktop/my-mosaics.json
tessera import ~/Desktop/my-mosaics.json
```

---

## Auto-Update Checking (GitHub Releases)

Tessera automatically checks `https://api.github.com/repos/<owner>/<repo>/releases` on launch (throttled by your configured frequency, default every 24h) and via **Tessera → Check for Updates…** or the Settings **Updates** tab:

- Compares SemVer 2.0 release tags (`v1.2.0`, `v1.3.0-beta.1`) against the running `CFBundleShortVersionString`.
- Ignores draft releases always, and ignores pre-releases unless opted in.
- Selects the best macOS artifact (`.dmg` universal/arch-matched, falling back to `.zip`).
- Downloads directly to `~/Downloads` with a live progress bar, **cryptographically verifies SHA-256** against the release's `SHA256SUMS.txt` asset, and then **automatically closes the current app, atomically replaces `Tessera.app` from the `.dmg`/`.zip` (with rollback safety), and relaunches the new version**.
- The target repository is automatically embedded into `Info.plist` (`TesseraGitHubRepo`) by the release workflow so forks automatically track their own GitHub Releases, and can also be edited in **Settings → Updates** or overridden via `TESSERA_GITHUB_REPO`.

---

## GitHub Actions CI & Releases

Two workflows are included in `.github/workflows/`:

1. **[`.github/workflows/ci.yml`](.github/workflows/ci.yml)** — Runs on every push/PR to `main`: executes `swift test --parallel`, builds release binaries, packages `.app`/`.dmg`/`.zip`/CLI/`SHA256SUMS.txt`, and smoke-tests the CLI.
2. **[`.github/workflows/release.yml`](.github/workflows/release.yml)** — Runs on version tags (`v*.*.*`) or manual `workflow_dispatch`: runs full unit tests, builds universal (`arm64` + `x86_64`) native artifacts, verifies `SHA256SUMS.txt`, and publishes a GitHub Release with all downloadable artifacts.

### Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

> **Optional Code Signing:** Configure the `MACOS_CODESIGN_IDENTITY` repository secret (plus certificate import step) to sign with a Developer ID certificate; otherwise builds automatically use clean ad-hoc signing.

---

## License

MIT — see [LICENSE](LICENSE).
