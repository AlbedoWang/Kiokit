"""Compare the actual Swift rendering adapter with official Anki rendering.

Checks HTML, CSS, AV tags, PNG/SVG LaTeX commands, generated image bytes,
browser behavior, cached media, and the disabled-generation error path.
Run: uv run --no-project --with anki==26.9.3 python Scripts/verify_rendering_parity.py
The machine must have the desktop TeX tools used by Anki to check generation.
"""
import copy
import json
from pathlib import Path
import subprocess
import tempfile

from anki import buildinfo
from anki.collection import Collection
from anki.config import Config
from anki.sound import SoundOrVideoTag, TTSTag
from anki.card_rendering_pb2 import AVTag as ProtoAVTag, TTSTag as ProtoTTSTag
from google.protobuf.json_format import MessageToDict

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "Core/.build/debug/AnkiProbe"

def av(tag):
    if isinstance(tag, SoundOrVideoTag):
        return MessageToDict(ProtoAVTag(sound_or_video=tag.filename))
    assert isinstance(tag, TTSTag)
    result = MessageToDict(ProtoAVTag(tts=ProtoTTSTag(field_text=tag.field_text, lang=tag.lang, voices=tag.voices, speed=tag.speed, other_args=tag.other_args)))
    # Compare the actual protobuf Float32 value, not Python JSON's shorter
    # decimal representation of that value.
    if tag.speed:
        result["tts"]["speed"] = tag.speed
    return result

def comparison_tags(tags):
    result = copy.deepcopy(tags)
    for tag in result:
        if "otherArgs" in tag.get("tts", {}):
            # rslib/src/card_rendering/{parser.rs,writer.rs} stores unknown
            # attributes in a HashMap. Their iteration order is not stable
            # between the two independent official backend processes.
            tag["tts"]["otherArgs"].sort()
    return result

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = Collection(str(root / "source.anki2"))
        basic = source.models.by_name("Basic")
        svg = copy.deepcopy(basic)
        svg["id"] = 0
        svg["name"] = "Original SVG fixture"
        svg["latexsvg"] = True
        source.models.add_dict(svg)
        svg = source.models.by_name(svg["name"])
        note_ids = []
        examples = [
            (basic, ['<b>日本語</b> [sound:q.mp3]', '中文翻译 [sound:a.mp3]']),
            (basic, ['Plain question', 'Plain answer']),
            (basic, ['[sound:directory/q.mp3][sound:/outside/a.wav][sound:trailing/][sound:C:\\audio\\x.mp3]', '[sound:directory/reply.mp3]']),
            (basic, ['[anki:tts lang=ja_JP voices=Apple_Kyoko,Missing speed=1.2 foo=bar baz=qux]日本語[/anki:tts]', '[anki:tts lang=en_US]Original speech[/anki:tts]']),
            (source.models.by_name("Basic (and reversed card)"), ['Bonjour', 'Hello']),
            (source.models.by_name("Basic (type in the answer)"), ['Type an answer', '日本語']),
            (basic, ['Before [$]x^2+1[/$] after', '[latex]text[/latex]']),
            (svg, ['[$$]\\frac{1}{2}[/$$]', '[latex]SVG text[/latex]']),
            (source.models.by_name("Cloze"), ['{{c1::bonjour}} and {{c2::salut}}.', 'A greeting']),
        ]
        for model, fields in examples:
            note = source.new_note(model)
            note.fields = fields
            source.add_note(note, 1)
            note_ids.append(note.id)
        archive = root / "fixture.colpkg"
        source._backend.export_collection_package(out_path=str(archive), include_media=True, legacy=False)
        process = subprocess.Popen([str(PROBE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        def call(method, arguments):
            process.stdin.write(json.dumps({"method": method, "input": arguments}) + "\n")
            process.stdin.flush()
            response = json.loads(process.stdout.readline())
            assert "error" not in response, response
            return response["value"]
        collections = {}
        for label in ["official", "swift"]:
            folder = root / label
            folder.mkdir()
            media = folder / "collection.media"
            media.mkdir()
            arguments = {"colPath": str(folder / "collection.anki2"), "backupPath": str(archive), "mediaFolder": str(media), "mediaDb": str(folder / "collection.media.db2")}
            if label == "official":
                collection = Collection(str(root / "installer.anki2"))
                collection.close()
                collection._backend.import_collection_package(col_path=arguments["colPath"], backup_path=arguments["backupPath"], media_folder=arguments["mediaFolder"], media_db=arguments["mediaDb"])
                collections[label] = Collection(arguments["colPath"])
            else:
                call("anki.import_export.ImportCollectionPackage", arguments)
                call("openanki.verify.OpenCollectionAdapter", {"directory": str(folder)})
        oracle = collections["official"]
        cards = oracle.find_cards("")
        checks = 0
        # First check disabled generation, then actual generation, then cached media.
        for generate in [False, True, False]:
            oracle.set_config_bool(Config.Bool.RENDER_LATEX, generate)
            call("anki.config.SetConfigBool", {"key": "RENDER_LATEX", "value": generate})
            for browser in [True, False]:
                for cid in cards:
                    card = oracle.get_card(cid)
                    expected = card.render_output(browser=browser)
                    actual = call("openanki.verify.RenderedCard", {"cardId": str(cid), "browser": browser})
                    assert actual["question"]["text"] == expected.question_text, (cid, generate, browser, actual["question"]["text"], expected.question_text)
                    assert actual["answer"]["text"] == expected.answer_text, (cid, generate, browser, actual["answer"]["text"], expected.answer_text)
                    assert actual.get("css", "") == expected.css, cid
                    for side, tags in [("question", expected.question_av_tags), ("answer", expected.answer_av_tags)]:
                        actual_tags = actual[side].get("avTags", [])
                        expected_tags = [av(tag) for tag in tags]
                        assert comparison_tags(actual_tags) == comparison_tags(expected_tags), (cid, side, actual_tags, expected_tags)
                    checks += 1
        images = list((root / "official/collection.media").glob("latex-*"))
        assert any(image.suffix == ".png" for image in images)
        assert any(image.suffix == ".svg" for image in images)
        for image in images:
            assert image.read_bytes() == (root / "swift/collection.media" / image.name).read_bytes(), image.name
        call("anki.collection.CloseCollection", {})
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        oracle.close()
        print(f"Verified {checks} exact rendered cards and {len(images)} generated LaTeX images against official Anki.")

if __name__ == "__main__":
    main()
