import SwiftUI
import UniformTypeIdentifiers

/// 設定：音声ファイルの入れ方、iCloud Drive のフォルダ選択、タイトル一覧の差し替え
struct SettingsView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    private enum ImportKind {
        case folder
        case catalog
    }

    @State private var importKind = ImportKind.folder
    @State private var isImporting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Show.allCases) { show in
                        LabeledContent(show.name, value: "\(library.fileCount(show)) 回")
                    }
                    Button {
                        Task { await library.rescan() }
                    } label: {
                        HStack {
                            Text("もう一度探す")
                            if library.isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(library.isScanning)
                } header: {
                    Text("見つかった音声ファイル")
                } footer: {
                    if !library.scanReport.isEmpty {
                        Text(library.scanReport.joined(separator: "\n"))
                    }
                }

                Section {
                    Text("1. Windows の「Apple Devices」アプリで iPhone を開く\n2. 左の「ファイル」を選び、「金曜・最高ラジオ」に kinyo_radio_mp3 と saikou_radio_mp3 のフォルダをドラッグする\n3. このアプリに戻ると自動で探します")
                        .font(.callout)
                } header: {
                    Text("PC から直接入れる")
                }

                Section {
                    if let name = library.folderName {
                        LabeledContent("選んだフォルダ", value: name)
                    }
                    Button(library.folderName == nil ? "フォルダを選ぶ" : "別のフォルダを選ぶ") {
                        importKind = .folder
                        isImporting = true
                    }
                    if library.folderName != nil {
                        Button("フォルダの選択をやめる", role: .destructive) {
                            library.clearFolder()
                        }
                    }
                } header: {
                    Text("iCloud Drive から入れる")
                } footer: {
                    Text("kinyo_radio_mp3 と saikou_radio_mp3 が入っている親フォルダを選んでください。まだ iPhone にダウンロードされていない回は、再生するときに読み込みます。")
                }

                Section {
                    LabeledContent("タイトルあり", value: "\(library.titledCount) / \(library.catalogCount) 回")
                    Button("新しい episodes.json を読み込む") {
                        importKind = .catalog
                        isImporting = true
                    }
                    if library.usesCustomCatalog {
                        Button("アプリに入っている一覧に戻す", role: .destructive) {
                            library.resetCatalog()
                        }
                    }
                } header: {
                    Text("タイトル一覧")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: importKind == .folder ? [.folder] : [.json]
            ) { result in
                handleImport(result)
            }
            .alert("お知らせ", isPresented: messageShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var messageShown: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            switch importKind {
            case .folder:
                library.setFolder(url)
            case .catalog:
                do {
                    let count = try library.importCatalog(from: url)
                    message = "\(count) 件のタイトル一覧を読み込みました。"
                } catch {
                    message = "読み込めませんでした：\(error.localizedDescription)"
                }
            }
        case .failure(let error):
            message = "選べませんでした：\(error.localizedDescription)"
        }
    }
}
