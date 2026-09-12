# Changelog

## v0.6.0 - 2026-09-12

### Menu Bar

- Replaced the native menu with a custom `.window` panel: one row per runtime showing its effective version, its source (项目声明 / 全局默认) and a one-click version switcher.
- Expanding a row lists every installed version with its origin (ENVPilot 管理 / 系统安装), marks the current one, and collapses the panel after a switch. Runtimes with nothing installed are flagged instead of offering a dead end.
- The panel reports the active scope (global or a specific project path) and keeps window-level actions (main window, settings, quit) together. It refreshes itself when opened, so a stale version list is no longer possible.

### App Icon

- Replaced the translucent, glass-like icon with a flat geometric mark: a solid indigo squircle, a white terminal chevron and three runtime dots for Node / JDK / Python.
- The icon is generated from code (`scripts/generate_app_icon.py`) rather than shipped as a hand-drawn asset, so colours and geometry stay reproducible.

### Tooling

- Added `MenuBarSnapshot`: an offscreen `ImageRenderer` snapshot of the real menu bar panel, in light and dark, with an option to expand a runtime row. The menu bar popover cannot be captured with `screencapture` or driven by automation, so this is the review and regression path.
- Added `.github/workflows/release.yml`: pushing a `v*` tag runs the test suite, packages the app with the tag as `CFBundleShortVersionString`, verifies the bundle signature, and publishes `ENVPilot.dmg` plus `ENVPilot.zip` to a GitHub Release. Manual runs upload the artifacts without creating a release.
- `scripts/package_app.sh` now accepts `APP_VERSION` and `APP_BUILD` overrides.
- Rewrote the README around the menu bar panel, the four main window pages, the release pipeline and the reproducible tooling.

### App UI and UX

- Rebuilt the window shell on `NavigationSplitView`: real translucent sidebar, unified toolbar (refresh + ⌘R), per-page navigation title and subtitle. The previous hand-built `NSWindow` and the duplicate `Settings` scene rendering the same root view are gone, so ⌘, now opens a small dedicated settings window instead of a second main window.
- Collapsed seven sidebar destinations into four pages: 概览 / 运行时 / 项目 / 环境预设. Node, JDK and Python share one 运行时 page with a segmented switcher instead of three near-identical pages.
- Added an always-visible current-environment panel on 概览: one row per runtime with its resolved version, a 项目声明 / 全局默认 source marker and an inline version switcher, so the most frequent action (changing the version you are using) is one click from launch.
- Added a project inspector on the 项目 page: choose or paste a directory, see which versions its `.envpilot` declares, whether they are installed, and copy the command that applies them to the current terminal. Recently inspected folders are remembered.
- Downloadable versions now load automatically when a runtime page opens and can be refiltered locally; install progress and per-row state stay attached to the row that is working instead of a page-wide banner.
- Moved errors and confirmations into a persistent status strip above the bottom of the window, so feedback is never scrolled out of view.
- Removed the decorative layer (gradient page background, tinted card rails, material-filled status capsules, custom text-field chrome) in favour of system materials, hairline separators and standard controls.
- Shortened the menu bar item to a standalone icon, independent of the main window.

### Platform

- Raised the minimum deployment target to macOS 14 (`Package.swift`, `LSMinimumSystemVersion`) to use the newer window and menu primitives.

## v0.5.1 - 2026-09-11

### JDK Discovery and Installation

- Managed JDK installs now keep the full macOS `.jdk` bundle layout (`Contents/Info.plist`, `Contents/MacOS`) instead of extracting only `Contents/Home`, which previously produced bundles that `/usr/libexec/java_home` and other standard tooling could not enumerate.
- Added a symbolic-link discovery entry under `~/Library/Java/JavaVirtualMachines` pointing at the managed runtime, created on install and removed on uninstall. Runtime payloads stay under `~/.envpilot/runtimes/java`.
- Kept non-bundle archive layouts in the private runtime directory, so malformed entries are never published into the standard JVM directory.
- Extended JDK detection to the user-domain `~/Library/Java/JavaVirtualMachines` directory and to Gradle-provisioned JDKs under `~/.gradle/jdks`. A discovery entry and its private target are counted once.

