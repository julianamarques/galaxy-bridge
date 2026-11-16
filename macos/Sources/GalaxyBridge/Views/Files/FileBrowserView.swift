import AppKit
import BridgeProtocol
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var browser: FileBrowser
    @State private var selection: Set<PhoneFile.ID> = []
    @State private var isDropTarget = false

    var body: some View {
        content
            .frame(minWidth: 560, minHeight: 380)
            .navigationTitle(title)
            .toolbar { toolbar }
            .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: drop)
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { if browser.files.isEmpty { browser.refresh() } }
            .onChange(of: browser.path) { selection = [] }
    }

    private var title: String {
        browser.components.last?.name ?? String(localized: "Arquivos do \(app.deviceName)")
    }

    @ViewBuilder
    private var content: some View {
        if let error = browser.error {
            ContentUnavailableView {
                Label("Não foi possível abrir a pasta", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Tentar Novamente") { browser.refresh() }
            }
        } else if browser.files.isEmpty, browser.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if browser.files.isEmpty {
            ContentUnavailableView("Pasta vazia", systemImage: "folder", description: Text("Arraste arquivos do Mac para cá para enviá-los ao \(app.deviceName)."))
        } else {
            table
        }
    }

    private var table: some View {
        Table(browser.files, selection: $selection) {
            TableColumn("Nome") { file in
                HStack(spacing: 6) {
                    Image(nsImage: Self.icon(for: file))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(file.name).lineLimit(1)
                }
            }
            TableColumn("Tamanho") { file in
                Text(file.folder ? "—" : file.size.formatted(.byteCount(style: .file)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Modificado") { file in
                Text(Date(millis: file.modified).formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160, max: 200)
        }
        .contextMenu(forSelectionType: PhoneFile.ID.self) { ids in
            let files = selected(ids)
            if files.count == 1, let file = files.first, file.folder {
                Button("Abrir") { browser.open(file) }
            } else if files.contains(where: { !$0.folder }) {
                Button("Baixar para Downloads") { browser.download(files) }
            }
        } primaryAction: { ids in
            let files = selected(ids)
            if files.count == 1, let file = files.first {
                browser.open(file)
            } else {
                browser.download(files)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { browser.back() } label: { Label("Voltar", systemImage: "chevron.backward") }
                .disabled(!browser.canGoBack)
            Menu {
                Button(app.deviceName) { browser.open("") }
                ForEach(browser.components.dropLast(), id: \.path) { component in
                    Button(component.name) { browser.open(component.path) }
                }
            } label: {
                Label("Pastas", systemImage: "folder")
            }
            .disabled(browser.components.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if browser.isLoading, !browser.files.isEmpty {
                ProgressView().controlSize(.small)
            }
            Button { browser.download(selected(selection)) } label: {
                Label("Baixar para Downloads", systemImage: "square.and.arrow.down")
            }
            .disabled(!selected(selection).contains { !$0.folder })
            Button(action: chooseFiles) { Label("Enviar Arquivos…", systemImage: "square.and.arrow.up") }
                .disabled(!app.isAppConnected)
            Button { browser.refresh() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
        }
    }

    private func selected(_ ids: Set<PhoneFile.ID>) -> [PhoneFile] {
        browser.files.filter { ids.contains($0.id) }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Enviar")
        guard panel.runModal() == .OK else { return }
        browser.upload(panel.urls)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard app.isAppConnected else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in browser.upload([url]) }
            }
        }
        return true
    }

    private static func icon(for file: PhoneFile) -> NSImage {
        let type = file.folder ? UTType.folder : UTType(filenameExtension: (file.name as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}
