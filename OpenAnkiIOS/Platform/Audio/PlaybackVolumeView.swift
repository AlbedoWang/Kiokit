import SwiftUI
import MediaPlayer

struct PlaybackVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsRouteButton = false
        view.tintColor = UIColor(AnkiTheme.tint)
        view.accessibilityIdentifier = "playbackVolume"
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
