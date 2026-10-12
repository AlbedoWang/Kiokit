"""Create reviewer fixtures through the pinned official Anki implementation.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_reviewer_fixture.py
The user-authored content exercises typed answers, MathJax, image occlusion, and
the official custom scheduling hook; no application rules are implemented here.
"""
from pathlib import Path
import tempfile

from anki import buildinfo
from anki.collection import Collection

ROOT = Path(__file__).resolve().parents[1]

def add(collection, model, deck, fields):
    note = collection.new_note(model)
    note.fields = fields
    collection.add_note(note, collection.decks.id(deck))

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        add(collection, collection.models.by_name("Basic (type in the answer)"), "Typed answer", ["Type the Japanese word", "日本語"])
        add(collection, collection.models.by_name("Basic"), "MathJax", [r"Official formula \(x^2 + 1\)", r"Answer \[\frac{1}{2}\]"])
        add(collection, collection.models.by_name("Basic"), "Async scheduling", ["Wait for the official async hook", "Async answer"])
        collection._backend.add_image_occlusion_notetype()
        collection.media.write_data("occlusion image.svg", b'<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200"><rect width="400" height="200" fill="white"/><text x="100" y="80" font-size="32">Original image</text></svg>')
        add(collection, collection.models.by_name("Image Occlusion"), "Image occlusion", [
            "{{c1::image-occlusion:rect:left=.2:top=.2:width=.3:height=.3:oi=1}}{{c2::image-occlusion:rect:left=.6:top=.2:width=.2:height=.3:oi=1}}",
            '<img src="occlusion image.svg">', "Official image occlusion", "Mask revealed", "",
        ])
        collection.set_config("cardStateCustomizer", """
        if (ctx.deckName === 'Async scheduling') {
            await new Promise(resolve => setTimeout(resolve, 8000));
        }
        if (states.good.normal?.learning) {
            states.good.normal.learning.scheduledSecs = 42;
        }
        customData.good.count = (customData.good.count ?? 0) + 1;
        customData.good.deck = ctx.deckName;
        """)
        collection._backend.export_collection_package(
            out_path=str(ROOT / "OpenAnkiIOSUITests/reviewer.colpkg"), include_media=True, legacy=False,
        )

if __name__ == "__main__":
    main()
