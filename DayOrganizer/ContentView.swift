import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    
    @State private var taskToEdit: TaskItem?
    @State private var showingNewTaskSheet = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { task in
                    VStack(alignment: .leading) {
                        Text(task.title).font(.headline)
                        if !task.subtext.isEmpty {
                            Text(task.subtext)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        taskToEdit = task
                    }
                }
                .onDelete(perform: deleteTasks)
            }
            .navigationTitle("My Tasks")
            .toolbar {
                Button(action: { showingNewTaskSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingNewTaskSheet) {
                NewTaskView(taskToEdit: nil)
            }
            .sheet(item: $taskToEdit) { task in
                NewTaskView(taskToEdit: task)
            }
        }
    }
    
    private func deleteTasks(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
    }
}