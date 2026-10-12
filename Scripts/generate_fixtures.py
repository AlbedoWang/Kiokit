"""Create small, original Anki-format fixtures. Requires the local libzstd.

Fixtures are committed, so building and testing do not require Python or zstd CLI.
The schemas and protobuf field numbers follow the upstream Anki file format.
"""
import base64
import ctypes
import ctypes.util
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import wave
import zipfile

DESTINATION = Path(__file__).resolve().parents[1] / "Core/Tests/OpenAnkiCoreTests/Fixtures"
ZSTD = ctypes.CDLL(ctypes.util.find_library("zstd") or "/opt/homebrew/lib/libzstd.dylib")
ZSTD.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
ZSTD.ZSTD_compressBound.restype = ctypes.c_size_t
ZSTD.ZSTD_compress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
ZSTD.ZSTD_compress.restype = ctypes.c_size_t


def compress(data):
    output = ctypes.create_string_buffer(ZSTD.ZSTD_compressBound(len(data)))
    size = ZSTD.ZSTD_compress(output, len(output), data, len(data), 3)
    return output.raw[:size]


def varint(value):
    output = bytearray()
    while value >= 128:
        output.append((value & 127) | 128)
        value >>= 7
    output.append(value)
    return bytes(output)


def message(fields):
    output = bytearray()
    for number, value in fields:
        if isinstance(value, int):
            output += varint(number << 3) + varint(value)
        else:
            if isinstance(value, str):
                value = value.encode()
            output += varint((number << 3) | 2) + varint(len(value)) + value
    return bytes(output)


MODELS = {
    "10": {"name": "Basic and reverse", "type": 0, "css": ".card { font-size: 24px; }", "flds": [{"name": "Front", "ord": 0}, {"name": "Back", "ord": 1}], "tmpls": [
        {"ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr>{{Back}}"},
        {"ord": 1, "qfmt": "{{Back}}", "afmt": "{{FrontSide}}<hr>{{Front}}"},
    ]},
    "20": {"name": "Cloze", "type": 1, "css": ".cloze { font-weight: bold; }", "flds": [{"name": "Text", "ord": 0}, {"name": "Extra", "ord": 1}], "tmpls": [
        {"ord": 0, "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}<hr>{{Extra}}"},
    ]},
}


def generate(filename, modern=False, unsafe=False):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "collection.sqlite"
        db = sqlite3.connect(path)
        db.executescript("""
            CREATE TABLE col (ver INTEGER, decks TEXT, models TEXT);
            CREATE TABLE notes (id INTEGER PRIMARY KEY, guid TEXT, mid INTEGER, flds TEXT, tags TEXT);
            CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, ord INTEGER, queue INTEGER);
        """)
        db.execute("INSERT INTO col VALUES (?, ?, ?)", (18 if modern else 11, json.dumps({"1": {"name": "Languages::Cities"}, "2": {"name": "Cloze"}}), json.dumps(MODELS)))
        if modern:
            db.executescript("""
                CREATE TABLE decks (id INTEGER PRIMARY KEY, name TEXT);
                CREATE TABLE notetypes (id INTEGER PRIMARY KEY, name TEXT, config BLOB);
                CREATE TABLE fields (ntid INTEGER, ord INTEGER, name TEXT);
                CREATE TABLE templates (ntid INTEGER, ord INTEGER, config BLOB);
            """)
            db.executemany("INSERT INTO decks VALUES (?, ?)", [(1, "Languages\x1fCities"), (2, "Cloze")])
            for key, model in MODELS.items():
                db.execute("INSERT INTO notetypes VALUES (?, ?, ?)", (int(key), model["name"], message([(1, model["type"]), (3, model["css"])])))
                for field in model["flds"]:
                    db.execute("INSERT INTO fields VALUES (?, ?, ?)", (int(key), field["ord"], field["name"]))
                for template in model["tmpls"]:
                    db.execute("INSERT INTO templates VALUES (?, ?, ?)", (int(key), template["ord"], message([(1, template["qfmt"]), (2, template["afmt"])])))
        db.executemany("INSERT INTO notes VALUES (?, ?, ?, ?, ?)", [
            (100, "cities-basic", 10, 'What is the capital of France?<img src="pixel.png">[sound:tone.wav]\x1fParis', " geography "),
            (200, "cities-cloze", 20, "{{c1::London::city}} is the capital of {{c2::England}}.\x1fUnited Kingdom", " geography cloze "),
        ])
        db.executemany("INSERT INTO cards VALUES (?, ?, ?, ?, ?)", [(1001, 100, 1, 0, 0), (1002, 100, 1, 1, -1 if modern else 0), (2001, 200, 2, 0, 0), (2002, 200, 2, 1, 0)])
        db.commit()
        db.close()
        png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII=")
        sound = io.BytesIO()
        with wave.open(sound, "wb") as writer:
            writer.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
            writer.writeframes(b"\x00\x00" * 800)
        media = [png, sound.getvalue()]
        names = ["../outside.png" if unsafe else "pixel.png", "tone.wav"]
        with zipfile.ZipFile(DESTINATION / filename, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            if modern:
                archive.writestr("meta", message([(1, 3)]))
                archive.writestr("collection.anki21b", compress(path.read_bytes()))
                media_map = message([(1, message([(1, name), (2, len(data))])) for name, data in zip(names, media)])
                archive.writestr("media", compress(media_map))
            else:
                archive.writestr("collection.anki2", path.read_bytes())
                archive.writestr("media", json.dumps(dict(enumerate(names))))
            for index, data in enumerate(media):
                archive.writestr(str(index), compress(data) if modern else data)


if __name__ == "__main__":
    DESTINATION.mkdir(parents=True, exist_ok=True)
    generate("legacy.apkg")
    generate("modern.apkg", modern=True)
    generate("unsafe-media.apkg", unsafe=True)
