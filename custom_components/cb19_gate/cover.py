"""The full and pedestrian gates of one CB19 controller."""
from homeassistant.components.cover import CoverDeviceClass, CoverEntity, CoverEntityFeature
from homeassistant.helpers import entity_registry as er

from . import GateEntity
from .api import DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    async_add_entities([GateCover(entry.runtime_data, False), GateCover(entry.runtime_data, True)])


class GateCover(GateEntity, CoverEntity):
    _attr_device_class = CoverDeviceClass.GATE
    _attr_supported_features = CoverEntityFeature.OPEN | CoverEntityFeature.CLOSE | CoverEntityFeature.STOP

    def __init__(self, coordinator, pedestrian):
        key = "pedestrian" if pedestrian else "gate"
        super().__init__(coordinator, key)
        self._attr_translation_key = key
        self.pedestrian = pedestrian

    @property
    def available(self):
        return super().available and bool(self.coordinator.data.get("state"))

    @property
    def _stationary(self):
        d = self.coordinator.data
        return (not self.pedestrian and d.get("path") == "single"
                or self.pedestrian and d.get("path") == "from_ped")

    @property
    def is_opening(self):
        return not self._stationary and (self.coordinator.data.get("state") or "").endswith("OPENING")

    @property
    def is_closing(self):
        return not self._stationary and (self.coordinator.data.get("state") or "").endswith("CLOSING")

    @property
    def is_closed(self):
        state = self.coordinator.data.get("state")
        if not state:
            return None
        return state.endswith("CLOSED") or (not self.pedestrian and self.coordinator.data.get("path") == "single")

    @property
    def extra_state_attributes(self):
        if self.pedestrian:
            return {}
        d = self.coordinator.data
        uid = self.coordinator.config_entry.unique_id
        registry = er.async_get(self.hass)
        return {
            "gate_state": d.get("state"), "travel_percent": d.get("pct"), "travel_path": d.get("path"),
            "busy": d.get("busy"), "f9": d.get("f9"), "devinfo": d.get("dev"),
            "settings": d.get("rows", []), "settings_stale": d.get("old"),
            "controller_url": self.coordinator.api.address,
            "pedestrian_entity": registry.async_get_entity_id("cover", DOMAIN, uid + "_pedestrian"),
            "delay_entity": registry.async_get_entity_id("select", DOMAIN, uid + "_delay"),
        }

    async def async_open_cover(self, **kwargs):
        await self.coordinator.send("ped" if self.pedestrian else "both")

    async def async_close_cover(self, **kwargs):
        await self.coordinator.send("close")

    async def async_stop_cover(self, **kwargs):
        await self.coordinator.send("stop")
