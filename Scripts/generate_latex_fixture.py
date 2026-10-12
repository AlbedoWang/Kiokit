"""Create original LaTeX collection fixtures with official Anki and TeX tools.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_latex_fixture.py
"""
import copy
from pathlib import Path
import tempfile

from anki import buildinfo
from anki.collection import Collection
from anki.config import Config

ROOT = Path(__file__).resolve().parents[1]

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "collection.anki2"
        collection = Collection(str(path))
        collection.set_config_bool(Config.Bool.RENDER_LATEX, True)
        basic = collection.models.by_name("Basic")
        svg = copy.deepcopy(basic)
        svg["id"] = 0
        svg["name"] = "Original LaTeX SVG"
        svg["latexsvg"] = True
        collection.models.add_dict(svg)
        svg = collection.models.by_name(svg["name"])
        for name, model, text in [
            ("LaTeX PNG", basic, "Imported PNG [$]x^2+1[/$]"),
            ("LaTeX SVG", svg, r"Imported SVG [$$]\frac{1}{2}[/$$]"),
        ]:
            note = collection.new_note(model)
            note.fields = [text, "Original formula answer"]
            collection.add_note(note, collection.decks.id(name))
            card = note.cards()[0]
            rendered = card.render_output()
            assert "Error executing" not in rendered.question_text, rendered.question_text
            assert '<img class=latex' in rendered.question_text
        missing = collection.new_note(basic)
        missing.fields = ["Missing image [$]y^3+7[/$]", "Generate the image in desktop Anki."]
        collection.add_note(missing, collection.decks.id("Missing LaTeX"))
        collection._backend.export_collection_package(out_path=str(ROOT / "OpenAnkiIOSUITests/latex.colpkg"), include_media=True, legacy=False)
        collection = Collection(str(path))
        collection.set_config_bool(Config.Bool.RENDER_LATEX, False)
        collection._backend.export_collection_package(out_path=str(ROOT / "OpenAnkiIOSUITests/latex-disabled.colpkg"), include_media=True, legacy=False)

if __name__ == "__main__":
    main()
