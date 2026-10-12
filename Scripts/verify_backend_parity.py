"""Compare the Swift transport with the official Anki 26.09.3 Python wheel.

Run after building AnkiProbe:
    uv run --no-project --with anki==26.9.3 python Scripts/verify_backend_parity.py

The fixture is created by Anki, exported as a colpkg, and restored into both
backends. Requests use the official protobuf descriptors and generated RPC IDs.
This verifies backend/transport behavior; it does not certify application views
or adapters that have not yet been migrated to these operations.
"""

from __future__ import annotations

import importlib
import inspect
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

import anki.buildinfo
from anki._backend import RustBackend
from anki._backend_generated import RustBackendGenerated
from anki.collection import Collection
from google.protobuf.json_format import MessageToDict, ParseDict
from google.protobuf.message_factory import GetMessageClass


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "Core/.build/debug/AnkiProbe"


def descriptor(name: str):
    package, operation = name.rsplit(".", 1)
    module = importlib.import_module(package + "_pb2")
    for service in module.DESCRIPTOR.services_by_name.values():
        for method in service.methods:
            if method.name == operation:
                return method
    raise AssertionError(f"Missing official RPC descriptor: {name}")


def rpc_ids(name: str) -> tuple[int, int]:
    operation = name.rsplit(".", 1)[1]
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", operation).lower()
    source = inspect.getsource(getattr(RustBackendGenerated, snake + "_raw"))
    match = re.search(r"self\._run_command\((\d+), (\d+), message\)", source)
    assert match, name
    return int(match[1]), int(match[2])


def official_call(backend: RustBackend, name: str, arguments: dict):
    method = descriptor(name)
    request = ParseDict(arguments, GetMessageClass(method.input_type)())
    response = GetMessageClass(method.output_type)()
    service, operation = rpc_ids(name)
    response.ParseFromString(backend._run_command(service, operation, request.SerializeToString()))
    return response


