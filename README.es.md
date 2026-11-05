 # Parche de Home Assistant: resolución de entidades fuera del área del asistente

- **Proyecto:** Home Assistant personalizado
- **Versión de referencia:** 2026.11.0
- **Arquitectura:** Docker / amd64
- **Fecha de implementación:** 5 de noviembre de 2026
**Estado:** Implementado y probado correctamente

## 1. Objetivo

Permitir que Home Assistant controle una entidad concreta aunque no pertenezca al área asignada al satélite de Assist.

El problema original ocurría porque el satélite ReSpeaker está asignado al área `Dormitorio`, mientras que la entidad `Laptop de trabajo KVM` (`switch.primer_enchufe`) no tiene un área asignada.

Cuando el usuario decía «Apaga la laptop», Ollama identificaba correctamente la entidad, pero también incluía el área contextual `Dormitorio`. Home Assistant intentaba encontrar la entidad dentro de esa área y fallaba, aunque el nombre fuera correcto.

El parche permite reintentar la búsqueda sin la restricción de área cuando se cumplen determinadas condiciones.

## 2. Comportamiento esperado

| Comando | Resultado esperado |
|---|---|
| Apaga la laptop | Encuentra `Laptop de trabajo KVM` fuera del área del satélite |
| Enciende la laptop | Encuentra `Laptop de trabajo KVM` fuera del área del satélite |
| Enciende las luces | Sigue utilizando el área del satélite |
| Apaga las luces | Sigue utilizando el área del satélite |
| Apaga el laptop de trabajo KVM | Sigue funcionando mediante resolución local |

El parche no modifica las áreas de los dispositivos, no cambia la configuración de Assist y no elimina las restricciones contextuales de otros tipos de intents.

## 3. Archivos modificados

### Archivo 1: `homeassistant/components/intent/__init__.py`

En la clase `OnOffIntentHandler` se añadió:

```python
allow_named_entity_area_fallback = True
```

Esto habilita el comportamiento únicamente para el intent handler de encendido y apagado.

### Archivo 2: `homeassistant/helpers/intent.py`

Se modificó el método `DynamicServiceIntentHandler.async_handle()`.

Inmediatamente después de la primera llamada a:

```python
match_result = async_match_targets(hass, match_constraints, match_preferences)
```

Se añadió el siguiente bloque:

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

**Importante:** Este bloque pertenece al flujo de resolución de objetivos dentro de `DynamicServiceIntentHandler.async_handle()`. No debe colocarse en otro método ni sustituir indiscriminadamente la lógica original de búsqueda.

## 4. Funcionamiento interno

El comportamiento se divide en dos intentos de resolución.

### Primer intento: búsqueda normal

Home Assistant utiliza los argumentos originales recibidos del modelo, incluyendo nombre, dominio y área contextual.

Por ejemplo:

```yaml
area: Dormitorio
name: Laptop de trabajo KVM
domain: switch
```

Si la entidad está dentro del área, la búsqueda funciona normalmente.

### Segundo intento: fallback

Si la búsqueda falla específicamente por `MatchFailedReason.AREA`, se comprueba que:

- Exista un nombre de entidad.
- Exista un área contextual.
- El handler tenga habilitado `allow_named_entity_area_fallback`.

Entonces se repite la búsqueda sin el área contextual.

Se conservan las demás restricciones de la búsqueda original, incluyendo dominio, nombre, características y estados requeridos.

También se eliminan las preferencias contextuales para evitar que el área del satélite vuelva a influir en la selección.

### Protección contra ambigüedades

La segunda búsqueda utiliza:

```python
single_target=True
```

Esto es fundamental: si existen varias entidades posibles y no se puede identificar un único objetivo, el parche no ejecuta una acción arbitraria.

Si el fallback tampoco encuentra una coincidencia válida, se devuelve el error correspondiente.

## 5. Estructura del proyecto y de la imagen Docker personalizada

El proyecto mantiene separados el repositorio del parche y la instalación de producción de Home Assistant.

Los directorios utilizados son:

