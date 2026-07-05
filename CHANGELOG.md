# Changelog

All notable changes to Bolt are documented here. Versions follow
[semver](https://semver.org): major for breaking changes to config or
behavior, minor for new features, patch for fixes.

## [Unreleased]

### Changed
- `build-app.sh` signs with a "Bolt Dev" certificate when the keychain has
  one (or `CODESIGN_IDENTITY`), so permission grants survive rebuilds during
  development. Falls back to ad-hoc signing as before.

## [1.4.0] - 2026-07-06

### Added
- Browser bookmark search: bookmarks from Chrome, Brave, Edge, Chromium and
  Vivaldi (all profiles) appear in results and open in your default browser.
  Safari bookmarks are included when Bolt has Full Disk Access. Disable with
  `"bookmarksEnabled": false`.
- Snippets support a `{cursor}` placeholder: after insertion or live
  expansion, the caret lands where the marker was.
- Test suite (fuzzy matcher, calculator parser, hotkey combos, semver
  comparison, alias rewriting, snippet placeholders) and a CI workflow that
  runs it on every push and pull request.

### Fixed
- Live snippet expansion used to require an app restart if Accessibility
  was granted after launch; it now starts on its own within seconds of the
  grant.

## [1.3.1] - 2026-07-05

### Added
- `servers` (alias `ports`) lists every TCP listener with its ports, project
  folder (the process working directory) and full command line, so dev
  servers are identifiable at a glance. `servers vite` filters by name, port
  or project. System daemons are hidden. Enter kills.
- `kill <port>` (e.g. `kill 3000` or `kill :3000`) shows what is listening
  on that TCP port, with the full command line so dev servers are tellable
  apart. Enter sends SIGTERM, Cmd+Enter SIGKILL.

## [1.3.0] - 2026-07-05

### Added
- Update check: once a day Bolt asks the GitHub releases API whether a newer
  version exists and shows a clickable toast if so. Disable with
  `"updateCheckEnabled": false`. A manual "Check for Updates" command too.
- Aliases: `~/.bolt/aliases.json` maps keywords to queries ("dm" can stand
  for "dark mode"), with trailing words appended so quicklink arguments work.
- `almostMaximize` is now a bindable hotkey action (unbound by default).
- Releases are built by GitHub Actions on tag push: universal (Apple Silicon
  and Intel) binary, built from clean source.

## [1.2.0] - 2026-07-05

### Added
- All global hotkeys are now rebindable via a `hotkeys` block in
  `~/.bolt/config.json` (launcher, clipboard, scratchpad, and every window
  command). `"none"` disables a binding. Invalid combos fall back to the
  default with a warning toast. "Reload Bolt Config" applies changes live.
- Menu bar labels and window command hints show the user's actual bindings.

### Fixed
- A config file written by an older version (or with keys removed by hand)
  no longer resets the whole config to defaults on load; missing keys keep
  their defaults, present keys keep their values.

## [1.1.0] - 2026-07-05

### Added
- App icon (lightning bolt squircle), packaged into the bundle and shown in Finder.
- README: features overview, 14 screenshots, section links, project icon.

### Fixed
- Menu bar search rendered blank ghost rows because sibling menu items shared
  a result ID. Every item now gets a unique ID.

### Changed
- Release binaries are stripped, so build machine paths no longer appear in
  the executable.

## [1.0.0] - 2026-07-04

Initial open source release. App/file/window search, clipboard history,
snippets with live expansion, calculator, unit and currency conversion,
color tools, emoji picker, dictionary, process killer, system commands,
window management, quicklinks, menu bar search and scratchpad.
