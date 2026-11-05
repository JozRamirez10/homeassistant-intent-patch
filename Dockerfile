FROM homeassistant/home-assistant:2026.11.0

COPY patches/homeassistant/components/intent/__init__.py /usr/src/homeassistant/homeassistant/components/intent/__init__.py
COPY patches/homeassistant/helpers/intent.py /usr/src/homeassistant/homeassistant/helpers/intent.py
