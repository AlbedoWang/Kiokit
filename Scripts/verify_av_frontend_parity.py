"""Compare media classification and voice matching with the pinned Python source.

Run: uv run --no-project --with anki==26.9.3 python Scripts/verify_av_frontend_parity.py
"""
import ast
from dataclasses import dataclass
import itertools
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

from anki import buildinfo
from anki.collection import Collection
from anki.sound import AVTag, TTSTag

ROOT = Path(__file__).resolve().parents[1]

def upstream_bindings():
    tts_path = ROOT / "Backend/anki/qt/aqt/tts.py"
    sound_path = ROOT / "Backend/anki/qt/aqt/sound.py"
    tts = ast.parse(tts_path.read_text())
    sound = ast.parse(sound_path.read_text())
    classes = [node for node in tts.body if isinstance(node, ast.ClassDef) and node.name in {"TTSVoice", "TTSVoiceMatch", "TTSPlayer"}]
    classification = [node for node in sound.body if
        isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "AUDIO_EXTENSIONS" for target in node.targets)
        or isinstance(node, ast.FunctionDef) and node.name == "is_audio_file"]
    assert len(classes) == 3 and len(classification) == 2
    namespace = {"dataclass": dataclass, "TTSTag": TTSTag, "AVTag": AVTag, "Any": object}
    exec(compile(ast.Module(body=classes, type_ignores=[]), str(tts_path), "exec"), namespace)
    exec(compile(ast.Module(body=classification, type_ignores=[]), str(sound_path), "exec"), namespace)
    return SimpleNamespace(**namespace)

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    upstream = upstream_bindings()
    voice_data = [
        ("Apple_Alex", "en_US"), ("Apple_Samantha", "en_US"),
        ("Apple_Samantha_Enhanced", "en_US"), ("Apple_Kyoko", "ja_JP"),
        ("Apple_Otoya", "ja_JP"), ("Apple_Mei-Jia", "zh_TW"),
    ]
    inventories = [[], voice_data, list(reversed(voice_data)), voice_data[:1], voice_data[3:]]
    requests = [[], ["Apple_Alex"], ["Apple_Kyoko"], ["Missing", "Apple_Otoya"],
                ["Apple_Kyoko", "Apple_Otoya"], ["Apple_Otoya", "Apple_Kyoko"],
                ["Apple_Samantha_Enhanced"], ["Apple_Samantha", "Missing"], ["Missing", "missing"]]
    filenames = ["word.mp3", "SAMPLE.WAV", "voice.m4a", "clip.mp4", "clip.webm", "clip.3gp",
                 "sound.flac", "sound.oga", "sound.ogg", "sound.opus", "sound.spx", "sound.aac",
                 "sound.aiff", "sound.caf", "no_extension", "mp3", "trailing.", ".wav", "folder.name/file", "字.MP3"]
    process = subprocess.Popen([str(ROOT / "Core/.build/debug/AnkiProbe")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    checked = 0
    try:
        for inventory, requested, language, rank in itertools.product(inventories, requests, ["en_US", "ja_JP", "zh_TW", "de_DE"], [0, 7, -4]):
            player = upstream.TTSPlayer()
            player.default_rank = rank
            player._available_voices = [upstream.TTSVoice(name=name, lang=lang) for name, lang in inventory]
            tag = TTSTag(field_text="Original 日本語 text", lang=language, voices=requested, speed=1.2, other_args=["foo=bar"])
            match = player.voice_for_tag(tag)
            filename = filenames[checked % len(filenames)]
            expected_voice = None if match is None else {"identifier": str(player._available_voices.index(match.voice)), "rank": match.rank}
            arguments = {"filename": filename, "defaultRank": rank,
                         "voices": [{"identifier": str(index), "name": name, "language": lang} for index, (name, lang) in enumerate(inventory)],
                         "tag": {"tts": {"fieldText": tag.field_text, "lang": tag.lang, "voices": tag.voices, "speed": tag.speed, "otherArgs": tag.other_args}}}
            process.stdin.write(json.dumps({"method": "openanki.verify.AVFrontend", "input": arguments}) + "\n")
            process.stdin.flush()
            actual = json.loads(process.stdout.readline())
            expected = {"isAudio": upstream.is_audio_file(filename), "voice": expected_voice}
            assert actual == {"value": expected}, (arguments, expected, actual)
            checked += 1
    finally:
        process.stdin.close()
        process.wait(timeout=10)
    assert process.returncode == 0
    print(f"Verified {checked} media/voice outputs against the actual pinned Python methods.")

if __name__ == "__main__":
    main()
