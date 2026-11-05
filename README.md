# Home Assistant Patch: Resolve Named Entities Outside the Assistant's Area

**Project:** Custom Home Assistant build  
**Reference version:** 2026.11.0  
**Architecture:** Docker / amd64  
**Implementation date:** November 5, 2026  
**Status:** Implemented and successfully tested

## 1. Purpose

Allow Home Assistant to control a specifically identified entity even when it does not belong to the area assigned to the Assist satellite.

The original issue occurred because the ReSpeaker satellite was assigned to the `Dormitorio` area, while the entity `Laptop de trabajo KVM` (`switch.primer_enchufe`) had no area assigned.

When the user said “Turn off the laptop”, Ollama correctly identified the entity but also included the contextual `Dormitorio` area. Home Assistant then attempted to find the entity inside that area and failed, despite receiving the correct entity name.

This patch allows Home Assistant to retry the target lookup without the area restriction when specific conditions are met.

## 2. Expected behavior

| Command | Expected result |
|---|---|
| Turn off the laptop | Finds `Laptop de trabajo KVM` outside the satellite's area |
| Turn on the laptop | Finds `Laptop de trabajo KVM` outside the satellite's area |
| Turn on the lights | Continues using the satellite's area |
| Turn off the lights | Continues using the satellite's area |
| Turn off Laptop de trabajo KVM | Continues working through local intent resolution |

The patch does not modify device areas, change Assist configuration, or remove contextual restrictions from other intent handlers.

## 3. Modified files

### File 1: `homeassistant/components/intent/__init__.py`

The following attribute was added to the `OnOffIntentHandler` class:

```python
allow_named_entity_area_fallback = True
```

This enables the behavior only for the on/off intent handler.

### File 2: `homeassistant/helpers/intent.py`

The `DynamicServiceIntentHandler.async_handle()` method was modified.

Immediately after the first call to:

```python
match_result = async_match_targets(hass, match_constraints, match_preferences)
```

the following block was added:

```python
if (
    not match_result.is_match
    and match_result.no_match_reason is MatchFailedReason.AREA
    and entity_name
    and area_id
    and getattr(self, "allow_named_entity_area_fallback", False)
):
    # A named entity should not be restricted to the assistant's area.
    # Retry without the area and without contextual preferences.
    fallback_constraints = MatchTargetsConstraints(
        name=match_constraints.name,
        area_name=None,
        floor_name=match_constraints.floor_name,
        domains=match_constraints.domains,
        device_classes=match_constraints.device_classes,
        assistant=match_constraints.assistant,
        features=match_constraints.features,
        states=match_constraints.states,
        allow_duplicate_names=match_constraints.allow_duplicate_names,
        single_target=True,
    )
    fallback_preferences = MatchTargetsPreferences()
    match_result = async_match_targets(
        hass, fallback_constraints, fallback_preferences
    )

    if not match_result.is_match:
        raise MatchFailedError(
            result=match_result,
            constraints=fallback_constraints,
            preferences=fallback_preferences,
        )

    match_constraints = fallback_constraints
    match_preferences = fallback_preferences

elif not match_result.is_match:
    raise MatchFailedError(
        result=match_result,
        constraints=match_constraints,
        preferences=match_preferences,
    )
```

**Important:** This block belongs in the target-resolution flow inside `DynamicServiceIntentHandler.async_handle()`. It must not be placed in another method or indiscriminately replace the original lookup logic.

## 4. Internal behavior

The implementation uses two target-resolution attempts.

### First attempt: normal lookup

Home Assistant uses the original arguments received from the model, including the entity name, domain, and contextual area.

For example:

```yaml
area: Dormitorio
name: Laptop de trabajo KVM
domain: switch
```

If the entity belongs to that area, the lookup succeeds normally.

### Second attempt: fallback

If the lookup fails specifically with `MatchFailedReason.AREA`, the code checks that:

- An entity name is present.
- A contextual area is present.
- The handler has `allow_named_entity_area_fallback` enabled.

The lookup is then retried without the contextual area.

All other original lookup constraints are preserved, including the name, domain, required features, and states.

Contextual preferences are also cleared so the satellite's area cannot influence the second lookup again.

### Ambiguity protection

The second lookup uses:

```python
single_target=True
```

This is essential: if multiple possible entities exist and a single target cannot be identified, the patch does not execute an arbitrary action.

If the fallback also fails to find a valid match, the corresponding error is raised.

## 5. Custom Docker image structure

The installation uses a custom image to preserve the modifications.

Project directory:

`/home/docker/homeassistant`

Directory structure:

```text
/home/docker/homeassistant/
├── Dockerfile
├── docker-compose.yml
├── docker-compose.yml.pre-custom.bak
├── patches/
│   └── homeassistant/
│       ├── components/
│       │   └── intent/
│       │       ├── __init__.py
│       │       └── __init__.py.orig
│       └── helpers/
│           ├── intent.py
│           └── intent.py.orig
```

Dockerfile:

```dockerfile
FROM homeassistant/home-assistant:2026.11.0

COPY patches/homeassistant/components/intent/__init__.py /usr/src/homeassistant/homeassistant/components/intent/__init__.py
COPY patches/homeassistant/helpers/intent.py /usr/src/homeassistant/homeassistant/helpers/intent.py
```

