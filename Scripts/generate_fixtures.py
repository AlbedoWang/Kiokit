"""Generate original fixtures with the pinned official Anki backend.

Run with:
    uv run --no-project --with anki==26.9.3 python Scripts/generate_fixtures.py

No collection schemas, template rules, scheduling, ZIP/protobuf encoders, or
compression algorithms are implemented here. Anki creates and exports fixtures.
"""
import base64
import io
from pathlib import Path
import shutil
import tempfile
import time
import wave

from anki import buildinfo
from anki.collection import Collection
from anki.scheduler_pb2 import CardAnswer

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "Core/Tests/KiokitCoreTests/Fixtures"

def media(collection):
    image = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5C8AAAAASUVORK5CYII=")
    sound = io.BytesIO()
    with wave.open(sound, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(8000)
        output.writeframes(b"\0\0" * 800)
    collection.media.write_data("sample.png", image)
    collection.media.write_data("sample.wav", sound.getvalue())

def add(collection, model, deck_id, fields):
    note = collection.new_note(model)
    note.fields = fields
    collection.add_note(note, deck_id)
    return note

def export_package(collection, path, legacy):
    collection._backend.export_anki_package(
        out_path=str(path),
        options={"with_scheduling": True, "with_deck_configs": True, "with_media": True, "legacy": legacy},
        limit={"whole_collection": {}},
    )

def main():
    assert buildinfo.version == "26.09.3"
    assert buildinfo.buildhash.startswith("29bb700b")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        basic_deck = collection.decks.id("Basics")
        cloze_deck = collection.decks.id("Cloze")
        media(collection)
        add(collection, collection.models.by_name("Basic"), basic_deck, [
            "What is the capital of France?",
            'Paris <img src="sample.png"> [sound:sample.wav]',
        ])
        add(collection, collection.models.by_name("Basic (and reversed card)"), basic_deck, ["Bonjour", "Hello"])
        add(collection, collection.models.by_name("Cloze"), cloze_deck, ["Say {{c1::bonjour}} to {{c2::the world}}.", "A greeting"])
        export_package(collection, DESTINATION / "legacy.apkg", True)
        export_package(collection, DESTINATION / "modern.apkg", False)
        collection.close()
    shutil.copy2(DESTINATION / "modern.apkg", ROOT / "KiokitUITests/modern.apkg")
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        deck = collection.decks.id("Backup native deck")
        add(collection, collection.models.by_name("Basic"), deck, ["Backed-up question", "Backed-up answer"])
        collection.decks.select(deck)
        queued = collection._backend.get_queued_cards(fetch_limit=1, intraday_learning_only=False).cards[0]
        collection._backend.answer_card(CardAnswer(
            card_id=queued.card.id, current_state=queued.states.current, new_state=queued.states.easy,
            rating=3, answered_at_millis=int(time.time() * 1000), milliseconds_taken=2000,
        ))
        collection._backend.export_collection_package(
            out_path=str(ROOT / "KiokitUITests/backup.colpkg"), include_media=True, legacy=False,
        )
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        deck = collection.decks.id("Restored original deck")
        add(collection, collection.models.by_name("Basic"), deck, ["Restored question", "原始答案"])
        collection.decks.select(deck)
        collection.set_config("openAnki.interface", {
            "initialized": True,
            "settings": {"dailyGoal": 200, "newCardsPerDay": 20, "appearance": "system", "interfaceLanguage": "zh-Hans"},
        })
        collection._backend.export_collection_package(
            out_path=str(ROOT / "KiokitUITests/backup-zh.colpkg"), include_media=True, legacy=False,
        )

if __name__ == "__main__":
    main()
