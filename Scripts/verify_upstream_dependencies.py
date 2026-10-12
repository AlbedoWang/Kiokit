"""Require every shared Rust dependency to match the pinned Anki lockfile."""
from pathlib import Path
import tomllib

root = Path(__file__).resolve().parents[1]
upstream = tomllib.loads((root / "Backend/anki/Cargo.lock").read_text())
bridge = tomllib.loads((root / "Backend/Cargo.lock").read_text())

def identity(package):
    return package["name"], package["version"], package.get("source"), package.get("checksum")

expected = {identity(package) for package in upstream["package"] if package.get("source")}
actual = {identity(package) for package in bridge["package"] if package.get("source")}
unexpected = sorted(actual - expected)
if unexpected:
    raise SystemExit(f"Dependencies differ from the pinned Anki lockfile: {unexpected}")
print(f"Verified {len(actual)} dependency revisions/checksums against the official Anki lockfile.")
