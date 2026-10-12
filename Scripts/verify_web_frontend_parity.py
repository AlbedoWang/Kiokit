"""Check resource rules against actual pinned Python methods and wheel bytes.

Run: python3 Scripts/verify_web_frontend_parity.py
The pinned aqt wheel is cached at /tmp/openanki-aqt-26.9.3.whl.
"""
import ast
import hashlib
import itertools
import json
import mimetypes
import os
from pathlib import Path
import re
import subprocess
import zipfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Core/Sources/KiokitCore/Resources/AnkiWeb"

def upstream_bindings():
    source = ROOT / "Backend/anki/qt/aqt/mediasrv.py"
    module = ast.parse(source.read_text())
    methods = [node for node in module.body if isinstance(node, ast.FunctionDef) and node.name in {"_mime_for_path", "_strip_csp_meta"}]
    pattern = next(node for node in module.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "_SVELTEKIT_CSP_META_RE" for target in node.targets))
    assert len(methods) == 2
    namespace = {"re": re, "os": os, "mimetypes": mimetypes}
    exec(compile(ast.Module(body=[pattern, *methods], type_ignores=[]), str(source), "exec"), namespace)
    mime_method = next(node for node in methods if node.name == "_mime_for_path")
    mapping = next(node for node in ast.walk(mime_method) if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "mime_types" for target in node.targets))
    return namespace, ast.literal_eval(mapping.value)

def main():
    namespace, mime_types = upstream_bindings()
    process = subprocess.Popen([str(ROOT / "Core/.build/debug/AnkiProbe")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    checked = 0
    try:
        examples = [
            '<html><meta http-equiv="content-security-policy" content="script-src \'self\' \'sha256-AbC+/=123\'"></html>',
            '<!-- Original 日本語 -->\n<meta http-equiv="content-security-policy" content="script-src \'self\' \'sha256-abc=\'">\nOriginal body',
            (ASSETS / "sveltekit/index.html").read_text(),
        ]
        for extension, prefix, html in itertools.product(mime_types, ["original", "/path with spaces/原文", "nested.path/UPPER"], examples):
            path = prefix + (extension.upper() if prefix.endswith("UPPER") else extension)
            expected = {"mime": namespace["_mime_for_path"](path), "html": namespace["_strip_csp_meta"](html.encode()).decode()}
            process.stdin.write(json.dumps({"method": "openanki.verify.WebFrontend", "input": {"path": path, "html": html}}) + "\n")
            process.stdin.flush()
            actual = json.loads(process.stdout.readline())
            assert actual == {"value": expected}, (path, expected, actual)
            checked += 1
        source = ROOT / "Backend/anki/qt/aqt/webview.py"
        module = ast.parse(source.read_text())
        method = next(node for node in ast.walk(module) if isinstance(node, ast.FunctionDef) and node.name == "on_theme_did_change")
        for night_mode, macos_dark_mode in itertools.product([False, True], repeat=2):
            theme = SimpleNamespace(night_mode=night_mode, macos_dark_mode=lambda: macos_dark_mode, qcolor=lambda color: color)
            theme_namespace = {"theme_manager": theme, "colors": SimpleNamespace(CANVAS=None)}
            exec(compile(ast.Module(body=[method], type_ignores=[]), str(source), "exec"), theme_namespace)
            scripts = []
            page = SimpleNamespace(setBackgroundColor=lambda _: None)
            webview = SimpleNamespace(page=lambda: page, eval=scripts.append)
            theme_namespace["on_theme_did_change"](webview)
            process.stdin.write(json.dumps({"method": "openanki.verify.WebTheme", "input": {"nightMode": night_mode, "macOSDarkMode": macos_dark_mode}}) + "\n")
            process.stdin.flush()
            actual = json.loads(process.stdout.readline())
            assert actual == {"value": scripts[0]}, (scripts, actual)
            checked += 1
        for html in ["", "No CSP meta tag", '<meta http-equiv="content-security-policy" content="script-src \'self\'">']:
            try:
                namespace["_strip_csp_meta"](html.encode())
            except RuntimeError as error:
                expected_error = str(error)
            else:
                raise AssertionError("Upstream must reject missing CSP metadata")
            process.stdin.write(json.dumps({"method": "openanki.verify.WebFrontend", "input": {"path": "original.html", "html": html}}) + "\n")
            process.stdin.flush()
            actual = json.loads(process.stdout.readline())
            assert actual["error"]["message"] == expected_error, actual
            checked += 1
    finally:
        process.stdin.close()
        process.wait(timeout=10)
    assert process.returncode == 0
    metadata = json.loads((ASSETS / "upstream.json").read_text())
    wheel = Path("/tmp/openanki-aqt-26.9.3.whl")
    assert hashlib.sha256(wheel.read_bytes()).hexdigest() == metadata["distribution_sha256"]
    files = [path for path in ASSETS.rglob("*") if path.is_file() and path.name != "upstream.json"]
    with zipfile.ZipFile(wheel) as archive:
        for path in files:
            name = "_aqt/data/web/" + path.relative_to(ASSETS).as_posix()
            assert path.read_bytes() == archive.read(name), name
    print(f"Verified {checked} resource-rule outputs against actual pinned Python methods and {len(files)} unmodified official web assets.")

if __name__ == "__main__":
    main()
