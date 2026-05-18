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
    /// Returns a dynamic color that adapts between light and dark mode so the
    /// farm remains legible without the SpriteKit scene washing out in dark
    /// environments.
    var backgroundColor: UIColor {
        switch self {
        case .spring:
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.10, green: 0.22, blue: 0.08, alpha: 1.0)
                    : UIColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1.0)
            }
        case .summer:
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.07, green: 0.20, blue: 0.04, alpha: 1.0)
                    : UIColor(red: 0.52, green: 0.78, blue: 0.30, alpha: 1.0)
            }
        case .fall:
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.18, green: 0.13, blue: 0.04, alpha: 1.0)
                    : UIColor(red: 0.72, green: 0.62, blue: 0.30, alpha: 1.0)
            }
        case .winter:
            return UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0)
                    : UIColor(red: 0.72, green: 0.80, blue: 0.90, alpha: 1.0)
            }
        }
    }
}
