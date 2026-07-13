# Changelog

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
