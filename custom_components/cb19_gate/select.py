"""Controller-confirmed F9 setting including off."""
from homeassistant.components.select import SelectEntity
from homeassistant.exceptions import HomeAssistantError

from . import GateEntity
from .api import DELAYS


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([GateDelay(entry.runtime_data)])


class GateDelay(GateEntity, SelectEntity):
    _attr_translation_key = "delay"
    _attr_options = list(DELAYS)

    def __init__(self, coordinator):
        super().__init__(coordinator, "delay")

    @property
    def current_option(self):
        raw = str(self.coordinator.data.get("f9"))
        return DELAYS[int(raw)] if raw.isdecimal() and int(raw) < len(DELAYS) else None

    async def async_select_option(self, option):
        current = self.current_option
        if current is None:
            raise HomeAssistantError("Waiting for the CB19 automatic closing setting")
        await self.coordinator.send("f9", value=DELAYS.index(option), expected=DELAYS.index(current))
