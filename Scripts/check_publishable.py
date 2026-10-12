"""Check the Git index for machine-specific or private publication artifacts.

Run after staging: python3 Scripts/check_publishable.py
Upstream copyright/contributor emails and public project URLs are permitted.
The scan reports filenames and categories without printing matched values.
"""
import getpass
from pathlib import PurePosixPath
import re
import subprocess
import sys

files = subprocess.check_output(["git", "ls-files", "--stage", "-z"]).decode().split("\0")
issues = []
checked = 0
username = getpass.getuser()
for entry in files:
    if not entry:
        continue
    metadata, name = entry.split("\t", 1)
    mode, object_id, _ = metadata.split()
    if mode == "160000":
        continue  # Pinned upstream submodule is a public source reference.
    path = PurePosixPath(name)
    if any(part in path.parts for part in ["xcuserdata", ".build", "DerivedData", "target", "generated"]) or any(part.endswith(".xcframework") or part.startswith("DerivedData") for part in path.parts):
        issues.append((name, "local build/user directory"))
    if path.name == "Local.xcconfig" or path.suffix in [".p12", ".p8", ".mobileprovision", ".xcuserstate", ".log", ".xcresult", ".anki2", ".anki21", ".anki21b", ".db", ".db2", ".sqlite", ".sqlite3", ".openanki", ".dylib", ".a", ".ipa", ".crash", ".ips"]:
        issues.append((name, "private configuration, certificate, or diagnostic"))
    if path.suffix in [".apkg", ".colpkg"] and not (name.startswith("Core/Tests/OpenAnkiCoreTests/Fixtures/") or name.startswith("OpenAnkiIOSUITests/")):
        issues.append((name, "personal deck outside authored test fixtures"))
    data = subprocess.check_output(["git", "cat-file", "blob", object_id])
    checked += 1
    if len(data) > 100 * 1024 * 1024:
        issues.append((name, "oversized artifact"))
    try:
        text = data.decode("utf-8")
    except UnicodeError:
        continue
    patterns = {
        "absolute machine path": "/" + r"Users/[^\s/]+/|/" + r"Volumes/[^\s/]+/|/" + r"private/var/|[A-Za-z]:\\Users\\",
        "private key/token": r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:github_pat_|ghp_)[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{30,}",
        "personal signing team": r"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\s*;|OPENANKI_DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}(?:\s|$)",
    }
    if username not in ["root", "runner"]:
        patterns["machine username"] = re.escape(username)
    for category, pattern in patterns.items():
        if re.search(pattern, text):
            issues.append((name, category))
    if not name.startswith(("Core/Sources/OpenAnkiCore/Resources/Licenses/", "Core/Sources/OpenAnkiCore/Resources/AnkiWeb/")):
        for email in re.findall(r"[A-Za-z0-9_.+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", text):
            if not email.endswith(("@users.noreply.github.com", "@example.com", "@example.org")):
                issues.append((name, "account email outside upstream notices"))
if issues:
    for name, category in sorted(set(issues)):
        print(f"FAIL: {name}: {category}")
    sys.exit(1)
print(f"Checked {checked} staged files: no machine paths, private signing/accounts, credentials, personal decks, or build artifacts.")
