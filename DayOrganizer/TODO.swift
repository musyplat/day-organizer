import SwiftUI
import SwiftData

struct TODOView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TaskItem.title)
    private var tasks: [TaskItem]

    @State private var showingNewTaskSheet = false
    @State private var editingTask: TaskItem?

    @State private var completingTasks: Set<TaskItem.ID> = []

    var body: some View {

        VStack {

            if tasks.isEmpty {

                Spacer()

                Text("No tasks to complete!")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Spacer()

            } else {

                List {

                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                    .onDelete(perform: deleteTasks)

                }
                .animation(.easeInOut, value: tasks)

            }

        }
        .toolbar {

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewTaskSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

        }

        .sheet(isPresented: $showingNewTaskSheet) {
            NewTaskView()
        }

        .sheet(item: $editingTask) { task in
            NewTaskView(task: task)
        }

    }

    func taskRow(_ task: TaskItem) -> some View {

        let isCompleting = completingTasks.contains(task.id)

        return HStack(spacing: 12) {

            Button {
                completeTask(task)
            } label: {

                Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .scaleEffect(isCompleting ? 1.25 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isCompleting)
                    .padding(6)

            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {

                Text(task.title)
                    .font(.headline)

                if !task.subtext.isEmpty {

                    Text(task.subtext)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                }

            }

            Spacer()

        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingTask = task
        }

        .opacity(isCompleting ? 0 : 1)

        .scaleEffect(isCompleting ? 0.9 : 1)

        .animation(.easeOut(duration: 0.35), value: isCompleting)

    }

    private func deleteTasks(offsets: IndexSet) {

        for index in offsets {
            modelContext.delete(tasks[index])
        }

    }

    private func completeTask(_ task: TaskItem) {

        completingTasks.insert(task.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            modelContext.delete(task)
            completingTasks.remove(task.id)
        }

    }

}