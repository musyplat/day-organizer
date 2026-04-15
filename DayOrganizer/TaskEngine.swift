import Foundation

struct TaskEngine {
    static func tasksForCalendar(from tasks: [TaskItem], scheduled: [ScheduledTask], date: Date = Date()) -> [TaskItem] {
        let weekday = weekdayIndex(for: date)

        return tasks.filter { task in
            let isAlreadyScheduled = scheduled.contains { $0.task.id == task.id && Calendar.current.isDate($0.date, inSameDayAs: date) }
            if isAlreadyScheduled { return false }

            let repeatsToday = task.repeatDays[weekday]
            let completedToday = wasCompletedToday(task, date: date)

            if task.repeatDays.contains(true) {
                return repeatsToday && !completedToday
            }

            return true
        }
    }

    static func tasksCompletedToday(from tasks: [TaskItem], date: Date = Date()) -> [TaskItem] {

        tasks.filter {
            wasCompletedToday($0, date: date)
        }
    }

    static func markTaskCompleted(_ task: TaskItem) {
        task.lastCompletedDate = Date()
    }

    static func wasCompletedToday(_ task: TaskItem, date: Date = Date()) -> Bool {

        guard let last = task.lastCompletedDate else { return false }

        return Calendar.current.isDate(last, inSameDayAs: date)
    }

    static func weekdayIndex(for date: Date) -> Int {

        let weekday = Calendar.current.component(.weekday, from: date)

        return weekday - 1
    }

}