import SwiftUI
import SwiftData

// MARK: - Preference Key
// Tracks the ZStack scroll-content origin in the named "canvas" coordinate space.
// Because it uses .background(GeometryReader), it always reports the correct value
// as the ScrollView scrolls.
private struct TimelineOriginKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Calendar View

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query(sort: \ScheduledBlock.startMinute) private var allBlocks: [ScheduledBlock]

    private let today = Calendar.current.startOfDay(for: Date())

    // MARK: Drag state
    @State private var dragTask: TaskItem?          // task currently being dragged
    @State private var dragLocation: CGPoint = .zero // in "canvas" coordinate space
    @State private var isDragActive = false

    // Updated via TimelineOriginKey as the timeline ScrollView scrolls
    @State private var timelineOriginY: CGFloat = 0

    // MARK: Derived data

    private var todayBlocks: [ScheduledBlock] {
        allBlocks.filter { Calendar.current.isDate($0.dayDate, inSameDayAs: today) }
            .sorted { $0.startMinute < $1.startMinute }
    }

    private var availableTasks: [TaskItem] {
        TaskEngine.availableTasks(from: tasks, blocks: allBlocks, date: Date())
    }

    /// Snapped minute-from-midnight where the ghost block should appear.
    /// Returns nil when the drag is outside the timeline's time range.
    private var ghostMinute: Int? {
        guard isDragActive else { return nil }
        let rawY = dragLocation.y - timelineOriginY
        guard rawY >= 0, rawY <= CalendarEngine.totalHeight else { return nil }
        return CalendarEngine.snap(CalendarEngine.minute(for: rawY))
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // ── Top 55 %: scrollable timeline
                timelineSection
                    .frame(height: geo.size.height * 0.55)

                Divider()

                // ── Pool column headers
                HStack(spacing: 0) {
                    Text("Unassigned")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                    Divider().frame(height: 20)
                    Text("Assigned")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                }
                .frame(height: 38)
                .background(Color.gray.opacity(0.08))

                Divider()

                // ── Bottom ~45 %: task pools
                taskPoolsSection

            }
            // Floating pill that follows the finger during drag
            .overlay(alignment: .topLeading) {
                if let task = dragTask {
                    floatingPill(task: task)
                }
            }
        }
        .coordinateSpace(name: "canvas")
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {

                ZStack(alignment: .topLeading) {
                    hourGridLayer
                    scheduledBlocksLayer
                    currentTimeLayer
                    ghostLayer
                }
                .frame(maxWidth: .infinity)
                .frame(height: CalendarEngine.totalHeight)
                // This background GeometryReader is the correct way to track a scrolling
                // view's position. It always reports the ZStack's actual minY in canvas space.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TimelineOriginKey.self,
                            value: geo.frame(in: .named("canvas")).minY
                        )
                    }
                )

            }
            .onPreferenceChange(TimelineOriginKey.self) { value in
                timelineOriginY = value
            }
            .onAppear {
                // Slight delay so the ScrollView has finished layout before we scroll
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let hour = Calendar.current.component(.hour, from: Date())
                    if hour >= 23 {
                        proxy.scrollTo("hour-23", anchor: .bottom)
                    } else {
                        proxy.scrollTo("hour-\(max(0, hour - 1))", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: Hour Grid

    private var hourGridLayer: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(CalendarEngine.hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: CalendarEngine.gutterWidth, alignment: .trailing)
                        .padding(.trailing, 6)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                }
                .frame(height: CalendarEngine.minuteHeight * 60)
                .id("hour-\(hour)")
            }
        }
    }

    // MARK: Scheduled Blocks

    private var scheduledBlocksLayer: some View {
        ForEach(todayBlocks) { block in
            blockView(block)
        }
    }

    private func blockView(_ block: ScheduledBlock) -> some View {
        let y      = CalendarEngine.yOffset(for: block.startMinute)
        let height = max(CalendarEngine.minuteHeight * Double(block.durationMinutes), 24)

        return RoundedRectangle(cornerRadius: 7)
            .fill(block.isCompleted ? Color.gray.opacity(0.45) : Color.blue.opacity(0.78))
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.task.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(CalendarEngine.timeLabel(for: block.startMinute))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
            }
            .padding(.leading, CalendarEngine.gutterWidth + 4)
            .padding(.trailing, 8)
            .offset(y: y)
            .allowsHitTesting(false) // don't block gestures on the ZStack
    }

    // MARK: Current Time Line

    private var currentTimeLayer: some View {
        let hour   = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        let y      = CalendarEngine.yOffset(for: hour * 60 + minute)

        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                .padding(.leading, CalendarEngine.gutterWidth - 5)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
        }
        .offset(y: y)
        .allowsHitTesting(false)
    }

    // MARK: Ghost Layer

    @ViewBuilder
    private var ghostLayer: some View {
        if let task = dragTask, let minute = ghostMinute {
            ghostBlockView(task: task, minute: minute)
        }
    }

    private func ghostBlockView(task: TaskItem, minute: Int) -> some View {
        let y      = CalendarEngine.yOffset(for: minute)
        let height = max(CalendarEngine.minuteHeight * Double(task.estimatedMinutes), 24)

        return RoundedRectangle(cornerRadius: 7)
            .fill(Color.blue.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.blue.opacity(0.65), lineWidth: 1.5)
            }
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                    Text(CalendarEngine.timeLabel(for: minute))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
            }
            .padding(.leading, CalendarEngine.gutterWidth + 4)
            .padding(.trailing, 8)
            .offset(y: y)
            .allowsHitTesting(false)
    }

    // MARK: - Task Pools Section

    private var taskPoolsSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {

                // Left: Unassigned
                VStack(spacing: 6) {
                    ForEach(availableTasks, id: \.persistentModelID) { task in
                        unassignedCard(task)
                    }
                    if availableTasks.isEmpty {
                        Label("All caught up!", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)

                Divider()

                // Right: Assigned
                VStack(spacing: 6) {
                    ForEach(todayBlocks) { block in
                        assignedCard(block)
                    }
                    if todayBlocks.isEmpty {
                        Text("Drag tasks onto the timeline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(10)

            }
        }
    }

    // MARK: Unassigned Card

    private func unassignedCard(_ task: TaskItem) -> some View {
        let isBeingDragged = dragTask?.persistentModelID == task.persistentModelID

        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(task.estimatedMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    completeTask(task)
                }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isBeingDragged ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
        )
        .scaleEffect(isBeingDragged ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isBeingDragged)
        .gesture(makeDragGesture(for: task))
    }

    // MARK: Assigned Card

    private func assignedCard(_ block: ScheduledBlock) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(CalendarEngine.timeLabel(for: block.startMinute))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                modelContext.delete(block)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.blue.opacity(0.08))
        )
    }

    // MARK: Floating Pill

    private func floatingPill(task: TaskItem) -> some View {
        HStack(spacing: 6) {
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.medium)
            if let minute = ghostMinute {
                Text(CalendarEngine.timeLabel(for: minute))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .position(dragLocation)
        .allowsHitTesting(false)
    }

    // MARK: - Drag Gesture

    private func makeDragGesture(for task: TaskItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas")))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if dragTask == nil { dragTask = task }
                    isDragActive = true
                    dragLocation = drag.location
                default:
                    break
                }
            }
            .onEnded { _ in
                defer {
                    dragTask    = nil
                    isDragActive = false
                }
                guard isDragActive,
                      dragTask?.persistentModelID == task.persistentModelID,
                      let minute = ghostMinute
                else { return }
                createBlock(task: task, startMinute: minute)
            }
    }

    // MARK: - Actions

    private func createBlock(task: TaskItem, startMinute: Int) {
        let block = ScheduledBlock(task: task, dayDate: today, startMinute: startMinute)
        modelContext.insert(block)
    }

    private func completeTask(_ task: TaskItem) {
        if task.isRepeating {
            TaskEngine.markCompleted(task)
        } else {
            modelContext.delete(task)
        }
    }
}
