import SwiftUI
import SwiftData

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query(sort: \ScheduledTask.startTime)
    private var scheduled: [ScheduledTask]

    let today = Calendar.current.startOfDay(for: Date())

    var body: some View {

        HStack {

            taskPool

            Divider()

            timeline

        }

    }

    var taskPool: some View {

        let available = TaskEngine.tasksForCalendar(from: tasks, scheduled: scheduled)

        return VStack(alignment: .leading) {

            Text("Unassigned")
                .font(.headline)

            ScrollView {

                ForEach(available, id: \.persistentModelID) { task in

                    HStack {
                    
                        VStack(alignment: .leading) {
                        
                            Text(task.title)

                            Text("\(task.estimatedMinutes) min")
                                .font(.caption)
                                .foregroundColor(.secondary)

                        }

                        Spacer()

                        Button {
                            resolveTask(task)
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.title3)
                        }

                    }
                    .padding(8)
                    .background(.gray.opacity(0.1))
                    .cornerRadius(8)
                    .draggable(String(describing: task.persistentModelID))
                }

            }

            Spacer()

        }
        .frame(width: 200)
        .padding()

    }

    var timeline: some View {

        ScrollViewReader { proxy in

            ScrollView {

                ZStack(alignment: .topLeading) {
                
                    hourMarkers
                    scheduledTasks
                    currentTimeMarker

                }
                .frame(height: CalendarEngine.minuteHeight * Double(CalendarEngine.dayMinutes))
                .dropDestination(for: String.self) { items, location in

                    guard let idString = items.first else { return false }

                    scheduleTaskFromDrop(idString: idString, location: location)

                    return true
                }
                .frame(height: CalendarEngine.minuteHeight * Double(CalendarEngine.dayMinutes))
            }
            .onAppear {
            
                DispatchQueue.main.async {
                
                    let hour = Calendar.current.component(.hour, from: Date())

                    if hour >= 22 {
                        proxy.scrollTo("11pm", anchor: .bottom)
                    } else {
                        proxy.scrollTo("currentTime", anchor: .center)
                    }

                }

            }
        }

    }

    var hourMarkers: some View {
        VStack(spacing: 0) {
            ForEach(0..<24) { hour in

                HStack {
                
                    Text(hourLabel(hour))
                        .frame(width: 60, alignment: .trailing)
                        .padding(.trailing, 8)

                    Rectangle()
                        .frame(height: 1)

                }
                .frame(height: CalendarEngine.minuteHeight * 60)
                .id(hour == 23 ? "11pm" : nil)
            }
        }
    }

    var scheduledTasks: some View {

        let todayScheduled = scheduled.filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }

        return ForEach(todayScheduled) { item in

            let y = CalendarEngine.yPosition(for: item.startTime)
            let height = Double(item.durationMinutes) * CalendarEngine.minuteHeight

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.7))
                .frame(height: height)
                .overlay(
                    Text(item.task.title)
                        .foregroundColor(.white)
                        .padding(4),
                    alignment: .topLeading
                )
                .offset(y: y)

        }
    }

    var currentTimeMarker: some View {

        let y = CalendarEngine.yPosition(for: Date())

        return Rectangle()
            .fill(Color.red)
            .frame(height: 2)
            .offset(y: y)
            .id("currentTime")

    }

    func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"

        return "\(h) \(suffix)"
    }
    private func scheduleTaskFromDrop(idString: String, location: CGPoint) {

        guard let task = tasks.first(where: {
            String(describing: $0.persistentModelID) == idString
        }) else { return }

        let rawTime = CalendarEngine.timeFromYOffset(location.y, baseDate: today)

        let snapped = CalendarEngine.snapToQuarterHour(rawTime)

        let endTime = Calendar.current.date(
            byAdding: .minute,
            value: task.estimatedMinutes,
            to: snapped
        ) ?? snapped

        let newScheduled = ScheduledTask(
            task: task,
            date: today,
            startTime: snapped,
            endTime: endTime
        )

        modelContext.insert(newScheduled)
    }

    func resolveTask(_ task: TaskItem) {
        if task.repeatDays.isEmpty {
            modelContext.delete(task)
        } else {
            task.lastCompletedDate = Date()
        }
    }
}