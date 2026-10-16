import SwiftUI

@main
struct WakeVoteApp: App {
    @State private var model = PlannerModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 780)
        #endif
    }
}
