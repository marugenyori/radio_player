import Foundation

/// 番組（金曜ラジオ / 最高ラジオ）
enum Show: String, CaseIterable, Codable, Identifiable, Sendable {
    case kinyo
    case saikou

    var id: String { rawValue }

    var name: String {
        switch self {
        case .kinyo: "金曜ラジオ"
        case .saikou: "最高ラジオ"
        }
    }

    var fullName: String {
        switch self {
        case .kinyo: "セブ山・永田の金曜ラジオ"
        case .saikou: "セブ山・永田の最高ラジオ"
        }
    }

    /// 全何回あるか（一覧にはこの数まで並べる）
    var episodeCount: Int {
        switch self {
        case .kinyo: 250
        case .saikou: 194
        }
    }
}

/// 1回分
struct Episode: Identifiable, Hashable, Sendable {
    let show: Show
    let number: Int
    var title: String

    var id: String { Episode.key(show, number) }

    static func key(_ show: Show, _ number: Int) -> String { "\(show.rawValue)-\(number)" }

    var numberLabel: String { "第\(number)回" }
    var displayTitle: String { title.isEmpty ? "（タイトル不明）" : title }
}
