# OpenAnki iOS

An independent offline flashcard app built with Swift and SwiftUI for iPhone and iPad. Requires iOS 17 or later. No account or network connection is needed to study.

## Running the app

Open `OpenAnkiIOS.xcodeproj` in Xcode, select the `OpenAnkiIOS` scheme and an iOS simulator, then click Run. The first build downloads ZIPFoundation and Zstandard through Swift Package Manager. To run on a physical device, select your development team in Signing & Capabilities.

```sh
xcodebuild -project OpenAnkiIOS.xcodeproj -scheme OpenAnkiIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Features

- Create, rename, and delete decks; choose icons and colors.
- Add, edit, search, filter, move, suspend, and delete cards; create reversed cards.
- Four review ratings, learning and relearning steps, due-card queues, a daily new-card limit, and undo for the most recent review.
- Local progress storage, seven-day statistics, study streaks, recall rate, and study time.
- Import `.apkg` files, including legacy `.anki2` / `.anki21` and modern Zstandard `.anki21b` packages, plus UTF-8 CSV and TSV files.
- Common Anki templates, conditional fields, reversed cards, cloze deletions, furigana, hints, CSS, offline images, and audio.
- Export and restore full `.openanki` backups containing decks, progress, settings, and media.
- Light and dark appearance, an iPad sidebar, and keyboard shortcuts: Space reveals the answer; 1–4 select a rating.
- English and Simplified Chinese interfaces, with an explicit language selector. The default follows the device's first preferred language; unsupported languages use English. An explicit Simplified Chinese script is supported regardless of the device's region.
- Native playback of `[sound:...]` recordings. N4 Japanese words without recordings and Japanese examples use the device's Japanese voice. Word audio plays automatically during review unless disabled in Settings.

The interface takes its warm neutral palette, clay accent, thin borders, and typography hierarchy from the supplied Claude page reference. Headings use Georgia; controls use the system font. The app uses its own assets and does not bundle the downloaded page or Anthropic's proprietary fonts.

## Built-in study guide

New installations include one removable deck, **Getting started with Anki**, containing four guide cards. Its deck name, questions, answers, and tags follow the app's interface language. Language changes take effect immediately and preserve card IDs and learning progress. Imported and user-created content keeps its original language.

The previous English vocabulary and Swift sample decks are no longer included. Existing installations remove their unchanged starter cards on the next launch and delete those decks if they become empty. Migration recognizes the shipped card content and origin, preserving imported, added, moved, or edited cards rather than deleting everything with a matching deck name.

Deleting the guide or one of its cards does not recreate it later. Editing a guide card's content, tags, format, or deck makes it user-owned, so later language changes preserve those edits. A renamed guide keeps its custom name.

## Importing decks

Export an `.apkg` file from desktop Anki, save it to Files on your iPhone or iPad, and choose Import deck in OpenAnki. You can also open a supported deck from the Files share menu.

Decks with matching names are merged. Cards are deduplicated by Anki note GUID and card ordinal. Reimporting preserves existing progress and card content. Newly imported cards start as new; suspension is retained, but Anki review history is not transferred.

Reimporting an older N4 import adds pronunciation metadata to cards whose content still matches, without resetting progress. Edited cards do not receive pronunciation metadata for their old text. Editing a card's question or answer clears automatically derived pronunciation metadata to prevent stale read-aloud text.

For N4, the kana field supplies the Japanese word pronunciation. Japanese text before the slash in each example is read aloud; the Chinese translation after the slash remains visible. Speech always uses a Japanese voice regardless of the interface language. A few recordings are missing from the original package, so device speech provides a fallback. If no Japanese voice is available, the app prompts you to install one. Generic Anki `{{tts ...}}` template tags are not implemented yet.

Text imports use two required columns, front and back, plus an optional third column containing space-separated tags. CSV supports quoted commas and multiline fields; TSV uses tabs. Anki's `#separator`, `#html`, and `#deck` headers are recognized.

## Backups and data storage

Restoring an `.openanki` backup replaces the current collection after confirmation. Export a current backup before restoring. Backups include media, settings, and progress. Older backups also receive the starter-content migration and guide localization when restored.

A collection that cannot be read is never recreated or overwritten. Failed saves do not advance review progress. Media is installed before the collection is committed atomically; duplicate imports do not copy unused media folders.

## Supported scope

OpenAnki uses an independent SM-2 style scheduler. It does not integrate Anki's Rust backend or FSRS. Imported templates are rendered into independent cards, so editing one card does not update other cards from the same note.

Image occlusion, custom JavaScript, MathJax, external network resources, AnkiWeb sync, and `.colpkg` files are not supported yet. Complex templates depending on those features may need simplifying in desktop Anki.

Import limits are 256 MB per decompressed collection database, 64 MB per media file, 1 GB of total media, 100,000 cards per package, and 20,000 media files.

## Code layout

- `OpenAnkiIOS/`: SwiftUI views, Observation state, offline WebKit card rendering, and AVFoundation playback.
- `Core/`: An independently testable Swift package containing models, scheduling, atomic persistence, importers, templates, backups, built-in content migration, and localization resources.
- `Config/Info.plist`: `.apkg` and `.openanki` document type registration.
- `OpenAnkiIOSUITests/`: Simulator interaction tests.
- `Scripts/`: Icon, fixture, and localization resource generators.

Package and template formats were checked against the adjacent `../anki` source tree. The desktop Anki project is unchanged. Dependencies are pinned to [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/0.9.20) (MIT) and [Zstandard 1.5.7](https://github.com/facebook/zstd/tree/v1.5.7) (BSD / GPL dual licensing).

## Validation

Local validation passed with Xcode 26: an iOS simulator Debug build, an unsigned physical-device Release build, 22 Core tests, and 7 simulator UI tests. Tests cover starter-content migration, bilingual guide content, language changes and persistence, unsupported-language fallback, original imported content, review and undo, imports, backups, and Japanese audio.

The supplied `N4.apkg` imports 2,216 cards and 1,100 media files and passes a full backup round trip. iPhone simulator tests verify word recordings, speech fallback, Japanese examples, and Chinese meanings. The iPad layout has also been checked. The original deck file is unchanged and is not included in the repository. The local-deck Core and UI tests skip when no deck path is supplied.

```sh
swift test --package-path Core

# Optional: validate a local deck's import, media, and full backup round trip.
OPENANKI_TEST_APKG=/path/to/deck.apkg swift test --package-path Core

xcodebuild -project OpenAnkiIOS.xcodeproj -scheme OpenAnkiIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test

# Optional: verify N4 recordings, Japanese speech, and original meanings on iOS.
xcodebuild -project OpenAnkiIOS.xcodeproj -scheme OpenAnkiIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath DerivedData -parallel-testing-enabled NO \
  OPENANKI_TEST_APKG=/path/to/N4.apkg CODE_SIGNING_ALLOWED=NO test
```

Bundled test packages are small, original fixtures covering legacy and modern formats, reversed cards, cloze deletions, images, audio, and invalid media paths. The Python fixture generator is only needed to regenerate those fixtures; Python is not required to build or test the app. UI tests use a separate data directory and leave normal study data untouched.
