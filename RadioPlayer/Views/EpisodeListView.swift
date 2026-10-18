import SwiftUI

enum EpisodeFilter: String, CaseIterable, Identifiable {
    case all = "すべて"
    case unlistened = "未聴"
    case favorites = "お気に入り"
    case available = "音声あり"

    var id: Self { self }
}

struct EpisodeListView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var store: ListeningStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var downloader: Downloader

    @AppStorage("selectedShow") private var show: Show = .kinyo
    @AppStorage("episodeFilter") private var filter: EpisodeFilter = .all
    @AppStorage("newestFirst") private var newestFirst = false
    @State private var query = ""
    @State private var showsSettings = false

    var body: some View {
        List {
            Section {
                ForEach(visibleEpisodes) { episode in
                    row(episode)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("音声あり \(library.fileCount(show)) 回 ／ 全 \(library.episodes(of: show).count) 回")
                    if let current = downloader.current {
                        Text("iPhone にダウンロード中：\(current.show.name) \(current.numberLabel)（残り \(downloader.remaining) 回）")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .searchable(text: $query, prompt: "タイトルや回番号で検索")
        .refreshable { await library.rescan() }
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("番組", selection: $show) {
                    ForEach(Show.allCases) { show in
                        Text(show.name).tag(show)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("絞り込み", selection: $filter) {
                        ForEach(EpisodeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    Picker("並び順", selection: $newestFirst) {
                        Text("古い順").tag(false)
                        Text("新しい順").tag(true)
                    }
                } label: {
                    Image(systemName: filter == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("絞り込みと並び順")
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }

    private var visibleEpisodes: [Episode] {
        var list = library.episodes(of: show)
        switch filter {
        case .all: break
        case .unlistened: list = list.filter { !store.state($0.id).listened }
        case .favorites: list = list.filter { store.state($0.id).favorite }
        case .available: list = list.filter { library.file(for: $0) != nil }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { String($0.number).contains(q) || $0.title.localizedCaseInsensitiveContains(q) }
        }
        return newestFirst ? list.reversed() : list
    }

    private func row(_ episode: Episode) -> some View {
        let state = store.state(episode.id)
        let file = library.file(for: episode)
        return Button {
            if let file { player.play(episode, file: file) }
        } label: {
            EpisodeRow(
                episode: episode,
                state: state,
                file: file,
                isCurrent: player.current?.id == episode.id,
                isDownloading: downloader.current?.id == episode.id
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                store.toggleFavorite(episode.id)
            } label: {
                Label(state.favorite ? "お気に入り解除" : "お気に入り",
                      systemImage: state.favorite ? "heart.slash" : "heart")
            }
            .tint(.pink)
        }
        .swipeActions(edge: .trailing) {
            Button {
                store.setListened(episode.id, !state.listened)
            } label: {
                Label(state.listened ? "未聴にする" : "聴いた",
                      systemImage: state.listened ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(state.listened ? .gray : .green)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if visibleEpisodes.isEmpty {
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if filter == .available {
                ContentUnavailableView {
                    Label("音声ファイルが見つかりません", systemImage: "music.note")
                } description: {
                    Text("左上の設定から、音声ファイルの入れ方を確認してください。")
                }
            } else {
                ContentUnavailableView("「\(filter.rawValue)」の回はありません", systemImage: "tray")
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let state: ListeningState
    let file: AudioFile?
    let isCurrent: Bool
    let isDownloading: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(episode.numberLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if isDownloading {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("iPhone にダウンロード中")
                    } else if let file, !file.isLocal {
                        Image(systemName: "icloud")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("まだ iCloud にだけある")
                    }
                    if state.favorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                            .accessibilityLabel("お気に入り")
                    }
                }
                Text(episode.displayTitle)
                    .font(.body)
                    .foregroundStyle(episode.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                if state.isInProgress {
                    ProgressView(value: state.progress)
                        .tint(.accentColor)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("再生中")
            } else if state.listened {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("聴いた")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .opacity(file == nil ? 0.4 : 1)
    }
}
