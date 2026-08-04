import SwiftUI

@main
struct SojiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // サイドバー付きの一覧なので、狭すぎる初期サイズだと内容が潰れる。
        .defaultSize(width: 1000, height: 640)
        .commands {
            // 掃除アプリに新規ウィンドウの概念は無い。
            CommandGroup(replacing: .newItem) {}
        }
    }
}