- **Repositorio del parche:** `/home/docker/repositories/homeassistant-intent-patch`
- **Instalación de producción:** `/home/docker/homeassistant`

Esta separación permite mantener el código fuente, la documentación y los archivos necesarios para construir la imagen Docker sin mezclar el repositorio con los archivos de configuración y datos de producción.

### Estructura del repositorio

```text
/home/docker/repositories/homeassistant-intent-patch/
├── .gitignore
├── CHANGELOG.md
├── Dockerfile
├── README.md
├── README.es.md
├── README.en.md
├── docker-compose.example.yml
└── patches/
    └── homeassistant/
        ├── components/
        │   └── intent/
        │       ├── __init__.py
        │       └── __init__.py.orig
        └── helpers/
            ├── intent.py
            └── intent.py.orig
```

### Dockerfile

El archivo `Dockerfile` se encuentra en la raíz del repositorio:

```dockerfile
FROM homeassistant/home-assistant:2026.11.0

COPY patches/homeassistant/components/intent/__init__.py /usr/src/homeassistant/homeassistant/components/intent/__init__.py
COPY patches/homeassistant/helpers/intent.py /usr/src/homeassistant/homeassistant/helpers/intent.py
```

Durante la construcción, Docker utiliza los archivos del directorio del repositorio para aplicar los cambios sobre la imagen original de Home Assistant.

### Configuración de ejemplo

El repositorio incluye `docker-compose.example.yml` como referencia para futuras instalaciones.

Este archivo utiliza el propio repositorio como contexto de construcción:

```yaml
build:
  context: .
  dockerfile: Dockerfile
```

Es una configuración de ejemplo y no sustituye ni modifica el archivo Compose de una instalación existente.

### Imagen personalizada

La imagen personalizada utiliza la etiqueta:

`homeassistant-custom:2026.11.0`

Los archivos `.orig` conservan referencias a los archivos originales de Home Assistant utilizados durante la implementación del parche.

### Separación respecto a producción

La instalación de producción permanece en `/home/docker/homeassistant` y conserva su Dockerfile, sus archivos de parche y su configuración Compose actuales.

El repositorio es una copia independiente y versionada del código necesario para documentar, mantener y reconstruir el parche.

No es necesario modificar el Compose de producción para mantener o publicar este repositorio.

## 6. Aplicar el parche en una futura actualización

**No se deben copiar directamente los archivos completos de 2026.11.0 sobre una versión futura.** Home Assistant puede modificar sus clases, métodos, argumentos o lógica interna entre versiones.

El parche debe reconstruirse sobre los archivos originales de la nueva versión.

### Paso 1. Obtener la nueva versión

Identificar la versión estable que se desea instalar y revisar sus archivos originales:

- `homeassistant/components/intent/__init__.py`
- `homeassistant/helpers/intent.py`

### Paso 2. Revisar `OnOffIntentHandler`

Buscar:

```python
class OnOffIntentHandler
```

Comprobar que la clase sigue existiendo y conserva una estructura compatible. Añadir:

```python
allow_named_entity_area_fallback = True
```

### Paso 3. Revisar `DynamicServiceIntentHandler`

Buscar:

```python
class DynamicServiceIntentHandler
```

Dentro de `async_handle()`, localizar la primera llamada a `async_match_targets()`.

Comprobar que siguen existiendo los elementos utilizados por el parche:

- `MatchFailedReason.AREA`
- `MatchTargetsConstraints`
- `MatchTargetsPreferences`
- `MatchFailedError`
- `entity_name`
- `area_id`
- `match_constraints`
- `match_preferences`

Si la estructura cambió, adaptar el parche a la nueva implementación antes de aplicarlo.

### Paso 4. Adaptar el bloque de fallback

Revisar especialmente los argumentos del constructor `MatchTargetsConstraints`.

No asumir que las versiones futuras conservarán exactamente los mismos campos o el mismo comportamiento de `single_target`.

También verificar que el resultado de la segunda búsqueda se utiliza posteriormente para ejecutar la acción y no se sobrescribe con las restricciones originales.

