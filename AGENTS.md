# Hard Constraints

These rules apply to the entire Kiokit repository and all future changes.

## Anki Is the Source of Truth

- All application and domain logic MUST be copied from or delegated to the official Anki implementation: https://github.com/ankitects/anki.
- Do not independently design, implement, simplify, approximate, or substitute Anki's logic. Similar behavior, the same algorithm name, or compatibility with an Anki file format is not sufficient.
- This requirement includes scheduling, SM-2 and FSRS behavior, learning and relearning steps, interval calculation, fuzzing, card gathering and sorting, random order, queue construction, daily limits, day boundaries, sibling burying, suspension, undo, review history, statistics, deck options, collection operations, import/export, note types, templates, rendering, and media handling.
- Reuse Anki's upstream backend and source wherever possible. If a language or platform adaptation is necessary, translate the upstream implementation faithfully; do not replace its rules with a newly written algorithm.
- Swift and iOS-specific code may provide the interface and the necessary platform bindings, storage access, and audio integration. Such code MUST NOT introduce alternative domain rules or change Anki's semantics.

## Implementation and Verification

- Before implementing or changing logic, locate the corresponding implementation in the official Anki repository. Prefer the pinned submodule at `Backend/anki`; a checkout at `../anki` may also be used after verifying that its origin and revision match the official repository above.
- Pin the upstream version or commit used. Record that revision and the relevant upstream source paths for copied or adapted logic so its provenance can be reviewed.
- Preserve upstream defaults, state transitions, data meaning, and supported configuration behavior. Do not silently discard imported scheduling state, review history, or deck settings, and do not reset imported cards to new unless the upstream import operation does so under the same options.
- Verify copied or adapted behavior against Anki's implementation and upstream tests. Include relevant boundary cases, configuration differences, randomness/fuzzing, and persistence behavior. Tests that only agree with our own implementation do not establish Anki parity.
- If upstream behavior cannot yet be reproduced, report the gap explicitly and leave that feature incomplete. Do not use a handwritten fallback or claim Anki equivalence without evidence.
- Existing custom implementations are NOT exceptions to these constraints. Any handwritten scheduler, random-order algorithm, or other replacement for Anki's domain logic MUST be replaced with upstream logic; this file does not make such implementations compliant.
- Preserve upstream copyright and license notices when reusing source code.

## Documentation

- Keep this file, the README, and source comments/docstrings in English.
- Distinguish verified upstream behavior from incomplete migrations or unsupported Anki features when documenting or reporting the application's behavior.
