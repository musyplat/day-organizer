//
//  ContentView.swift
//  DayOrganizer
//
//  Created by Daniel Yi on 3/7/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.timestamp) private var tasks: [TaskItem]

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { task in
                    HStack {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .onTapGesture { task.isCompleted.toggle() }
                        
                        VStack(alignment: .leading) {
                            Text(task.title)
                            Text(task.timestamp, style: .date).font(.caption)
                        }
                    }
                }
                .onDelete(perform: deleteTasks)
            }
            .navigationTitle("Productivity Node")
            .toolbar {
                Button(action: addTask) { Label("Add Task", systemName: "plus") }
            }
        }
    }

    private func addTask() {
        let newTask = TaskItem(title: "New Task", timestamp: Date())
        modelContext.insert(newTask)
    }

    private func deleteTasks(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tasks[index])
        }
    }
}