Custom image:

`homeassistant-custom:2026.11.0`

The Home Assistant service in Docker Compose uses:

```yaml
image: homeassistant-custom:2026.11.0
build:
  context: .
  dockerfile: Dockerfile
```

All other original service settings were preserved.

## 6. Reapplying the patch after a future update

**Do not copy the complete 2026.11.0 files directly into a future Home Assistant version.** Home Assistant may change its classes, methods, arguments, or internal lookup logic between releases.

The patch must be rebuilt against the original files from the new version.

### Step 1. Obtain the new version

Identify the stable release to install and inspect its original files:

- `homeassistant/components/intent/__init__.py`
- `homeassistant/helpers/intent.py`

### Step 2. Inspect `OnOffIntentHandler`

Find:

```python
class OnOffIntentHandler
```

Verify that the class still exists and has a compatible structure. Add:

```python
allow_named_entity_area_fallback = True
```

### Step 3. Inspect `DynamicServiceIntentHandler`

Find:

```python
class DynamicServiceIntentHandler
```

Inside `async_handle()`, locate the first call to `async_match_targets()`.

Verify that the following elements used by the patch still exist:

- `MatchFailedReason.AREA`
- `MatchTargetsConstraints`
- `MatchTargetsPreferences`
- `MatchFailedError`
- `entity_name`
- `area_id`
- `match_constraints`
- `match_preferences`

If the implementation has changed, adapt the patch to the new code before applying it.

### Step 4. Adapt the fallback block

Pay special attention to the arguments accepted by the `MatchTargetsConstraints` constructor.

Do not assume that future releases will retain exactly the same fields or the same `single_target` behavior.

Also verify that the result of the second lookup is used by the subsequent action-execution logic and is not overwritten by the original constraints.

### Step 5. Validate the files

Run:

```bash
python3 -m py_compile \
  patches/homeassistant/components/intent/__init__.py \
  patches/homeassistant/helpers/intent.py
```

Compare the patched files with the original files from the new release:

```bash
diff -u original_file.py patched_file.py
```

The diff should contain only the intended changes.

### Step 6. Update the Dockerfile and build

Update the base image version:

```dockerfile
FROM homeassistant/home-assistant:NEW_VERSION
```

Update the custom image tag in Docker Compose as well.

Build the image:

```bash
cd /home/docker/homeassistant
docker compose build homeassistant
```

Verify that the patch attribute exists inside the image:

```bash
docker run --rm --entrypoint sh homeassistant-custom:NEW_VERSION -c \
"grep -n 'allow_named_entity_area_fallback' /usr/src/homeassistant/homeassistant/components/intent/__init__.py"
```

Validate Python syntax inside the image:

```bash
docker run --rm --entrypoint python3 homeassistant-custom:NEW_VERSION \
-m py_compile \
/usr/src/homeassistant/homeassistant/components/intent/__init__.py \
/usr/src/homeassistant/homeassistant/helpers/intent.py
```

### Step 7. Update the container

Once the files have been validated:

```bash
docker compose up -d --no-deps homeassistant
```

Check startup logs:

```bash
docker logs --since 2m homeassistant 2>&1 | tail -100
```

## 7. Required regression tests

After every update, test through the ReSpeaker satellite, not only through the Home Assistant chat interface.

### Test A: entity outside the satellite's area

- “Turn off the laptop.”
- “Turn on the laptop.”

Expected result: both commands must find `switch.primer_enchufe`, even if Ollama includes `area: Dormitorio`.

### Test B: generic area commands

- “Turn on the lights.”
- “Turn off the lights.”

Expected result: commands must continue to resolve locally within the Dormitorio area.

### Test C: exact entity name

- “Turn off Laptop de trabajo KVM.”
- “Turn on Laptop de trabajo KVM.”

Expected result: Home Assistant must continue resolving these commands locally.

### Test D: duplicate-name safety

If multiple entities share the same name and the fallback cannot distinguish them, verify that no arbitrary action is executed.

## 8. Rollback

If the new version causes errors, restore the original Compose file:

```bash
cd /home/docker/homeassistant
cp docker-compose.yml.pre-custom.bak docker-compose.yml
docker compose up -d --no-deps homeassistant
```

This procedure applies to rolling back to the installation that existed before the custom image was introduced.

For future updates, keep a separate Compose backup for each working version instead of relying permanently on a single backup file.

Do not remove the previous Docker images until the new version has been confirmed to work correctly.

## 9. Original implementation status

The following items were verified on Home Assistant 2026.11.0:

- Both modified Python files compile successfully.
- The custom Docker image builds successfully.
- The Home Assistant container starts successfully.
- Individually named entities outside the contextual area resolve successfully.
- Generic room commands continue to resolve locally.
- Exact entity names continue to resolve locally.
- Turn-on and turn-off actions execute successfully.
- Ambiguous target lookups are protected by `single_target=True`.

**Conclusion:** The patch is functional and validated on Home Assistant 2026.11.0. It must be reviewed and adapted to the original source code of every future release before rebuilding the custom image.

---

**Core principle:** The satellite's area should help interpret generic commands, but it should not prevent control of an entity explicitly identified by name.