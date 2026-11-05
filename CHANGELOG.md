# Changelog

All notable changes to this project will be documented in this file.

## [2026.11.0] - 2026-11-05

### Added
- Custom Home Assistant Docker image based on Home Assistant 2026.11.0.
- Named entity area fallback for OnOff intent handling.
- Original Home Assistant source files preserved as `.orig` references.
- Custom Dockerfile for applying the patches during image construction.
- Regression testing for individual device control and area-based commands.

### Fixed
- Explicitly named entities can now be controlled even when they are outside the assistant's current area.
- Contextual area preferences no longer prevent the resolution of an explicitly named entity.
- Ambiguous entity matches remain protected by single-target matching.

### Compatibility
- Home Assistant: 2026.11.0
- Architecture: amd64

