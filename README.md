# OpenAnki iOS

An independent, offline flashcard app for iPhone and iPad, written in Swift and
SwiftUI using the official [Anki backend](https://github.com/ankitects/anki).
Supports deck import, spaced repetition, audio, and English/Simplified Chinese UI.
Requires iOS 17 or later. No account is needed, and no personal decks are bundled.

## Install on your iPhone with Xcode

1. Install Xcode and its iOS support. Use an Xcode version that supports your
   phone's iOS version, such as Xcode 27 for iOS 27.
2. Clone the project and build the Anki backend once in Terminal:

   ```sh
   git clone --recurse-submodules https://github.com/AlbedoWang/OpenAnkiIOS.git
   cd OpenAnkiIOS
   brew install protobuf
   bash Scripts/build_backend.sh
   ```

   The script downloads the pinned Rust toolchain and produces the local backend
   library. The first build can take a while.
3. Open `OpenAnkiIOS.xcodeproj` in Xcode and choose the **OpenAnkiIOS** scheme.
4. In **Xcode → Settings → Apple Accounts**, sign in with **your own** Apple Account.
   Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, then enter your
   own Team ID and a unique Bundle Identifier. The local file is ignored by Git.
   Use the app target's **Signing & Capabilities** to check automatic signing;
   a Personal Team works for installation on your own phone.
5. Connect and unlock your iPhone, trust the Mac, and select the phone as Xcode's
   run destination. Enable **Developer Mode** under the phone's
   **Settings → Privacy & Security** if prompted, then restart the phone.
6. Click **Run** (⌘R). Xcode builds and installs the app. OpenAnki's **Import**
   button can open an `.apkg` deck saved in Files.

See Apple's [device setup guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) for signing and connection help.

Licensed under **AGPL-3.0-or-later**. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md)
for Anki attribution and third-party licenses.
