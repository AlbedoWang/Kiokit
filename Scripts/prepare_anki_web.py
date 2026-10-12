"""Copy unmodified web assets from the pinned official Anki Qt wheel.

These files implement Anki's reviewer, statistics, image occlusion, and MathJax.
The download is verified against the publisher's SHA256 before extraction.
"""
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "26.9.3"
SHA256 = "83d60a2494939128138692435ab9c65579338c6902aaba88606bce6b5ccd22d3"
DESTINATION = ROOT / "Core/Sources/KiokitCore/Resources/AnkiWeb"

def main():
    with urllib.request.urlopen(f"https://pypi.org/pypi/aqt/{VERSION}/json") as response:
        metadata = json.load(response)
    wheel = next(item for item in metadata["urls"] if item["filename"] == f"aqt-{VERSION}-py3-none-any.whl")
    assert wheel["digests"]["sha256"] == SHA256
    with urllib.request.urlopen(wheel["url"]) as response:
        data = response.read()
    assert hashlib.sha256(data).hexdigest() == SHA256
    prefix = "_aqt/data/web/"
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for entry in archive.namelist():
            if not entry.startswith(prefix) or entry.endswith("/"):
                continue
            relative = entry[len(prefix):]
            if relative not in ["js/reviewer.js", "js/reviewer-bottom.js", "js/mathjax.js", "css/reviewer.css"] and not relative.startswith(("js/vendor/mathjax/", "sveltekit/")):
                continue
            target = DESTINATION / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))
    (DESTINATION / "upstream.json").write_text(json.dumps({
        "repository": "https://github.com/ankitects/anki",
        "commit": "29bb700b951e3f0c0cb69b77c0180fc1fe33e6ba",
        "distribution": wheel["filename"], "distribution_sha256": SHA256,
        "source_paths": ["ts/reviewer", "qt/aqt/data/web/js/reviewer-bottom.ts", "ts/routes", "ts/mathjax"],
        "modifications": "none",
    }, indent=2) + "\n")

if __name__ == "__main__":
    main()
