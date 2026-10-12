"""Bundle original dependency notices for offline viewing in the app.

Run after building the backend: python3 Scripts/prepare_licenses.py
Uses locked Cargo metadata and Anki's frontend inventory/lockfile. npm archives
are read without extraction or execution and checked against registry integrity.
The inventory is a conservative superset, including build-only dependencies.
"""
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Core/Sources/OpenAnkiCore/Resources/Licenses"
CACHE = Path(os.environ.get("OPENANKI_TOOL_CACHE", Path.home() / "Library/Caches/OpenAnkiIOS"))


def is_notice(name):
    return name.lower().startswith(("license", "licence", "copying", "notice", "ofl"))


def copy_notice(source, destination):
    # SwiftPM checkouts can have read-only files; generated copies are writable.
    destination.unlink(missing_ok=True)
    shutil.copyfile(source, destination)


def repository_notices(package, folder):
    """Fetch repository notices omitted from a published crate archive."""
    repo = package["repository"].removeprefix("https://github.com/").rstrip("/").removesuffix(".git")
    vcs = folder / ".cargo_vcs_info.json"
    if vcs.exists():
        revision = json.loads(vcs.read_text())["git"]["sha1"]
    else:
        with urllib.request.urlopen(f"https://api.github.com/repos/{repo}/commits?per_page=1", timeout=60) as response:
            revision = json.load(response)[0]["sha"]
    with urllib.request.urlopen(f"https://api.github.com/repos/{repo}/contents/?ref={revision}", timeout=60) as response:
        entries = json.load(response)
    texts = [f"Crate archive omitted notice files; original repository notices at {revision}:"]
    for entry in entries:
        if entry["type"] == "file" and is_notice(entry["name"]):
            with urllib.request.urlopen(entry["download_url"], timeout=60) as response:
                texts.extend([entry["download_url"], response.read().decode()])
    if len(texts) == 1:
        raise RuntimeError(f"Missing repository notices: {repo}")
    return "\n".join(texts)


def rust_notices():
    env = dict(os.environ, CARGO_HOME=str(CACHE / "cargo"), RUSTUP_HOME=str(CACHE / "rustup"))
    cargo = CACHE / "cargo/bin/cargo"
    metadata = json.loads(subprocess.check_output([
        str(cargo), "metadata", "--locked", "--format-version", "1",
        "--filter-platform", "aarch64-apple-ios",
    ], cwd=ROOT / "Backend", env=env))
    sections = []
    for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
        if package["source"] is None:
            continue  # Workspace code is covered by Anki's original notices.
        folder = Path(package["manifest_path"]).parent
        files = sorted(p for p in folder.rglob("*") if p.is_file() and is_notice(p.name))
        if package["license_file"]:
            explicit = folder / package["license_file"]
            if explicit.is_file() and explicit not in files:
                files.append(explicit)
        if not files:
            # Some crates place their copyright/license notice in the README.
            files = sorted(folder.glob("README*"))
        text = [f"{package['name']} {package['version']}",
                f"License: {package['license']}", f"Source: {package['repository'] or package['source']}",
                "Authors: " + ", ".join(package["authors"])]
        if not files:
            text.append(repository_notices(package, folder))
        for file in files:
            text.extend(["", f"--- {file.relative_to(folder)} ---", file.read_text(errors="replace")])
        sections.append("\n".join(text))
    return "\n\n".join(sections), len(sections)


def web_packages():
    inventory = json.loads((ROOT / "Backend/anki/ts/licenses.json").read_text())
    packages = {tuple(key.rsplit("@", 1)) for key in inventory}
    names = {name for name, _ in packages}
    names.update(json.loads((ROOT / "Backend/anki/package.json").read_text())["dependencies"])
    names.update(["svelte", "@sveltejs/kit", "tslib", "devalue", "esm-env", "clsx", "@standard-schema/spec", "diff"])
    locked = re.findall(r'^  resolution: "(.+)@npm:([^\"]+)"$',
                        (ROOT / "Backend/anki/yarn.lock").read_text(), re.MULTILINE)
    packages.update((name, version) for name, version in locked if name in names)
    # Anki explicitly disables node-canvas with an unused placeholder package.
    return sorted(package for package in packages if package[0] != "empty-npm-package")


def web_notice(package):
    name, version = package
    cache = CACHE / "licenses/npm" / (name.replace("/", "_") + "-" + version)
    cache.mkdir(parents=True, exist_ok=True)
    meta_file, archive_file = cache / "metadata.json", cache / "package.tgz"
    if not meta_file.exists():
        url = "https://registry.npmjs.org/" + urllib.parse.quote(name, safe="") + "/" + version
        with urllib.request.urlopen(url, timeout=60) as response:
            meta_file.write_bytes(response.read())
    meta = json.loads(meta_file.read_text())
    if not archive_file.exists():
        with urllib.request.urlopen(meta["dist"]["tarball"], timeout=60) as response:
            archive_file.write_bytes(response.read())
    data = archive_file.read_bytes()
    integrity = meta["dist"].get("integrity")
    if integrity:
        algorithm, encoded = integrity.split("-", 1)
        assert base64.b64encode(hashlib.new(algorithm, data).digest()).decode() == encoded
    else:
        assert hashlib.sha1(data).hexdigest() == meta["dist"]["shasum"]
    text = [f"{name} {version}", f"License: {meta.get('license', 'See original notices')}",
            f"Source archive: {meta['dist']['tarball']}"]
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        files = sorted((m for m in archive.getmembers() if m.isfile() and is_notice(Path(m.name).name)), key=lambda m: m.name)
        if not files:
            files = [m for m in archive.getmembers() if m.isfile() and Path(m.name).name.lower().startswith("readme")]
        if not files:
            raise RuntimeError(f"Missing notice: {name} {version}")
        for file in files:
            text.extend(["", f"--- {file.name} ---", archive.extractfile(file).read().decode(errors="replace")])
    return "\n".join(text)


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    (DESTINATION / "Anki").mkdir(exist_ok=True)
    for name in ["LICENSE", "CONTRIBUTORS"]:
        copy_notice(ROOT / "Backend/anki" / name, DESTINATION / "Anki" / name)
    copy_notice(ROOT / "LICENSE", DESTINATION / "OpenAnki-LICENSE.txt")
    copy_notice(ROOT / "NOTICE.md", DESTINATION / "NOTICE.md")
    copy_notice(ROOT / "Core/.build/checkouts/ZIPFoundation/LICENSE", DESTINATION / "ZIPFoundation-LICENSE.txt")
    rust, rust_count = rust_notices()
    (DESTINATION / "RustDependencies.txt").write_text(rust + "\n")
    packages = web_packages()
    with ThreadPoolExecutor(max_workers=8) as pool:
        web = list(pool.map(web_notice, packages))
    (DESTINATION / "WebDependencies.txt").write_text("\n\n".join(web) + "\n")
    print(f"Bundled original notices for Anki, ZIPFoundation, {rust_count} Rust and {len(web)} npm packages.")


if __name__ == "__main__":
    main()
