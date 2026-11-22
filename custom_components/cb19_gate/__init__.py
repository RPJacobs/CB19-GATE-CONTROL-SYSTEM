"""CB19 Gate local integration."""
import asyncio
from datetime import timedelta
from pathlib import Path
from time import monotonic

from homeassistant.components.http import StaticPathConfig
from homeassistant.exceptions import ConfigEntryAuthFailed, HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.device_registry import DeviceInfo, CONNECTION_NETWORK_MAC, format_mac
from homeassistant.helpers.update_coordinator import CoordinatorEntity, DataUpdateCoordinator, UpdateFailed
import logging

from .api import DOMAIN, GateAPI, GateAuthError, GateError

PLATFORMS = ["cover", "select"]


async def async_setup(hass, config):
    await hass.http.async_register_static_paths([
        StaticPathConfig("/cb19-gate-card", str(Path(__file__).parent / "www"), False)
    ])
    return True


async def async_setup_entry(hass, entry):
    coordinator = GateCoordinator(hass, entry)
    await coordinator.async_config_entry_first_refresh()
    entry.runtime_data = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass, entry):
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


class GateCoordinator(DataUpdateCoordinator):
    def __init__(self, hass, entry):
        super().__init__(hass, logging.getLogger(__name__), name=entry.title,
                         config_entry=entry, update_interval=timedelta(seconds=4))
        self.api = GateAPI(async_get_clientsession(hass), entry.data["address"], entry.unique_id,
                           entry.data.get("username"), entry.data.get("password"))
        self.lock = asyncio.Lock()
        self.next_detail = 0

    async def _async_update_data(self):
        detail = monotonic() >= self.next_detail
        try:
            async with self.lock:
                data = await self.api.status(detail)
        except GateAuthError as err:
            raise ConfigEntryAuthFailed(str(err)) from err
        except GateError as err:
            raise UpdateFailed(str(err)) from err
        data.pop("token", None)
        if detail:
            self.next_detail = monotonic() + (60 if data.get("dev") else 8)
        elif self.data:
            data.update({k: self.data.get(k) for k in ("dev", "rows", "old")})
        return data

    async def send(self, action, **kwargs):
        try:
            async with self.lock:
                await self.api.command(action, **kwargs)
        except GateError as err:
            raise HomeAssistantError(str(err)) from err
        await self.async_request_refresh()


class GateEntity(CoordinatorEntity):
    _attr_has_entity_name = True

    def __init__(self, coordinator, key):
        super().__init__(coordinator)
        entry = coordinator.config_entry
        self._attr_unique_id = entry.unique_id + "_" + key
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.unique_id)},
            connections={(CONNECTION_NETWORK_MAC, format_mac(entry.unique_id))},
            name=entry.title, manufacturer="TMT Automation", model="CB19",
            configuration_url=coordinator.api.address + "/hek",
        )
