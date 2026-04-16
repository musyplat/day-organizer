import Foundation
import CoreGraphics

struct CalendarEngine {

    // MARK: - Layout

    /// Points per minute in the scroll content
    static let minuteHeight: Double = 1.5

    /// Width of the left gutter that holds hour labels
    static let gutterWidth: Double = 58

    /// Total height of the full-day content (midnight-to-midnight)
    static var totalHeight: Double { Double(24 * 60) * minuteHeight }

    // MARK: - Coordinate Conversion

    /// Y offset in the scroll content for a given minute from midnight
    static func yOffset(for minute: Int) -> Double {
        Double(clamped(minute)) * minuteHeight
    }

    /// Nearest minute from midnight for a Y offset in the scroll content
    static func minute(for yOffset: Double) -> Int {
        clamped(Int(yOffset / minuteHeight))
    }

    /// Snaps a minute value to the nearest `interval` (default 5 min)
    static func snap(_ minute: Int, to interval: Int = 5) -> Int {
        let rounded = Int(round(Double(minute) / Double(interval))) * interval
        return clamped(rounded)
    }

    // MARK: - Labels

    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }

    /// Short time string for a minute-from-midnight value, e.g. "9:30 AM"
    static func timeLabel(for minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        let displayHour = h % 12 == 0 ? 12 : h % 12
        let suffix = h < 12 ? "AM" : "PM"
        if m == 0 { return "\(displayHour) \(suffix)" }
        return "\(displayHour):\(String(format: "%02d", m)) \(suffix)"
    }

    // MARK: - Private

    private static func clamped(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}
