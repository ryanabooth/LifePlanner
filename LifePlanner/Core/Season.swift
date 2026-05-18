import UIKit

/// The four calendar seasons derived from the device's current date.
/// Northern-hemisphere mapping: spring Mar–May, summer Jun–Aug,
/// fall Sep–Nov, winter Dec–Feb.
enum Season: CaseIterable {
    case spring, summer, fall, winter

    /// Season for a given date (Northern hemisphere).
    static func current(for date: Date = Date(), calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5:  return .spring
        case 6...8:  return .summer
        case 9...11: return .fall
        default:     return .winter  // 12, 1, 2
        }
    }

    // MARK: - Display

    var label: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall:   return "Fall"
        case .winter: return "Winter"
        }
    }

    var emoji: String {
        switch self {
        case .spring: return "🌸"
        case .summer: return "☀️"
        case .fall:   return "🍂"
        case .winter: return "❄️"
        }
    }

    // MARK: - Scene tint

    /// Sky / ground background color used by FarmScene.
    var backgroundColor: UIColor {
        switch self {
        case .spring: return UIColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1.0) // green meadow
        case .summer: return UIColor(red: 0.52, green: 0.78, blue: 0.30, alpha: 1.0) // deeper green
        case .fall:   return UIColor(red: 0.72, green: 0.62, blue: 0.30, alpha: 1.0) // warm amber
        case .winter: return UIColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1.0) // pale blue-grey
        }
    }
}
