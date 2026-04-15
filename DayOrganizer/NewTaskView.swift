import SwiftUI
import SwiftData

struct NewTaskView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var task: TaskItem? = nil

    @State private var title = ""
    @State private var subtext = ""
    @State private var timeInput = "30"
    @State private var timeUnit = "Mins"
    @State private var days = Array(repeating: false, count: 7)

    let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    let units = ["Mins", "Hours"]

    var body: some View {

        NavigationStack {

            Form {

                Section("Task Info") {
                    TextField("Title", text: $title)
                    TextField("Notes (Subtext)", text: $subtext)
                }

                Section("Estimation") {

                    HStack {

                        TextField("30", text: $timeInput)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)

                        Picker("Unit", selection: $timeUnit) {
                            ForEach(units, id: \.self) { unit in
                                Text(unit)
                            }
                        }
                        .pickerStyle(.segmented)

                    }

                }

                Section("Repeat Days") {

                    HStack {

                        ForEach(0..<7) { index in

                            Text(dayLabels[index])
                                .frame(width: 30, height: 30)
                                .background(days[index] ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(days[index] ? .white : .primary)
                                .clipShape(Circle())
                                .onTapGesture {
                                    days[index].toggle()
                                }

                        }

                    }

                }

                if task != nil {

                    Section {

                        Button(role: .destructive) {
                            deleteCurrentTask()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Task")
                                Spacer()
                            }
                        }

                    }

                }

            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")

            .onAppear {
                populateFieldsIfEditing()
            }

            .toolbar {

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                    }
                }

            }

        }

    }

    private func populateFieldsIfEditing() {

        guard let task else { return }

        title = task.title
        subtext = task.subtext
        days = task.repeatDays

        if task.estimatedMinutes >= 60 && task.estimatedMinutes % 60 == 0 {
            timeInput = "\(task.estimatedMinutes / 60)"
            timeUnit = "Hours"
        } else {
            timeInput = "\(task.estimatedMinutes)"
            timeUnit = "Mins"
        }

    }

    private func saveTask() {

        let inputNum = Int(timeInput) ?? 30
        let totalMinutes = (timeUnit == "Hours") ? (inputNum * 60) : inputNum

        if let task {

            task.title = title
            task.subtext = subtext
            task.estimatedMinutes = totalMinutes
            task.repeatDays = days

        } else {

            let newTask = TaskItem(
                title: title,
                subtext: subtext,
                estimatedMinutes: totalMinutes,
                repeatDays: days
            )

            modelContext.insert(newTask)

        }

        dismiss()

    }

    private func deleteCurrentTask() {

        guard let task else { return }

        modelContext.delete(task)
        dismiss()

    }

}