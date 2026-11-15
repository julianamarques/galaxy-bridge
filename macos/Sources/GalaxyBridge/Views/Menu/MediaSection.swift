import BridgeProtocol
import SwiftUI

struct MediaSection: View {
    @EnvironmentObject private var app: AppModel
    let media: MediaState

    var body: some View {
        HStack(spacing: 10) {
            artwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(media.title ?? "")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(verbatim: [media.artist, media.appName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                control("backward.fill", help: "Faixa Anterior") { app.controlMedia(.previous) }
                control(media.playing ? "pause.fill" : "play.fill", help: media.playing ? "Pausar" : "Tocar") {
                    app.controlMedia(media.playing ? .pause : .play)
                }
                control("forward.fill", help: "Próxima Faixa") { app.controlMedia(.next) }
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = media.artwork, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else if let app = media.app, let icon = self.app.phoneApps.icon(app) {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
    }

    private func control(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