### Paso 5. Validar los archivos

Ejecutar:

```bash
python3 -m py_compile \
  patches/homeassistant/components/intent/__init__.py \
  patches/homeassistant/helpers/intent.py
```

Comparar los archivos parcheados con los originales de la nueva versión:

```bash
diff -u archivo_original.py archivo_parcheado.py
```

La comparación debe mostrar únicamente los cambios intencionales.

### Paso 6. Actualizar Dockerfile y construir

Actualizar la versión de la imagen base:

```dockerfile
FROM homeassistant/home-assistant:NUEVA_VERSION
```

Actualizar también la etiqueta de la imagen personalizada en Docker Compose.

Construir:

```bash
cd /home/docker/homeassistant
docker compose build homeassistant
```

Comprobar que el atributo del parche está presente:

```bash
docker run --rm --entrypoint sh homeassistant-custom:NUEVA_VERSION -c \
"grep -n 'allow_named_entity_area_fallback' /usr/src/homeassistant/homeassistant/components/intent/__init__.py"
```

Validar la sintaxis dentro de la imagen:

```bash
docker run --rm --entrypoint python3 homeassistant-custom:NUEVA_VERSION \
-m py_compile \
/usr/src/homeassistant/homeassistant/components/intent/__init__.py \
/usr/src/homeassistant/homeassistant/helpers/intent.py
```

### Paso 7. Actualizar el contenedor

Una vez validados los archivos:

```bash
docker compose up -d --no-deps homeassistant
```

Comprobar el arranque:

```bash
docker logs --since 2m homeassistant 2>&1 | tail -100
```

## 7. Pruebas de regresión obligatorias

Después de cada actualización, probar mediante el ReSpeaker y no solamente desde el chat de Home Assistant.

### Prueba A: entidad fuera del área

- «Apaga la laptop».
- «Enciende la laptop».

Resultado esperado: ambas acciones deben encontrar `switch.primer_enchufe`, aunque Ollama incluya `area: Dormitorio`.

### Prueba B: órdenes genéricas

- «Enciende las luces».
- «Apaga las luces».

Resultado esperado: las acciones deben continuar resolviéndose localmente en el área Dormitorio.

### Prueba C: nombre exacto

- «Apaga el laptop de trabajo KVM».
- «Enciende el laptop de trabajo KVM».

Resultado esperado: Home Assistant debe seguir resolviendo las órdenes localmente.

### Prueba D: seguridad ante duplicados

Si existen varias entidades con el mismo nombre y el fallback no puede distinguirlas, comprobar que no se ejecuta una acción arbitraria.

## 8. Rollback

Si la nueva versión presenta errores, restaurar el Compose original:

```bash
cd /home/docker/homeassistant
cp docker-compose.yml.pre-custom.bak docker-compose.yml
docker compose up -d --no-deps homeassistant
```

Este procedimiento corresponde al rollback de la instalación original que existía antes de introducir la imagen personalizada.

Para futuras actualizaciones, conviene conservar un Compose específico de cada versión funcional, en lugar de depender permanentemente de un único backup.

No eliminar las imágenes anteriores hasta comprobar que la nueva versión funciona correctamente.

## 9. Estado de la implementación original

En Home Assistant 2026.11.0 se verificó:

- Compilación Python correcta de ambos archivos.
- Construcción correcta de la imagen Docker personalizada.
- Arranque correcto del contenedor.
- Resolución satisfactoria de entidades individuales fuera del área contextual.
- Resolución local satisfactoria de órdenes genéricas por habitación.
- Resolución local satisfactoria de nombres exactos.
- Ejecución satisfactoria de encendido y apagado.
- Protección contra búsquedas ambiguas mediante `single_target=True`.

**Conclusión:** parche funcional y validado en Home Assistant 2026.11.0. Debe revisarse y adaptarse al código original de cada nueva versión antes de reconstruir la imagen.

---

**Principio fundamental:** el contexto del satélite debe ayudar a interpretar órdenes genéricas, pero no debe impedir controlar una entidad identificada explícitamente por su nombre.
