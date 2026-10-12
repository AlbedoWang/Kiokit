"""Create an original filtered-deck/audio fixture with official Anki APIs.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_filtered_fixture.py
"""
import io
from pathlib import Path
import tempfile
import wave

from anki import buildinfo
from anki.collection import Collection

ROOT = Path(__file__).resolve().parents[1]

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        original = collection.decks.id("Original audio")
        sound = io.BytesIO()
        with wave.open(sound, "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(8000)
            stream.writeframes(b"\0\0" * 800)
        for name in ["question.wav", "answer.wav"]:
            collection.media.write_data(name, sound.getvalue())
        note = collection.new_note(collection.models.by_name("Basic"))
        note.fields = ["Original filtered question [sound:question.wav]", "Original filtered answer [sound:answer.wav]"]
        collection.add_note(note, original)
        preset = collection.decks.config_dict_for_deck_id(original)
        preset["autoplay"] = False
        preset["replayq"] = False
        collection.decks.update_config(preset)
        collection.decks.select(original)
        filtered = collection.sched.get_or_create_filtered_deck(0)
        filtered.name = "Filtered audio"
        term = filtered.config.search_terms[0]
        term.search = 'deck:"Original audio"'
        del filtered.config.search_terms[1:]
        collection.sched.add_or_update_filtered_deck(filtered)
        collection._backend.export_collection_package(
            out_path=str(ROOT / "OpenAnkiIOSUITests/filtered.colpkg"), include_media=True, legacy=False,
        )

if __name__ == "__main__":
    main()