## v0.5.0 - 2026-07-13

### App UI

- Added an app settings page for showing or hiding the ENVPilot menu bar entry.
- Kept the main window available from the Dock when the menu bar entry is hidden.
- Refreshed the README with clean application screenshots and updated installation, CLI, and development guidance.

### Runtime Reliability and Security

- Restricted runtime download URLs to HTTPS.
- Added request and resource timeouts for runtime metadata and archive downloads.
- Changed SHA-256 verification to stream large archives instead of loading them fully into memory.
- Added archive path validation to reject absolute paths and parent-directory traversal before extraction.
- Staged Python installations before replacing a managed runtime.
- Made managed runtime replacement recover the previous installation when the final move fails.
- Drained shell command stdout and stderr concurrently to prevent large-output deadlocks.
- Centralized shell single-quote escaping across runtime detection, profile exports, activation scripts, and installers.

### State Management and Tests

- Returned updated runtime snapshots directly from mutating service operations to avoid redundant reloads.
- Added installer safety, checksum, rollback, and shell output regression tests.
- Added a project-local build-and-run entry point and Codex Run configuration.

## v0.3.0 - 2026-07-07

### Runtime Management

- Added first-class Python support in ENVPilot.
- Added Python version discovery from the official Python distribution index.
- Python candidate lists now show Python 3.8+ only, with the latest patch release for each 3.x feature version.
- Python installs are managed by ENVPilot under `~/.envpilot/runtimes/python/<version>`.
- Python switching now exports `ENVPILOT_PYTHON_HOME` and prepends `$ENVPILOT_PYTHON_HOME/bin` to `PATH`.
- Project-level `.envpilot` files now support `PYTHON_VERSION` in addition to `NODE_VERSION` and `JAVA_VERSION`.
- Node, JDK, and Python runtime lists only show ENVPilot-managed installations.
- Node and JDK install flows no longer depend on SDKMAN, Homebrew, fnm, or nvm.
- Node candidates are fetched from the official Node distribution index.
- JDK candidates are fetched from Adoptium Temurin.
- Candidate searches support stable/LTS filtering and display only the latest release per major or feature version.
- Download and install progress now appears on the selected candidate row with percentage and transfer speed.
- Already installed candidates are marked before installation and cannot be downloaded again.

### App UI

- Refreshed the full app UI with a custom sidebar, clearer page headers, stronger card boundaries, and more visible input fields.
- Added a dedicated Python page alongside Node and JDK.
- Added Python status and selected path information to the overview.
- Removed the duplicate global progress banner so install progress is shown only where the operation is happening.
- Reworked installed runtime rows so the selected runtime shows a green `已选中` status in the action area instead of a redundant `切换` button.
- Standardized installed-row behavior across Node, JDK, and Python.
- Added ENVPilot badges to managed Node/JDK/Python rows.
- Improved search controls for installable versions with clearer input fields and switches.

### CLI

- Added `ep available py` / `envpilot-helper available py`.
- Added `ep install-python <version>`.
- Added `ep set-python <version-or-home-path>`.
- Added `ep list py`.
- Added `ep use py <version>` to write `PYTHON_VERSION` into project `.envpilot` files.
- Added config support for `selected-python-version`, `selected-python-home`, and `selected-python`.
- Extended status output with selected, active, and detected Python fields.

### Packaging

- Added app icon resources and updated packaging scripts to include the icon.
- Updated local install packaging so the app bundle, DMG, helper, and CLI are produced together.

### Notes

- Python installation builds CPython from official source packages. It does not use pyenv, Homebrew, uv, or other third-party runtime managers.
- Python source builds require the local macOS compiler toolchain and may take longer than Node or JDK installs.
