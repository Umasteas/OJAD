import SwiftData
import SwiftUI

@main
struct OJADApp: App {
    private let container: ModelContainer
    @State private var library: Library

    init() {
        let container: ModelContainer
        do {
            container = try AppSchema.container()
        } catch {
            fatalError("Could not open the local store: \(error)")
        }
        self.container = container
        _library = State(initialValue: Library(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                SearchView()
                    .tabItem { Label("查询", systemImage: "magnifyingglass") }
                FavoritesView()
                    .tabItem { Label("收藏", systemImage: "star") }
                HistoryView()
                    .tabItem { Label("历史", systemImage: "clock") }
                AboutView()
                    .tabItem { Label("关于", systemImage: "info.circle") }
            }
            .environment(library)
        }
        .modelContainer(container)
    }
}
