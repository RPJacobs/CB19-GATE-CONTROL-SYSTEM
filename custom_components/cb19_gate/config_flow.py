"""Discover and confirm each CB19 independently."""
import voluptuous as vol
from yarl import URL
from homeassistant import config_entries
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.selector import TextSelector, TextSelectorConfig, TextSelectorType

from .api import DOMAIN, GateAPI, GateAuthError, GateError, ID_PATTERN, address_url


class CB19ConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_zeroconf(self, discovery_info):
        uid = discovery_info.properties.get("id", "")
        if not isinstance(uid, str) or not ID_PATTERN.fullmatch(uid):
            return self.async_abort(reason="invalid_discovery")
        address = str(URL.build(scheme="http", host=str(discovery_info.ip_address), port=discovery_info.port))
        api = GateAPI(async_get_clientsession(self.hass), address, uid)
        try:
            await api.identify()
        except GateError:
            return self.async_abort(reason="cannot_connect")
        await self.async_set_unique_id(uid)
        self._abort_if_unique_id_configured(updates={"address": api.address})
        self.discovered_address = api.address
        self.context["title_placeholders"] = {"name": f"CB19 {uid[-6:].upper()}"}
        return await self.async_step_confirm()

    async def async_step_confirm(self, user_input=None):
        return await self._form("confirm", user_input, self.discovered_address)

    async def async_step_user(self, user_input=None):
        return await self._form("user", user_input, None)

    async def async_step_reauth(self, entry_data):
        return await self.async_step_reauth_confirm()

    async def async_step_reauth_confirm(self, user_input=None):
        entry = self._get_reauth_entry()
        errors = {}
        if user_input is not None:
            api = GateAPI(async_get_clientsession(self.hass), entry.data["address"], entry.unique_id,
                          user_input.get("username"), user_input.get("password"))
            try:
                await api.status()
            except GateAuthError:
                errors["base"] = "invalid_auth"
            except GateError:
                errors["base"] = "cannot_connect"
            else:
                return self.async_update_reload_and_abort(entry, data_updates=user_input)
        return self.async_show_form(step_id="reauth_confirm", errors=errors, data_schema=vol.Schema({
            vol.Required("username", default=entry.data.get("username", "admin")): str,
            vol.Required("password"): TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD)),
        }))

    async def _form(self, step, user_input, discovered):
        errors = {}
        if user_input is not None:
            try:
                address = address_url(discovered or user_input["address"])
                api = GateAPI(async_get_clientsession(self.hass), address, self.unique_id if discovered else None,
                              user_input.get("username", ""), user_input.get("password", ""))
                uid = await api.identify()
                api.device_id = uid
                await api.status()
            except GateAuthError:
                errors["base"] = "invalid_auth"
            except (GateError, ValueError):
                errors["base"] = "cannot_connect"
            else:
                await self.async_set_unique_id(uid)
                self._abort_if_unique_id_configured(updates={"address": address})
                return self.async_create_entry(title=user_input.get("name") or f"CB19 {uid[-6:].upper()}",
                                               data={**user_input, "address": address})
        fields = {}
        if not discovered:
            fields[vol.Required("address", default=(user_input or {}).get("address", ""))] = str
        fields[vol.Optional("name")] = str
        fields[vol.Optional("username", default="admin")] = str
        fields[vol.Optional("password")] = TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD))
        return self.async_show_form(step_id=step, data_schema=vol.Schema(fields), errors=errors)
