import Foundation

struct CalendarEngine {

    static let minuteHeight: Double = 1.2
    static let dayMinutes = 24 * 60

    // MARK: Snap Time

    static func snapToQuarterHour(_ date: Date) -> Date {

        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)

        let snapped = Int(round(Double(minute) / 15.0) * 15)

        return calendar.date(
            bySettingHour: calendar.component(.hour, from: date),
            minute: snapped,
            second: 0,
            of: date
        ) ?? date
    }

    // MARK: Convert Time → Y position

    static func yPosition(for date: Date) -> Double {

        let calendar = Calendar.current

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        let totalMinutes = (hour * 60) + minute

        return Double(totalMinutes) * minuteHeight
    }

    // MARK: Convert Y → Time

    static func timeFromYOffset(_ y: Double, baseDate: Date) -> Date {

        let minutes = Int(y / minuteHeight)

        return Calendar.current.date(
            byAdding: .minute,
            value: minutes,
            to: Calendar.current.startOfDay(for: baseDate)
        )!
    }

}