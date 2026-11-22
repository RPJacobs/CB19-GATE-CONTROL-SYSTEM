"""Build the single-file Tasmota application using only Python's standard library."""
import json
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile, ZipInfo

APP = Path(__file__).resolve().parent
ROOT = APP.parent
FILES = [APP / "autoexec.be", ROOT / "gate.be", APP / "hekweb.be",
         APP / "hek.html", APP / "hek-taal.js", *(APP / f"{lang}.json" for lang in ("nl", "en", "de"))]


def build():
    catalogs = [json.loads(p.read_text(encoding="utf-8")) for p in FILES if p.suffix == ".json"]
    if not all(c.keys() == catalogs[0].keys() and all(isinstance(v, str) and v for v in c.values())
               for c in catalogs):
        raise ValueError("Language files must have matching keys and nonempty text values")
    output = ROOT / "dist" / "CB19-Gate.tapp"
    output.parent.mkdir(exist_ok=True)
    temporary = output.with_suffix(".tmp")
    with ZipFile(temporary, "w", compression=ZIP_STORED, allowZip64=False) as archive:
        for path in FILES:
            entry = ZipInfo(path.name, (2020, 1, 1, 0, 0, 0))
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, path.read_bytes())
    with ZipFile(temporary) as archive:
        if archive.testzip() or any(archive.read(p.name) != p.read_bytes() for p in FILES):
            raise ValueError("Archive verification failed")
    temporary.replace(output)
    print(f"{output.name}: {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    build()
