import Foundation
import SwiftData

enum WeatherKind: Int, Codable, CaseIterable {
    case clear    = 0
    case sunshine = 1
    case rain     = 2
    case drought  = 3
    case storm    = 4

    var emoji: String {
        switch self {
        case .clear:    return "🌤"
        case .sunshine: return "☀️"
        case .rain:     return "🌧"
        case .drought:  return "🔥"
        case .storm:    return "⛈"
        }
    }

    var label: String {
        switch self {
        case .clear:    return "Clear"
        case .sunshine: return "Sunshine"
        case .rain:     return "Rain"
        case .drought:  return "Drought"
        case .storm:    return "Storm"
        }
    }

    var effectDescription: String {
        switch self {
        case .clear:    return "No modifiers today. Enjoy the mild weather."
        case .sunshine: return "The common field pays passive gold today."
        case .rain:     return "Habit contributions are doubled today."
        case .drought:  return "Task contributions are halved and decay is 50% faster today."
        case .storm:    return "Chaos struck — one random plot took storm damage."
        }
    }

    /// Multiplier applied to habit contribution amounts.
    var habitMultiplier: Double { self == .rain ? 2.0 : 1.0 }

    /// Multiplier applied to task contribution amounts.
    var taskMultiplier: Double { self == .drought ? 0.5 : 1.0 }

    /// Multiplier applied to daily plot decay.
    var decayMultiplier: Double { self == .drought ? 1.5 : 1.0 }

    /// Weighted probability table. Weights sum to 100.
    static let rollTable: [(WeatherKind, Int)] = [
        (.clear,    40),
        (.sunshine, 20),
        (.rain,     20),
        (.drought,  15),
        (.storm,     5),
    ]
}

extension DBModel {
    /// A single 24-hour weather episode. One row per day; `startedAt` is the
    /// start of the calendar day and `expiresAt` is the start of the next day.
    @Model
    final class WeatherEvent {
        var id: UUID = UUID()
        var kindRaw: Int = WeatherKind.clear.rawValue
        var startedAt: Date = Date()
        var expiresAt: Date = Date()
        var createdAt: Date = Date()

        init(
            id: UUID = UUID(),
            kind: WeatherKind = .clear,
            startedAt: Date = Date(),
            expiresAt: Date = Date(),
            createdAt: Date = Date()
        ) {
            self.id = id
            self.kindRaw = kind.rawValue
            self.startedAt = startedAt
            self.expiresAt = expiresAt
            self.createdAt = createdAt
        }
    }
}

extension DBModel.WeatherEvent {
    var kind: WeatherKind {
        get { WeatherKind(rawValue: kindRaw) ?? .clear }
        set { kindRaw = newValue.rawValue }
    }
}
