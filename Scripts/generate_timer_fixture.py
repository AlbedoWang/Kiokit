"""Create original timer fixtures using the pinned official Anki API.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_timer_fixture.py
"""
from pathlib import Path
import tempfile

from anki import buildinfo
from anki.collection import Collection

ROOT = Path(__file__).resolve().parents[1]

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        for name, stops in [("Stopped timer", True), ("Running timer", False)]:
            did = collection.decks.id(name)
            config = collection.decks.add_config(name)
            config_id = config["id"]
            config["timer"] = 1
            config["maxTaken"] = 10
            config["stopTimerOnAnswer"] = stops
            collection.decks.update_config(config)
            deck = collection.decks.get(did)
            deck["conf"] = config_id
            collection.decks.update(deck)
            note = collection.new_note(collection.models.by_name("Basic"))
            note.fields = ['''<div id="original-timer-variable">Original timed question</div>
                <script>var time = "Original template time variable";
                document.getElementById('original-timer-variable').textContent = time;</script>''', "Original timed answer"]
            collection.add_note(note, did)
        collection._backend.export_collection_package(out_path=str(ROOT / "OpenAnkiIOSUITests/timers.colpkg"), include_media=True, legacy=False)

if __name__ == "__main__":
    main()
