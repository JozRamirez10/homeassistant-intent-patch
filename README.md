# Home Assistant Intent Patch

Custom patch for Home Assistant that allows explicitly named entities
to be controlled even when they are outside the assistant's current area.

## Documentation

- [Documentation in English](README.en.md)
- [Documentación en español](README.es.md)

## Compatibility

- Home Assistant: 2026.11.0
- Architecture: Docker / amd64

## Repository structure

- `Dockerfile`: builds the custom Home Assistant image.
- `patches/`: modified Home Assistant source files and original references.
- `docker-compose.example.yml`: example deployment configuration.
- `CHANGELOG.md`: project change history.

## Important

This project modifies internal Home Assistant source files.
Review compatibility before applying the patches to another version.
