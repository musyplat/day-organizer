import SwiftUI

enum AppPage {
    case todo
    case calendar
}

struct ContentView: View {

    @State private var showMenu = false
    @State private var currentPage: AppPage = .todo

    var body: some View {

        ZStack {

            NavigationStack {

                contentView
                    .navigationTitle(currentPage == .todo ? "TODO" : "Calendar")

                    .toolbar {

                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation {
                                    showMenu.toggle()
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                        }

                    }

            }

            if showMenu {
                menuOverlay
            }

        }
    }

    @ViewBuilder
    var contentView: some View {

        switch currentPage {

        case .todo:
            TODOView()

        case .calendar:
            Text("Calendar Coming Soon")
                .font(.title)

        }

    }

    var menuOverlay: some View {

        HStack {

            VStack(alignment: .leading, spacing: 25) {

                Button {
                    currentPage = .todo
                    showMenu = false
                } label: {

                    Label("TODO", systemImage: "checklist")
                        .font(.title3)
                        .foregroundColor(currentPage == .todo ? .blue : .primary)

                }

                Button {
                    currentPage = .calendar
                    showMenu = false
                } label: {

                    Label("Calendar", systemImage: "calendar")
                        .font(.title3)
                        .foregroundColor(currentPage == .calendar ? .blue : .primary)

                }

                Spacer()

            }
            .padding()
            .frame(width: 220)
            .background(.ultraThinMaterial)

            Spacer()

        }
        .background(
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showMenu = false
                    }
                }
        )
    }

}

#Preview {
    ContentView()
}