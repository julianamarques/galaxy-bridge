import AppKit
import BridgeProtocol
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var browser: GalleryBrowser

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { browser.album ?? Self.allPhotos }, set: { browser.show(album: $0 == Self.allPhotos ? nil : $0) })) {
                Label("Todas", systemImage: "photo.on.rectangle").tag(Self.allPhotos)
                Section("Álbuns") {
                    ForEach(browser.albums) { album in
                        Label {
                            HStack {
                                Text(album.name).lineLimit(1)
                                Spacer()
                                Text(verbatim: "\(album.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: "rectangle.stack")
                        }
                        .tag(album.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            content
                .toolbar { toolbar }
        }
        .frame(minWidth: 720, minHeight: 460)
        .navigationTitle(title)
        .onAppear { browser.open() }
    }

    private static let allPhotos = "all"

    private var title: String {
        browser.album.flatMap { id in browser.albums.first { $0.id == id }?.name } ?? String(localized: "Fotos do \(app.deviceName)")
    }

    @ViewBuilder
    private var content: some View {
        if let error = browser.error, browser.entries.isEmpty {
            ContentUnavailableView {
                Label("Não foi possível abrir as fotos", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Tentar Novamente") { browser.reload() }
            }
        } else if browser.entries.isEmpty, browser.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if browser.entries.isEmpty {
            ContentUnavailableView("Nenhuma foto", systemImage: "photo")
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 4)], spacing: 4, pinnedViews: .sectionHeaders) {
                ForEach(browser.months, id: \.title) { month in
                    Section {
                        ForEach(month.entries) { entry in
                            tile(entry)
                                .onAppear { if entry.id == browser.entries.last?.id { browser.loadMore() } }
                        }
                    } header: {
                        Text(month.title)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .background(.bar)
                    }
                }
            }
            .padding(8)
            if browser.isLoading {
                ProgressView().padding()
            }
        }
    }

    private func tile(_ entry: GalleryEntry) -> some View {
        let selected = browser.selection.contains(entry.id)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(nsImage: entry.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let duration = entry.duration {
                    Label(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)), systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay {
                if selected {
                    Rectangle().strokeBorder(Color.accentColor, lineWidth: 4)
                }
            }
            .contentShape(Rectangle())
            .help(entry.name)
            .onTapGesture(count: 2) { browser.download([entry.id]) }
            .onTapGesture { select(entry.id) }
            .contextMenu {
                Button("Baixar para Downloads") { browser.download(browser.selection.contains(entry.id) ? browser.selection : [entry.id]) }
            }
    }

    private func select(_ id: String) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if browser.selection.contains(id) { browser.selection.remove(id) } else { browser.selection.insert(id) }
        } else {
            browser.selection = [id]
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { browser.download(browser.selection) } label: {
                Label("Baixar para Downloads", systemImage: "square.and.arrow.down")
            }
            .disabled(browser.selection.isEmpty)
            Button { browser.reload() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
        }
    }
}
