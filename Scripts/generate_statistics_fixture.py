"""Create original statistics fixtures using only the pinned official Anki API.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_statistics_fixture.py
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
        decks = {name: collection.decks.id(name) for name in ["Statistics A", "Statistics B"]}
        cards = {}
        for name, count in [("Statistics A", 3), ("Statistics B", 1)]:
            cards[name] = []
            for index in range(count):
                note = collection.new_note(collection.models.by_name("Basic"))
                note.fields = [f"{name} original {index}", "Original statistics answer"]
                collection.add_note(note, decks[name])
                cards[name].extend(collection.find_cards(f"nid:{note.id}"))
        collection.decks.select(decks["Statistics A"])
        queued = collection._backend.get_queued_cards(fetch_limit=1, intraday_learning_only=False).cards[0]
        collection._backend.answer_card(CardAnswer(card_id=queued.card.id, current_state=queued.states.current,
            new_state=queued.states.easy, rating=3, answered_at_millis=int(time.time() * 1000), milliseconds_taken=2500))
        collection.sched.suspend_cards([cards["Statistics A"][-1]])
        collection._backend.export_collection_package(out_path=str(ROOT / "KiokitUITests/statistics.colpkg"), include_media=True, legacy=False)

if __name__ == "__main__":
    main()
