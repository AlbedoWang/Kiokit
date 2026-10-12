"""Create original sibling-note fixtures with the pinned official Anki API.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_notes_fixture.py
"""
from pathlib import Path
import tempfile
import time

from anki import buildinfo
from anki.collection import Collection
from anki.scheduler_pb2 import CardAnswer

ROOT = Path(__file__).resolve().parents[1]

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        did = collection.decks.id("Original sibling notes")
        for name, fields in [("Basic (and reversed card)", ["Original sibling front", "Original sibling answer"]),
                             ("Basic", ["Surviving original note", "Original independent answer"])]:
            note = collection.new_note(collection.models.by_name(name))
            note.fields = fields
            collection.add_note(note, did)
        collection.decks.select(did)
        queued = collection._backend.get_queued_cards(fetch_limit=1, intraday_learning_only=False).cards[0]
        collection._backend.answer_card(CardAnswer(card_id=queued.card.id, current_state=queued.states.current,
            new_state=queued.states.easy, rating=3, answered_at_millis=int(time.time() * 1000), milliseconds_taken=1500))
        collection._backend.export_collection_package(out_path=str(ROOT / "KiokitUITests/notes.colpkg"), include_media=True, legacy=False)

if __name__ == "__main__":
    main()
