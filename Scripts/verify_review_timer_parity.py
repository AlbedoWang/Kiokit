"""Compare elapsed-time handling with the actual pinned Python Card methods.

Run: python3 Scripts/verify_review_timer_parity.py
"""
import ast
import itertools
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]

def upstream_card(clock):
    source = ROOT / "Backend/anki/pylib/anki/cards.py"
    tree = ast.parse(source.read_text())
    card = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Card")
    methods = [node for node in card.body if isinstance(node, ast.FunctionDef) and node.name in {"start_timer", "time_limit", "time_taken"}]
    assert len(methods) == 3
    namespace = {"time": clock}
    cls = ast.ClassDef(name="UpstreamCard", bases=[], keywords=[], body=methods, decorator_list=[])
    exec(compile(ast.fix_missing_locations(ast.Module(body=[cls], type_ignores=[])), str(source), "exec"), namespace)
    return namespace["UpstreamCard"]

def main():
    clock = SimpleNamespace(time=lambda: 0)
    cls = upstream_card(clock)
    process = subprocess.Popen([str(ROOT / "Core/.build/debug/AnkiProbe")], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    checked = 0
    try:
        for start, delta, limit, capped in itertools.product([0.0, 1.5, 1791810000.123],
            [-2.5, -0.0009, 0, 0.0009, 0.001, 0.9999, 1.001, 59.9999, 60.0, 60.0001, 120.5, 4294968.0], [0, 1, 60, 99999], [False, True]):
            card = cls()
            card.current_deck_id = lambda: 1
            card.col = SimpleNamespace(decks=SimpleNamespace(config_dict_for_deck_id=lambda _: {"maxTaken": limit}))
            clock.time = lambda: start
            card.start_timer()
            now = start + delta
            clock.time = lambda: now
            expected = card.time_taken(capped=capped)
            arguments = {"startedAt": start, "now": now, "limit": limit * 1000, "capped": capped}
            process.stdin.write(json.dumps({"method": "openanki.verify.ReviewTimer", "input": arguments}) + "\n")
            process.stdin.flush()
            actual = json.loads(process.stdout.readline())
            assert actual == {"value": {"milliseconds": expected}}, (arguments, expected, actual)
            checked += 1
    finally:
        process.stdin.close()
        process.wait(timeout=10)
    assert process.returncode == 0
    print(f"Verified {checked} elapsed-time outputs against the actual pinned Python Card methods.")

if __name__ == "__main__":
    main()