class Pair:
    def __init__(self, root: Path, backup: Path):
        self.official = RustBackend(langs=["en"])
        self.process = subprocess.Popen(
            [str(PROBE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1,
        )
        self.comparisons = 0
        for native, name in [(False, "official"), (True, "swift")]:
            directory = root / name
            directory.mkdir()
            media = directory / "collection.media"
            media.mkdir()
            arguments = {
                "colPath": str(directory / "collection.anki2"),
                "backupPath": str(backup), "mediaFolder": str(media),
                "mediaDb": str(directory / "collection.media.db2"),
            }
            self.invoke(native, "anki.import_export.ImportCollectionPackage", arguments)
            self.invoke(native, "anki.collection.OpenCollection", {
                "collectionPath": arguments["colPath"], "mediaFolderPath": str(media),
                "mediaDbPath": arguments["mediaDb"],
            })

    def invoke(self, native: bool, name: str, arguments: dict):
        if not native:
            return official_call(self.official, name, arguments)
        assert self.process.stdin and self.process.stdout
        self.process.stdin.write(json.dumps({"method": name, "input": arguments}, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        assert line, f"Swift probe exited while calling {name}"
        envelope = json.loads(line)
        assert "error" not in envelope, (name, envelope)
        method = descriptor(name)
        return ParseDict(envelope["value"], GetMessageClass(method.output_type)())

    def call(self, name: str, arguments: dict | None = None) -> dict:
        arguments = arguments or {}
        expected = self.invoke(False, name, arguments)
        actual = self.invoke(True, name, arguments)
        assert actual.SerializeToString(deterministic=True) == expected.SerializeToString(deterministic=True), (
            name, MessageToDict(expected), MessageToDict(actual)
        )
        self.comparisons += 1
        return MessageToDict(expected)

    def close(self):
        for native in [False, True]:
            self.invoke(native, "anki.collection.CloseCollection", {})
        assert self.process.stdin
        self.process.stdin.close()
        self.process.wait(timeout=10)


def fixture(root: Path) -> tuple[Path, int]:
    directory = root / "seed"
    directory.mkdir()
    collection = Collection(str(directory / "collection.anki2"))
    parent = collection.decks.id("Parent")
    child = collection.decks.id("Parent::Child")
    basic = collection.models.by_name("Basic")
    assert basic
    ids = []
    for index in range(36):
        note = collection.new_note(basic)
        note.fields = [f"日本語 {index}", f"中文翻译 {index}"]
        collection.add_note(note, child if index < 12 else parent)
        ids.append(note.cards()[0].id)
    today = collection.sched.today
    for index, card_id in enumerate(ids[:8]):
        card = collection.get_card(card_id)
        card.type = 2
        card.queue = 2
        card.due = today - 3
        card.ivl = 12 + index
        card.factor = 2300
        card.reps = 5
        card.lapses = 1
        collection.update_card(card)
    for card_id, ctype in [(ids[8], 1), (ids[9], 3)]:
        card = collection.get_card(card_id)
        card.type = ctype
        card.queue = 1
        card.due = int(time.time()) - 60
        card.left = 1
        card.ivl = 7 if ctype == 3 else 0
        card.factor = 2300
        collection.update_card(card)
    collection.set_config("loadBalancerEnabled", False)
    backup = root / "seed.colpkg"
    official_call(collection._backend, "anki.import_export.ExportCollectionPackage", {
        "outPath": str(backup), "includeMedia": True, "legacy": False,
    })
    # The upstream export consumes/closes the collection.
    return backup, parent


def configure(pair: Pair, deck_id: int, *, fsrs: bool, random: bool):
    options = pair.call("anki.deck_config.GetDeckConfigsForUpdate", {"did": str(deck_id)})
    config_id = options["currentDeck"]["configId"]
    config = next(item["config"] for item in options["allConfig"] if item["config"]["id"] == config_id)
    values = config["config"]
    values["newCardGatherPriority"] = "NEW_CARD_GATHER_PRIORITY_RANDOM_CARDS" if random else "NEW_CARD_GATHER_PRIORITY_LOWEST_POSITION"
    values["newCardSortOrder"] = "NEW_CARD_SORT_ORDER_RANDOM_CARD" if random else "NEW_CARD_SORT_ORDER_NO_SORT"
    values["reviewOrder"] = "REVIEW_CARD_ORDER_RANDOM" if random else "REVIEW_CARD_ORDER_DAY"
    values["newPerDay"] = 10
    values["reviewsPerDay"] = 200
    values["buryNew"] = True
    pair.call("anki.deck_config.UpdateDeckConfigs", {
        "targetDeckId": str(deck_id), "configs": [config],
        "limits": {"new": 7, "review": 100}, "fsrs": fsrs,
        "newCardsIgnoreReviewLimit": options.get("newCardsIgnoreReviewLimit", False),
        "applyAllParentLimits": options.get("applyAllParentLimits", False),
        "cardStateCustomizer": options.get("cardStateCustomizer", ""),
        "fsrsHealthCheck": options.get("fsrsHealthCheck", False),
    })


def main():
    assert anki.buildinfo.version == "26.09.3", anki.buildinfo.version
    assert anki.buildinfo.buildhash.startswith("29bb700b"), anki.buildinfo.buildhash
    assert PROBE.is_file(), "Build the AnkiProbe executable first."
    with tempfile.TemporaryDirectory(prefix="openanki-parity-") as temporary:
        root = Path(temporary)
        backup, deck_id = fixture(root)
        pair = Pair(root, backup)
        try:
            pair.call("anki.decks.SetCurrentDeck", {"did": str(deck_id)})
            pair.call("anki.scheduler.SchedTimingToday")
            for fsrs in [False, True]:
                for random in [False, True]:
                    configure(pair, deck_id, fsrs=fsrs, random=random)
                    queue = pair.call("anki.scheduler.GetQueuedCards", {"fetchLimit": 50})
                    assert queue.get("cards"), queue
                    print(f"Matched queue and all scheduling states: FSRS={fsrs}, Random={random}", flush=True)
                    for rating in ["again", "hard", "good", "easy"]:
                        queue = pair.call("anki.scheduler.GetQueuedCards", {"fetchLimit": 1})
                        queued = queue["cards"][0]
                        states = queued["states"]
                        pair.call("anki.scheduler.DescribeNextStates", states)
                        pair.call("anki.scheduler.AnswerCard", {
                            "cardId": queued["card"]["id"], "currentState": states["current"],
                            "newState": states[rating], "rating": rating.upper(),
                            "answeredAtMillis": str(int(time.time() * 1000)), "millisecondsTaken": 1500,
                        })
                        pair.call("anki.cards.GetCard", {"cid": queued["card"]["id"]})
                        pair.call("anki.stats.GetReviewLogs", {"cid": queued["card"]["id"]})
                        pair.call("anki.collection.Undo")
                        pair.call("anki.scheduler.GetQueuedCards", {"fetchLimit": 1})
            ids = pair.call("anki.search.SearchCards", {"search": ""})["ids"]
            for card_id in ids:
                pair.call("anki.scheduler.GetSchedulingStates", {"cid": card_id})
                pair.call("anki.card_rendering.RenderExistingCard", {"cardId": card_id, "partialRender": False})
            pair.call("anki.scheduler.BuryOrSuspendCards", {"cardIds": ids[:2], "mode": "SUSPEND"})
            pair.call("anki.scheduler.GetQueuedCards", {"fetchLimit": 50})
            pair.call("anki.scheduler.RestoreBuriedAndSuspendedCards", {"cids": ids[:2]})
            preferences = pair.call("anki.config.GetPreferences")
            for rollover in [0, 4, 8]:
                preferences["scheduling"]["rollover"] = rollover
                pair.call("anki.config.SetPreferences", preferences)
                pair.call("anki.scheduler.SchedTimingToday")
                pair.call("anki.decks.DeckTree", {"now": str(int(time.time()))})
            package = os.environ.get("OPENANKI_TEST_APKG")
            if package:
                options = pair.call("anki.import_export.GetImportAnkiPackagePresets")
                pair.call("anki.import_export.ImportAnkiPackage", {"packagePath": package, "options": options})
                cards = pair.call("anki.search.SearchCards", {"search": ""})["ids"]
                pair.call("anki.import_export.ImportAnkiPackage", {"packagePath": package, "options": options})
                assert pair.call("anki.search.SearchCards", {"search": ""})["ids"] == cards
                print(f"Matched package import and duplicate handling: {len(cards)} cards", flush=True)
            print(f"Passed {pair.comparisons} protobuf-equivalent comparisons against the official Anki wheel.")
        finally:
            pair.close()


if __name__ == "__main__":
    main()
