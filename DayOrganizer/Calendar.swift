import SwiftUI
import SwiftData

// Carries task + optional block context into the info sheet.
private struct InfoSheetItem: Identifiable {
    let task: TaskItem
    let block: ScheduledBlock?
    // Use block ID when available so unscheduled vs scheduled entries are distinct.
    var id: PersistentIdentifier { block?.persistentModelID ?? task.persistentModelID }
}

// MARK: - Calendar View

struct CalendarView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query(sort: \ScheduledBlock.startMinute) private var allBlocks: [ScheduledBlock]

    private let today = Calendar.current.startOfDay(for: Date())

    /// Blocks at or below this duration use the single-line "title + range"
    /// layout instead of the stacked layout, since their rendered height
    /// (1.5 pt/min) can't fit two lines of caption text without overflow.
    private let compactThresholdMinutes = 20

    // MARK: Drag state
    @State private var dragTask: TaskItem?         // task dragged FROM the unassigned pool
    @State private var dragBlock: ScheduledBlock?  // block being relocated FROM the timeline
    @State private var dragLocation: CGPoint = .zero // in "canvas" coordinate space
    @State private var isDragActive = false
    // Set as soon as the long-press threshold is met, before any finger movement.
    // Drives the "lifted" visual on a block so the user knows relocation is ready.
    @State private var preparingBlockID: PersistentIdentifier?

    // ZStack's top in canvas space — kept live by .onGeometryChange so programmatic
    // scrolls (e.g. the on-appear scroll to the current hour) are reflected.
    @State private var timelineOriginY: CGFloat = 0
    // Bottom edge of the timeline viewport in canvas space.
    // ghostMinute returns nil when the finger is below this boundary so that
    // dropping onto the pool area cancels the placement.
    @State private var timelineSectionBottomY: CGFloat = 0

    // MARK: Info sheet
    @State private var infoSheetItem: InfoSheetItem?

    // MARK: New-task sheet
    @State private var showingNewTaskSheet = false

    // MARK: Derived data

    // Blocks for today that should still be shown: same-day AND the underlying
    // task hasn't been completed today. Completing a repeating task from the
    // modal sets lastCompletedDate = today, which drops its block from this
    // list (timeline + Assigned column) without deleting the block itself, so
    // tomorrow's view is unaffected.
    private var todayBlocks: [ScheduledBlock] {
        allBlocks.filter {
            Calendar.current.isDate($0.dayDate, inSameDayAs: today)
            && !TaskEngine.wasCompleted($0.task, on: today)
        }
        .sorted { $0.startMinute < $1.startMinute }
    }

    private var availableTasks: [TaskItem] {
        TaskEngine.availableTasks(from: tasks, blocks: allBlocks, date: Date())
    }

    /// Snapped minute-from-midnight for the ghost block preview.
    /// Returns nil when not dragging, when the finger is over the pool area,
    /// or when the computed y falls outside the 24-hour content range.
    private var ghostMinute: Int? {
        guard isDragActive else { return nil }
        // Require layout to have fired before accepting drops.
        guard timelineSectionBottomY > 0 else { return nil }
        // Finger must be inside the timeline viewport — not over the pool below.
        guard dragLocation.y < timelineSectionBottomY else { return nil }
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
                    // Track the timeline section's bottom edge in canvas space so
                    // we can distinguish a drop on the timeline vs. a drop on the pool.
                    .onGeometryChange(for: CGFloat.self, of: { proxy in
                        proxy.frame(in: .named("canvas")).maxY
                    }) { newValue in
                        timelineSectionBottomY = newValue
                    }

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
                if isDragActive {
                    let title = dragBlock?.task.title ?? dragTask?.title ?? ""
                    floatingPill(title: title)
                }
            }
            .sheet(item: $infoSheetItem) { item in
                TaskInfoSheet(task: item.task, block: item.block)
            }
            .sheet(isPresented: $showingNewTaskSheet) {
                NewCalendarTaskSheet()
            }
            // Toolbar items declared in a child view get merged into the
            // enclosing NavigationStack's toolbar (TODOView uses the same
            // pattern), so this lands as a "+" on the top-right.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTaskSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
                // .onGeometryChange fires during animated scrolls (including
                // proxy.scrollTo) so timelineOriginY stays accurate throughout.
                .onGeometryChange(for: CGFloat.self, of: { proxy in
                    proxy.frame(in: .named("canvas")).minY
                }) { newValue in
                    timelineOriginY = newValue
                }

            }
            // Lock scrolling once the long-press has fired (preparingBlockID is set)
            // or an active drag is in progress. This prevents the ScrollView from
            // fighting the relocation drag after the gesture threshold is met.
            // While neither state is active the ScrollView scrolls freely, even
            // when the touch starts on top of a scheduled block.
            .scrollDisabled(preparingBlockID != nil || isDragActive)
            .onAppear {
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
                HStack(alignment: .top, spacing: 0) {
                    Text(CalendarEngine.hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: CalendarEngine.gutterWidth, alignment: .trailing)
                        .padding(.trailing, 6)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        let y            = CalendarEngine.yOffset(for: block.startMinute)
        let height       = max(CalendarEngine.minuteHeight * Double(block.durationMinutes), 24)
        let isPreparing  = preparingBlockID == block.persistentModelID
        let isBeingMoved = dragBlock?.persistentModelID == block.persistentModelID

        let rangeText = CalendarEngine.timeRangeLabel(
            startMinute: block.startMinute,
            durationMinutes: block.durationMinutes
        )
        // Two-line layout overflows blocks shorter than ~25 min. For 20-min
        // blocks and below, fold the range onto the title line — block height
        // stays a proportional readout of duration; only the text reflow changes.
        let isCompact = block.durationMinutes <= compactThresholdMinutes

        return RoundedRectangle(cornerRadius: 7)
            .fill(block.isCompleted ? Color.gray.opacity(0.45) : Color.blue.opacity(0.78))
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if isCompact {
                    HStack(spacing: 6) {
                        Text(block.task.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // Smaller font + lower opacity differentiates the range
                        // from the title text without needing a separator glyph.
                        Text(rangeText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .layoutPriority(1) // keep the time readable; title truncates first
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.task.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(rangeText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                }
            }
            .padding(.leading, CalendarEngine.gutterWidth + 4)
            .padding(.trailing, 8)
            // "Preparing" = long-press met but no movement yet → lift effect.
            // "Being moved" = finger is dragging → dim so the ghost is the focus.
            .scaleEffect(isPreparing ? 1.04 : 1.0)
            .opacity(isBeingMoved ? 0.3 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPreparing)
            .animation(.easeOut(duration: 0.15), value: isBeingMoved)
            .offset(y: y)
            // Haptic fires exactly when the long-press threshold is met.
            .sensoryFeedback(.impact(weight: .medium), trigger: isPreparing)
            // Gesture arbitration story:
            //   • Quick tap (down + up within TapGesture slop)  → info sheet.
            //   • Quick swipe (finger moves past LongPress slop before 0.25 s)
            //     → LongPress fails → sequenced gesture fails → ScrollView's
            //     pan takes the touch and scrolls the timeline.
            //   • Hold 0.25 s stationary → LongPress fires, preparingBlockID is
            //     set (haptic + lift), .scrollDisabled below freezes the
            //     ScrollView, and the inner DragGesture tracks the finger for
            //     relocation.
            //
            // Plain `.gesture` (not `.simultaneousGesture`) is essential here:
            // with simultaneous the ScrollView's pan competes with the latent
            // LongPress during its 0.25 s window and stalls. With `.gesture`,
            // the LongPress stays dormant and lets the ScrollView pan freely
            // until (or unless) the long-press threshold is met.
            .onTapGesture {
                infoSheetItem = InfoSheetItem(task: block.task, block: block)
            }
            .gesture(makeBlockDragGesture(for: block))
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
        .offset(y: y - 4.5)
        .allowsHitTesting(false)
    }

    // MARK: Ghost Layer

    @ViewBuilder
    private var ghostLayer: some View {
        if let minute = ghostMinute {
            if let task = dragTask {
                ghostBlockView(title: task.title,
                               durationMinutes: task.estimatedMinutes,
                               minute: minute)
            } else if let block = dragBlock {
                ghostBlockView(title: block.task.title,
                               durationMinutes: block.durationMinutes,
                               minute: minute)
            }
        }
    }

    private func ghostBlockView(title: String, durationMinutes: Int, minute: Int) -> some View {
        let y      = CalendarEngine.yOffset(for: minute)
        let height = max(CalendarEngine.minuteHeight * Double(durationMinutes), 24)
        let rangeText = CalendarEngine.timeRangeLabel(
            startMinute: minute, durationMinutes: durationMinutes
        )
        let isCompact = durationMinutes <= compactThresholdMinutes

        return RoundedRectangle(cornerRadius: 7)
            .fill(Color.blue.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.blue.opacity(0.65), lineWidth: 1.5)
            }
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if isCompact {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(rangeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                        Text(rangeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                }
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
        .contentShape(Rectangle())
        // Same arbitration pattern as blockView — see comment there. Plain
        // `.gesture` lets the enclosing pool ScrollView pan freely on a quick
        // swipe; a sustained hold commits to the sequenced drag.
        .onTapGesture {
            infoSheetItem = InfoSheetItem(task: task, block: nil)
        }
        .gesture(makeDragGesture(for: task))
    }

    // MARK: Assigned Card

    private func assignedCard(_ block: ScheduledBlock) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(CalendarEngine.timeRangeLabel(
                    startMinute: block.startMinute,
                    durationMinutes: block.durationMinutes
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NotificationManager.cancel(for: block)
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
        .contentShape(Rectangle())
        .onTapGesture {
            infoSheetItem = InfoSheetItem(task: block.task, block: block)
        }
    }

    // MARK: Floating Pill

    private func floatingPill(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
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

    // MARK: - Drag Gestures

    /// Pool-card drag. Dropping in the pool is a no-op (ghostMinute is nil
    /// when the finger is below the timeline viewport boundary).
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
                    dragTask     = nil
                    isDragActive = false
                }
                guard isDragActive,
                      dragTask?.persistentModelID == task.persistentModelID,
                      let minute = ghostMinute  // nil when dropped in pool → no block created
                else { return }
                createBlock(task: task, startMinute: minute)
            }
    }

    /// Timeline-block drag. Dropping back onto the timeline moves the block;
    /// dropping into the pool unschedules it (deletes the block so the task
    /// reappears in the unassigned pool).
    private func makeBlockDragGesture(for block: ScheduledBlock) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas")))
            .onChanged { value in
                switch value {
                case .second(true, nil):
                    // Long-press threshold met; finger hasn't moved yet.
                    // Set preparingBlockID so the block shows the "lifted" look
                    // immediately — before any dragging occurs.
                    if preparingBlockID == nil {
                        preparingBlockID = block.persistentModelID
                    }
                case .second(true, let drag?):
                    // Finger started moving — transition to active drag.
                    preparingBlockID = nil
                    if dragBlock == nil { dragBlock = block }
                    isDragActive = true
                    dragLocation = drag.location
                default:
                    break
                }
            }
            .onEnded { _ in
                defer {
                    preparingBlockID = nil
                    dragBlock        = nil
                    isDragActive     = false
                }
                guard isDragActive,
                      dragBlock?.persistentModelID == block.persistentModelID
                else { return }

                if let minute = ghostMinute {
                    // Finger released on the timeline → relocate + reschedule
                    // the notification (schedule() is replace-or-remove).
                    block.startMinute = minute
                    NotificationManager.schedule(for: block)
                } else {
                    // Finger released on the pool → unschedule.
                    NotificationManager.cancel(for: block)
                    modelContext.delete(block)
                }
            }
    }

    // MARK: - Actions

    private func createBlock(task: TaskItem, startMinute: Int) {
        let block = ScheduledBlock(task: task, dayDate: today, startMinute: startMinute)
        modelContext.insert(block)
        NotificationManager.schedule(for: block)
    }

    private func completeTask(_ task: TaskItem) {
        if task.isRepeating {
            TaskEngine.markCompleted(task)
            // Only today's blocks are hidden from view — cancel their pushes.
            let todays = task.scheduledBlocks.filter {
                Calendar.current.isDate($0.dayDate, inSameDayAs: today)
            }
            NotificationManager.cancel(for: todays)
        } else {
            // Cascade-delete will remove the blocks; cancel their pushes first.
            NotificationManager.cancel(for: task.scheduledBlocks)
            modelContext.delete(task)
        }
    }
}

// MARK: - Task Info Sheet

private struct TaskInfoSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem
    let block: ScheduledBlock?

    var body: some View {
        NavigationStack {
            Form {

                // ── Editable task details
                Section("Task Info") {

                    // Title
                    TextField("Title", text: Binding(
                        get: { task.title },
                        set: { task.title = $0 }
                    ))

                    // Notes / subtext
                    TextField("Notes", text: Binding(
                        get: { task.subtext },
                        set: { task.subtext = $0 }
                    ), axis: .vertical)
                    .lineLimit(1...4)

                    // Duration — 5-minute steps, 5 min → 8 hr
                    Stepper(
                        value: Binding(
                            get: { task.estimatedMinutes },
                            set: { task.estimatedMinutes = $0 }
                        ),
                        in: 5...480, step: 5
                    ) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(durationText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Scheduled time — only when a block exists
                    if let block {
                        DatePicker(
                            "Scheduled at",
                            selection: Binding(
                                get: {
                                    let midnight = Calendar.current.startOfDay(for: Date())
                                    return Calendar.current.date(
                                        byAdding: .minute, value: block.startMinute, to: midnight
                                    ) ?? Date()
                                },
                                set: { newDate in
                                    let midnight = Calendar.current.startOfDay(for: Date())
                                    let comps = Calendar.current.dateComponents(
                                        [.hour, .minute], from: midnight, to: newDate
                                    )
                                    block.startMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                                    NotificationManager.schedule(for: block)
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }

                // ── Per-day completion
                // Repeating task → record today's completion (task stays in
                // the Task List, disappears from today's pool + timeline).
                // Non-repeating task → remove it from the Task List entirely
                // (cascade-deletes any ScheduledBlock via the model relationship).
                Section {
                    Button(role: task.isRepeating ? nil : .destructive) {
                        if task.isRepeating {
                            TaskEngine.markCompleted(task)
                            // Suppress any pending pushes for today only.
                            let today = Calendar.current.startOfDay(for: Date())
                            let todays = task.scheduledBlocks.filter {
                                Calendar.current.isDate($0.dayDate, inSameDayAs: today)
                            }
                            NotificationManager.cancel(for: todays)
                        } else {
                            NotificationManager.cancel(for: task.scheduledBlocks)
                            modelContext.delete(task)
                        }
                        dismiss()
                    } label: {
                        Label(
                            task.isRepeating ? "Complete for Today" : "Complete Task",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                } footer: {
                    Text(task.isRepeating
                         ? "Marks this task done for today. It will return on its next scheduled day."
                         : "Removes this task from the Task List.")
                }

                // ── Calendar actions (placeholder — wired up in a future update)
                Section {
                    actionRow(label: "Push to Current Time", icon: "arrow.down.to.line.compact")
                    actionRow(label: "Move Up",              icon: "arrow.up")
                    actionRow(label: "Move Down",            icon: "arrow.down")
                    actionRow(label: "Split Task",           icon: "scissors")
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Calendar management features are coming soon.")
                }

            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func actionRow(label: String, icon: String) -> some View {
        Button(action: {}) {
            Label(label, systemImage: icon)
        }
    }

    private var durationText: String {
        let mins = task.estimatedMinutes
        guard mins >= 60 else { return "\(mins) min" }
        let hours = mins / 60
        let rem   = mins % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }
}

// MARK: - New Calendar Task Sheet

/// Mirrors `TaskInfoSheet`'s layout but for *creating* a task scheduled for
/// today. Title and notes start blank; duration defaults to 30 min; the
/// "Scheduled at" picker defaults to the next 5-minute increment from now.
private struct NewCalendarTaskSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var subtext: String = ""
    @State private var estimatedMinutes: Int = 30
    @State private var scheduledDate: Date = NewCalendarTaskSheet.nextFiveMinuteIncrement(from: Date())

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Info") {
                    TextField("Title", text: $title)

                    TextField("Notes", text: $subtext, axis: .vertical)
                        .lineLimit(1...4)

                    Stepper(
                        value: $estimatedMinutes,
                        in: 5...480, step: 5
                    ) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(durationText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    DatePicker(
                        "Scheduled at",
                        selection: $scheduledDate,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        save()
                        dismiss()
                    }
                    // Block submission for an empty title — matches TaskItem's
                    // implicit assumption that title is the primary identifier.
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var durationText: String {
        let mins = estimatedMinutes
        guard mins >= 60 else { return "\(mins) min" }
        let hours = mins / 60
        let rem   = mins % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }

    /// Smallest 5-minute boundary strictly greater than `date`. If `date`
    /// already lands on a 5-minute mark, advances to the next one (i.e. 4:55
    /// → 5:00, never 4:55 → 4:55). Seconds are stripped so the math is exact.
    private static func nextFiveMinuteIncrement(from date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let truncated = cal.date(from: comps) ?? date
        let mins = comps.minute ?? 0
        let bump = mins % 5 == 0 ? 5 : 5 - (mins % 5)
        return cal.date(byAdding: .minute, value: bump, to: truncated) ?? date
    }

    private func save() {
        let cleanTitle   = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtext = subtext.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = TaskItem(
            title: cleanTitle,
            subtext: cleanSubtext,
            estimatedMinutes: estimatedMinutes
        )
        modelContext.insert(task)

        // Use today's startOfDay as the dayDate so the block lands in the
        // current calendar day even if `scheduledDate` happened to wrap to
        // tomorrow because the bump crossed midnight.
        let today = Calendar.current.startOfDay(for: Date())
        let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduledDate)
        let startMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let block = ScheduledBlock(
            task: task,
            dayDate: today,
            startMinute: startMinute,
            durationMinutes: estimatedMinutes
        )
        modelContext.insert(block)
        NotificationManager.schedule(for: block)
    }
}
