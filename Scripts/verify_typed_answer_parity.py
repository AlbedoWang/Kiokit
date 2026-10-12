"""Compare the Swift reviewer adapter with the actual pinned Python methods.

The upstream methods are compiled directly from reviewer.py, without importing
Qt or changing their bodies. Empty add-on hook bindings provide their default
identity behavior. Both sides use the official backend for cloze and comparison.
Run: uv run --no-project --with anki==26.9.3 python Scripts/verify_typed_answer_parity.py
"""
import ast
import json
from pathlib import Path
import re
import subprocess
import tempfile
from types import SimpleNamespace
from typing import Match

from anki import buildinfo
from anki.collection import Collection

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "Core/.build/debug/AnkiProbe"

def upstream_reviewer(collection):
    source = ROOT / "Backend/anki/qt/aqt/reviewer.py"
    module = ast.parse(source.read_text())
    reviewer = next(item for item in module.body if isinstance(item, ast.ClassDef) and item.name == "Reviewer")
    names = {"typeAnsQuestionFilter", "typeAnsAnswerFilter", "_contentForCloze"}
    methods = [item for item in reviewer.body if isinstance(item, ast.FunctionDef) and item.name in names]
    assert len(methods) == len(names)
    pattern = next(item for item in reviewer.body if isinstance(item, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "typeAnsPat" for target in item.targets))
    namespace = {
        "re": re, "Match": Match, "tr": collection.tr,
        "gui_hooks": SimpleNamespace(
            reviewer_will_compare_answer=lambda answers, pattern: answers,
            reviewer_will_render_compared_answer=lambda output, *args: output,
        ),
    }
    adapted = ast.Module(body=[ast.ClassDef(name="UpstreamReviewer", bases=[], keywords=[], body=[pattern, *methods], decorator_list=[])], type_ignores=[])
    exec(compile(ast.fix_missing_locations(adapted), str(source), "exec"), namespace)
    return namespace["UpstreamReviewer"]

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        collection = Collection(str(root / "oracle.anki2"))
        process = subprocess.Popen([str(PROBE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        def call(method, arguments):
            process.stdin.write(json.dumps({"method": method, "input": arguments}) + "\n")
            process.stdin.flush()
            response = json.loads(process.stdout.readline())
            assert "error" not in response, response
            return response["value"]
        call("anki.collection.OpenCollection", {"collectionPath": str(root / "swift.anki2"), "mediaFolderPath": str(root / "swift.media"), "mediaDbPath": str(root / "swift.media.db2")})
        reviewer_type = upstream_reviewer(collection)
        model = collection.models.by_name("Basic")
        model["flds"][1]["font"] = "Georgia"
        model["flds"][1]["size"] = 31
        examples = [
            ("{{type:Back}}", "Paris", "Paris"),
            ("[[type:Back]]", "日本語", "日本語"),
            ("[[type:Back]]", "é", "e"),
            ("[[type:nc:Back]]", "é", "e"),
            ("before [[type:Back]] after [[type:Front]]", "a $1 \\", "bad"),
            ("[[type:Back]]", "<b>A</b><br>B", "A B"),
            ("[[type:Back]]", "", ""),
            ("[[type:Missing]]", "answer", "answer"),
            ("[[type:cloze:Back]]", "Say {{c1::bonjour}} and {{c1::salut}}.", "bonjour, salut"),
            ("[[type:cloze:Back]]", "No cloze", ""),
            ("[[type:cloze:nc:Back]]", "{{c1::é}}", "e"),
            ("Plain question", "answer", ""),
        ]
        checked = 0
        for ordinal in [0, 1]:
            for question, expected, provided in examples:
                values = ["front", expected]
                note = collection.new_note(model)
                note.fields = values
                card = SimpleNamespace(ord=ordinal, note=lambda: note, note_type=lambda: model)
                for answer in [question + "<hr id=answer>" + expected, "<hr id=answer>plain answer"]:
                    upstream = reviewer_type()
                    upstream.card = card
                    upstream.mw = SimpleNamespace(col=collection)
                    rendered_question = upstream.typeAnsQuestionFilter(question)
                    upstream.typedAnswer = provided
                    rendered_answer = upstream.typeAnsAnswerFilter(answer)
                    result = call("openanki.verify.TypeAnswer", {
                        "question": question, "answer": answer, "provided": provided, "cardOrdinal": ordinal,
                        "fields": [{"name": field["name"], "config": {"fontName": field["font"], "fontSize": field["size"]}} for field in model["flds"]], "values": values,
                    })
                    assert result["question"] == rendered_question, (question, result["question"], rendered_question)
                    assert result["answer"] == rendered_answer, (question, result["answer"], rendered_answer)
                    checked += 1
        call("anki.collection.CloseCollection", {})
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        collection.close()
        print(f"Verified {checked} exact question/answer pairs against the pinned upstream reviewer methods.")

if __name__ == "__main__":
    main()
