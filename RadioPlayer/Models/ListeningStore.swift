import Foundation

/// 1回ごとの聴取状況
struct ListeningState: Codable, Equatable {
    var position: Double = 0
    var duration: Double = 0
    var listened = false
    var favorite = false

    /// 0〜1 の進み具合
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
    /// 途中まで聴いた（バーを出す）
    var isInProgress: Bool { !listened && position > 1 && duration > 0 }
}

/// 再生位置・聴いた・お気に入りを UserDefaults に保存する
@MainActor
final class ListeningStore: ObservableObject {
    @Published private(set) var states: [String: ListeningState]

    private let defaultsKey = "listeningStates"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: ListeningState].self, from: data) {
            states = decoded
        } else {
            states = [:]
        }
    }

    func state(_ id: String) -> ListeningState {
        states[id] ?? ListeningState()
    }

    func updatePosition(_ id: String, position: Double, duration: Double) {
        var state = state(id)
        state.position = position
        if duration > 0 { state.duration = duration }
        set(state, for: id)
    }

    func setListened(_ id: String, _ listened: Bool) {
        var state = state(id)
        state.listened = listened
        // 未聴に戻したら最初から
        if !listened { state.position = 0 }
        set(state, for: id)
    }

    func toggleFavorite(_ id: String) {
        var state = state(id)
        state.favorite.toggle()
        set(state, for: id)
    }

    private func set(_ state: ListeningState, for id: String) {
        guard states[id] != state else { return }
        states[id] = state
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
