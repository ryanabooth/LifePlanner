import Foundation
import SwiftData

protocol WeatherInteractor {
    func rollDaily(on date: Date, in context: ModelContext)
    func activeEvent(in context: ModelContext) -> DBModel.WeatherEvent?
}

final class RealWeatherInteractor: WeatherInteractor {

    private let economy: EconomyInteractor
    private let farm: FarmInteractor
    private let calendar: Calendar

    init(economy: EconomyInteractor, farm: FarmInteractor, calendar: Calendar = .current) {
        self.economy = economy
        self.farm = farm
        self.calendar = calendar
    }

    // MARK: - Roll

    func rollDaily(on date: Date, in context: ModelContext) {
        let today = calendar.startOfDay(for: date)
        // Idempotent: if a weather event already covers today, do nothing.
        guard !eventExists(for: today, in: context) else { return }

        let kind = rollKind()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let event = DBModel.WeatherEvent(kind: kind, startedAt: today, expiresAt: tomorrow)
        context.insert(event)

        applyImmediateEffects(for: kind, in: context)
    }

    // MARK: - Active event

    func activeEvent(in context: ModelContext) -> DBModel.WeatherEvent? {
        let now = Date()
        let all = (try? context.fetch(FetchDescriptor<DBModel.WeatherEvent>())) ?? []
        return all.first { $0.startedAt <= now && $0.expiresAt > now }
    }

    // MARK: - Private

    private func eventExists(for day: Date, in context: ModelContext) -> Bool {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let all = (try? context.fetch(FetchDescriptor<DBModel.WeatherEvent>())) ?? []
        return all.contains { $0.startedAt >= day && $0.startedAt < tomorrow }
    }

    private func rollKind() -> WeatherKind {
        let total = WeatherKind.rollTable.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<total)
        for (kind, weight) in WeatherKind.rollTable {
            roll -= weight
            if roll < 0 { return kind }
        }
        return .clear
    }

    private func applyImmediateEffects(for kind: WeatherKind, in context: ModelContext) {
        switch kind {
        case .sunshine:
            economy.credit(FarmTuning.weatherSunshineGold, reason: "sunshine", in: context)
        case .storm:
            applyStormDamage(in: context)
        default:
            break
        }
    }

    /// Deals `FarmTuning.weatherStormDamage` health to one random non-dead,
    /// non-common-field plot. If no eligible plot exists, the storm fizzles.
    private func applyStormDamage(in context: ModelContext) {
        let plots = (try? context.fetch(FetchDescriptor<DBModel.FarmPlot>())) ?? []
        let eligible = plots.filter { $0.kind != .commonField && $0.state != .dead }
        guard let target = eligible.randomElement() else { return }
        target.health = max(0, target.health - FarmTuning.weatherStormDamage)
        if target.health <= 0 {
            target.state = .withered
        } else if target.health < FarmTuning.matureThreshold {
            target.state = .growing
        }
        target.updatedAt = Date()
    }
}

final class StubWeatherInteractor: WeatherInteractor {
    func rollDaily(on date: Date, in context: ModelContext) {}
    func activeEvent(in context: ModelContext) -> DBModel.WeatherEvent? { nil }
}
