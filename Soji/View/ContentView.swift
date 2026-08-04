import SojiKit
import SwiftUI

struct ContentView: View {
    @State private var model = ScanViewModel()
    @State private var selectedTool: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, selectedTool: $selectedTool)
        } detail: {
            TargetTableView(model: model, tool: selectedTool)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isScanning {
                    Button("停止", systemImage: "stop.fill") { model.cancelScan() }
                } else {
                    Button("スキャン", systemImage: "magnifyingglass") { model.scan() }
                }
            }
        }
        .task {
            // 起動直後にスキャンを始める。ユーザーが最初にやることは 1 つしかない。
            model.scan()
        }
    }
}

/// ツール別のカテゴリ一覧。
///
/// Why サイドバーに .glassEffect を足さないか: macOS 26 SDK でビルドすると
/// NavigationSplitView のサイドバーは自動的に Liquid Glass になる。手で
/// 重ねると glass on glass のアンチパターンになり、可読性が落ちる。
private struct SidebarView: View {
    let model: ScanViewModel
    @Binding var selectedTool: String?

    var body: some View {
        List(selection: $selectedTool) {
            Section {
                NavigationLink(value: String?.none) {
                    Label("すべて", systemImage: "square.grid.2x2")
                }
                .tag(String?.none)
            }

            Section("ツール") {
                ForEach(toolSummaries, id: \.name) { summary in
                    HStack {
                        Label(summary.name, systemImage: "shippingbox")
                        Spacer()
                        Text(summary.bytes, format: .byteCount(style: .file))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(String?.some(summary.name))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    /// ツール別の合計。大きい順に並べる。
    private var toolSummaries: [(name: String, bytes: Int64)] {
        Dictionary(grouping: model.targets, by: \.toolName)
            .map { (name: $0.key, bytes: $0.value.reduce(Int64(0)) { $0 + $1.allocatedSize }) }
            .sorted { $0.bytes > $1.bytes }
    }
}

/// 削除候補の一覧。
private struct TargetTableView: View {
    let model: ScanViewModel
    let tool: String?

    var body: some View {
        VStack(spacing: 0) {
            Table(visibleTargets) {
                TableColumn("対象") { target in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.displayName)
                        Text(target.url.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TableColumn("ツール", value: \.toolName)
                TableColumn("サイズ") { target in
                    Text(target.allocatedSize, format: .byteCount(style: .file))
                        .monospacedDigit()
                }
                TableColumn("危険度") { target in
                    Text(riskLabel(for: target))
                }
            }

            Divider()
            summaryBar
        }
        .navigationTitle(tool ?? "すべて")
        .navigationSubtitle(subtitle)
    }

    /// この段階ではプレーンな HStack。Liquid Glass は実物を見てから足す。
    private var summaryBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.selectedTargets.count) 件を選択中")
                Text("概算 \(model.selectedBytes, format: .byteCount(style: .file)) を解放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("削除") {}
                .disabled(model.selectedTargets.isEmpty)
        }
        .padding()
    }

    private var visibleTargets: [CleanTarget] {
        guard let tool else { return model.targets }
        return model.targets.filter { $0.toolName == tool }
    }

    private var subtitle: String {
        switch model.phase {
        case .idle:
            return "待機中"
        case .scanning(let completed, let total):
            return total == 0 ? "スキャン中…" : "スキャン中… \(completed)/\(total)"
        case .done:
            let bytes = model.targets.reduce(Int64(0)) { $0 + $1.allocatedSize }
            let formatted = bytes.formatted(.byteCount(style: .file))
            return "\(model.targets.count) 件 / 概算 \(formatted)"
        }
    }

    private func riskLabel(for target: CleanTarget) -> String {
        if target.isAdvisory { return "コマンドで削除" }
        switch target.risk {
        case .safe: return "安全"
        case .slowToRebuild: return "再取得が重い"
        case .needsConfirmation: return "要確認"
        }
    }
}
