"""Create original offline-JavaScript and media fixtures using official Anki.

Run: uv run --no-project --with anki==26.9.3 python Scripts/generate_media_fixture.py
"""
from pathlib import Path
import subprocess
import tempfile
import struct
import wave

from anki import buildinfo
from anki.collection import Collection

ROOT = Path(__file__).resolve().parents[1]

def main():
    assert buildinfo.buildhash.startswith("29bb700b")
    with tempfile.TemporaryDirectory() as directory:
        collection = Collection(str(Path(directory) / "collection.anki2"))
        collection.media.write_data("offline data.json", b'{"message":"Original offline data loaded"}')
        note = collection.new_note(collection.models.by_name("Basic"))
        note.fields = ['''<div id="offline-fetch">Loading offline data</div>
        <script>onUpdateHook.push(async () => {
            try {
                const response = await fetch('offline%20data.json');
                const data = await response.json();
                document.getElementById('offline-fetch').textContent = data.message;
            } catch (error) {
                document.getElementById('offline-fetch').textContent = 'Fetch error: ' + error;
            }
        });</script>''', "Original offline answer"]
        collection.add_note(note, collection.decks.id("Offline media"))
        collection.media.write_data("original module.mjs", b'export const message = "Original offline module loaded";')
        note = collection.new_note(collection.models.by_name("Basic"))
        note.fields = ['''<div id="offline-module">Loading offline module</div>
        <script>onUpdateHook.push(async () => {
            try {
                const module = await import('./original%20module.mjs');
                document.getElementById('offline-module').textContent = module.message;
            } catch (error) {
                document.getElementById('offline-module').textContent = 'Module error: ' + error;
            }
        });</script>''', "Original module answer"]
        collection.add_note(note, collection.decks.id("Offline module"))
        note = collection.new_note(collection.models.by_name("Basic"))
        note.fields = ['''<style>
            .original-dark { display: none; }
            html.night-mode .original-light { display: none; }
            html.night-mode .original-dark { display: block; }
        </style><div class="original-light">Original light template</div>
        <div class="original-dark">Original dark template</div>''', "Original theme answer"]
        collection.add_note(note, collection.decks.id("Original template theme"))
        clip = Path(directory) / "original clip.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=192x108:rate=24",
                        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "6",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", str(clip)], check=True)
        collection.media.add_file(str(clip))
        video_3gp = Path(directory) / "original video.3gp"
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(clip), "-c", "copy",
                        "-f", "3gp", str(video_3gp)], check=True)
        collection.media.add_file(str(video_3gp))
        audio_mp4 = Path(directory) / "original audio.mp4"
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(clip), "-vn", "-c:a", "copy",
                        str(audio_mp4)], check=True)
        collection.media.add_file(str(audio_mp4))
        following = Path(directory) / "after.wav"
        with wave.open(str(following), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(44100)
            output.writeframes(struct.pack("<h", 500) * 44100 * 4)
        collection.media.add_file(str(following))
        for deck, front in [
            ("Video playback", "Original video [sound:original clip.mp4][sound:after.wav]"),
            ("Video in audio extension", "Original 3GP video [sound:original video.3gp][sound:after.wav]"),
            ("Audio in video extension", "Original MP4 audio [sound:original audio.mp4][sound:after.wav]"),
            ("Failed video playback", "Original missing video [sound:missing.mp4][sound:after.wav]"),
            ("Unavailable speech voice", "[anki:tts lang=zz_ZZ]Original speech[/anki:tts][sound:after.wav]"),
            ("Native speech playback", "[anki:tts lang=en_US foo=bar]Original device speech, followed by an original recording from the imported deck.[/anki:tts][sound:after.wav]"),
        ]:
            note = collection.new_note(collection.models.by_name("Basic"))
            note.fields = [front, "Original media answer"]
            collection.add_note(note, collection.decks.id(deck))
        collection._backend.export_collection_package(out_path=str(ROOT / "OpenAnkiIOSUITests/media.colpkg"), include_media=True, legacy=False)

if __name__ == "__main__":
    main()
