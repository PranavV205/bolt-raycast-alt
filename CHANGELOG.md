# Changelog

All notable changes to Bolt are documented here. Versions follow
[semver](https://semver.org): major for breaking changes to config or
behavior, minor for new features, patch for fixes.

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
