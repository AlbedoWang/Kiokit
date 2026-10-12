// Audio options adapted from ankitects/anki 26.09.3, qt/aqt/reviewer.py
// and pylib/anki/cards.py.
// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later.
import SwiftUI
import AVKit
import WebKit
import OpenAnkiCore

struct CardContentView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(CardAudioController.self) private var audio
    let card: Flashcard
    let answer: Bool
    var autoPlayAudio = false
    var showQuestionAboveAnswer = true
    var onShowAnswer: (() -> Void)?

    private var owner: String { "\(card.id)-\(answer)" }
    private var mediaURL: URL { store.mediaURL }
    private var sideAudio: [AnkiAudioTag] { (answer ? card.answerAudio : card.questionAudio) ?? [] }
    private var shouldAutoplay: Bool { autoPlayAudio && card.ankiDeckConfiguration?["autoplay"].bool == true }
    private var replayAudio: [AnkiAudioTag] {
        let replay = card.ankiDeckConfiguration?["replayq"] ?? .null
        if answer && (replay.isNull || replay.bool) {
            return (card.questionAudio ?? []) + sideAudio
        }
        return sideAudio
    }
    private var hasAudio: Bool { !replayAudio.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            content
            if audio.owner == owner, let playback = audio.videoPlayer {
                VideoPlayer(player: playback).frame(height: 220)
                    .accessibilityIdentifier("videoPlayback")
            }
            if hasAudio { audioControls }
        }
        .onAppear {
            if shouldAutoplay && !sideAudio.isEmpty {
                audio.play(sideAudio, mediaURL: mediaURL, owner: owner)
            }
        }
        .onDisappear { audio.stop(owner: owner) }
        .onChange(of: answer) { old, _ in
            audio.stop(owner: "\(card.id)-\(old)")
            if shouldAutoplay && !sideAudio.isEmpty {
                audio.play(sideAudio, mediaURL: mediaURL, owner: owner)
            }
        }
        .onChange(of: store.reviewTextGeneration) { _, _ in
            if shouldAutoplay && !sideAudio.isEmpty { audio.play(sideAudio, mediaURL: mediaURL, owner: owner) }
        }
    }

    private var audioControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button { audio.play(replayAudio, mediaURL: mediaURL, owner: owner) } label: {
                    Label(store.text("重播音频"), systemImage: "speaker.wave.2")
                        .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("readWord")
                if audio.owner == owner && audio.isPlaying {
                    Button { audio.stop(owner: owner) } label: { Image(systemName: "stop.circle") }
                        .accessibilityLabel(store.text("停止朗读")).accessibilityIdentifier("stopAudio")
                }
            }.font(.footnote).buttonStyle(.plain).foregroundStyle(AnkiTheme.tint)
            if audio.owner == owner {
                if let error = audio.error {
                    Text(store.text(error)).font(.caption).foregroundStyle(.secondary)
                } else if let source = audio.source {
                    Text(store.text(source)).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("playbackSource")
                }
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if card.isHTML {
            AnkiReviewerWebView(card: card, answer: answer, mediaURL: mediaURL, reviewing: autoPlayAudio,
                onShowAnswer: onShowAnswer,
                playAudio: { command in
                    let parts = command.split(separator: ":")
                    guard parts.count == 3, parts[0] == "play", let index = Int(parts[2]) else { return }
                    let tags = (parts[1] == "q" ? card.questionAudio : card.answerAudio) ?? []
                    if tags.indices.contains(index) { audio.play([tags[index]], mediaURL: mediaURL, owner: owner) }
                })
                .frame(minHeight: autoPlayAudio ? 60 : 220)
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    if answer && showQuestionAboveAnswer {
                        Text(card.front).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Rectangle().fill(AnkiTheme.tint.opacity(0.15)).frame(width: 46, height: 2)
                    }
                    Text(answer ? card.back : card.front)
                        .font(.system(size: answer ? 24 : 29, weight: .regular, design: .serif))
                        .foregroundStyle(AnkiTheme.ink)
                        .multilineTextAlignment(.center).lineSpacing(8)
                        .textSelection(.enabled).frame(maxWidth: .infinity)
                        .accessibilityIdentifier(answer ? "answerContent" : "questionContent")
                }.padding(.vertical, 32).padding(.horizontal, 4)
            }.defaultScrollAnchor(.center)
        }
    }
}
