#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_cache="${OPENANKI_TOOL_CACHE:-$HOME/Library/Caches/Kiokit}"
export RUSTUP_HOME="$task_cache/rustup"
export CARGO_HOME="$task_cache/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
    mkdir -p "$task_cache"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$task_cache/rustup-init.sh"
    sh "$task_cache/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain 1.97.1
fi
export PROTOC_BINARY="${PROTOC_BINARY:-$(command -v protoc)}"
export DESCRIPTORS_BIN="$task_root/Backend/generated/descriptors.bin"
export STRINGS_PY="$task_root/Backend/generated/_fluent.py"
export STRINGS_TS="$task_root/Backend/generated/ftl.ts"
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export MACOSX_DEPLOYMENT_TARGET=14.0
task_expected=29bb700b951e3f0c0cb69b77c0180fc1fe33e6ba
test "$(git -C "$task_root/Backend/anki" rev-parse HEAD)" = "$task_expected"
python3 "$task_root/Scripts/verify_upstream_dependencies.py"
git -C "$task_root/Backend/anki" submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
mkdir -p "$task_root/Backend/generated"
cd "$task_root/Backend"
if [[ "${1:-}" = "--test" ]]; then
    cargo test --locked --lib
    exit 0
fi
if [[ "${1:-}" = "--host" ]]; then
    cargo build --locked --release --target aarch64-apple-darwin
    exit 0
fi
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
for task_target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    cargo build --locked --release --target "$task_target"
done
task_simulator_lib="$task_root/Backend/generated/libopenanki_simulator.a"
lipo -create \
    "$task_root/Backend/target/aarch64-apple-ios-sim/release/libopenanki_backend.a" \
    "$task_root/Backend/target/x86_64-apple-ios/release/libopenanki_backend.a" \
    -output "$task_simulator_lib"
task_output="$task_root/Core/AnkiBackendFFI.xcframework"
task_staging="$task_root/Backend/generated/AnkiBackendFFI.xcframework"
if [[ -d "$task_staging" ]]; then rm -rf "$task_staging"; fi
xcodebuild -create-xcframework \
    -library "$task_root/Backend/target/aarch64-apple-darwin/release/libopenanki_backend.a" -headers "$task_root/Backend/include" \
    -library "$task_root/Backend/target/aarch64-apple-ios/release/libopenanki_backend.a" -headers "$task_root/Backend/include" \
    -library "$task_simulator_lib" -headers "$task_root/Backend/include" \
    -output "$task_staging"
if [[ -d "$task_output" ]]; then rm -rf "$task_output"; fi
mv "$task_staging" "$task_output"
