# Changelog

All notable changes to Bolt are documented here. Versions follow
[semver](https://semver.org): major for breaking changes to config or
behavior, minor for new features, patch for fixes.

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
