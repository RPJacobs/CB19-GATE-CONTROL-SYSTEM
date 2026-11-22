"""Local CB19 HTTP protocol. Every write is bound to one controller and boot token."""
import asyncio
import re

import aiohttp
from yarl import URL

DOMAIN = "cb19_gate"
DELAYS = ("Off", "3 s", "10 s", "20 s", "40 s", "60 s", "120 s", "180 s", "300 s")
ID_PATTERN = re.compile(r"[0-9a-f]{12}")


class GateError(Exception):
    """Unreachable controller or a rejected request."""


class GateAuthError(GateError):
    """The web interface requires credentials."""


def address_url(value):
    value = value.strip()
    url = URL(value if "://" in value else "http://" + value)
    if (url.scheme != "http" or not url.host or url.user is not None or url.password is not None
            or url.path != "/" or url.query_string or url.fragment or not url.port):
        raise ValueError("Expected a hostname or IP address and optional port")
    return str(url.origin())


class GateAPI:
    def __init__(self, session, address, device_id=None, username="", password=""):
        self.session = session
        self.address = address_url(address)
        self.device_id = device_id
        self.auth = aiohttp.BasicAuth(username or "admin", password) if password else None

    async def request(self, path, *, data=None, public=False):
        try:
            async with asyncio.timeout(5):
                async with self.session.request(
                    "GET" if data is None else "POST", self.address + path,
                    auth=None if public else self.auth, data=data, allow_redirects=False,
                ) as response:
                    if response.status in (401, 403):
                        raise GateAuthError("Controller denied access")
                    if response.status not in (200, 202):
                        raise GateError(f"CB19 returned HTTP {response.status}")
                    if data is not None:
                        return None
                    result = await response.json(content_type=None)
                    if not isinstance(result, dict):
                        raise GateError("Unexpected CB19 response")
                    return result
        except (aiohttp.ClientError, TimeoutError, ValueError) as err:
            raise GateError("Could not read CB19 response") from err

    async def identify(self):
        value = await self.request("/hek-data?identity=1", public=True)
        uid = value.get("id")
        if (value.get("product") != "cb19-gate" or value.get("api") != 1
                or not isinstance(uid, str) or not ID_PATTERN.fullmatch(uid)
                or (self.device_id is not None and uid != self.device_id)):
            raise GateError("Controller identity mismatch")
        return uid

    async def status(self, detail=False):
        await self.identify()
        result = await self.request("/hek-data?info=1" if detail else "/hek-data")
        if (result.get("id") != self.device_id or result.get("api") != 1
                or not re.fullmatch(r"[a-fA-F0-9]{32}", str(result.get("token", "")))):
            raise GateError("Unexpected controller or API version")
        return result

    async def command(self, action, *, value=None, expected=None):
        state = await self.status()
        form = {"id": self.device_id, "actie": action, "token": state["token"]}
        if action == "f9":
            actual = str(state.get("f9", ""))
            if (not actual.isdecimal() or int(actual) != expected or value not in range(len(DELAYS))):
                raise GateError("The automatic closing setting changed. Refresh and retry.")
            form.update(v=str(value), base=actual)
        elif action not in {"both", "ped", "close", "stop"}:
            raise GateError("Unknown gate command")
        await self.request("/hek-actie", data=form)
