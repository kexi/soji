import SojiKit
import SwiftUI

struct ContentView: View {
    @State private var model = ScanViewModel()
    @State private var selection: SidebarSelection = .all

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, selection: $selection)
        } detail: {
            TargetListView(model: model, tool: selection.toolName)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isScanning {
                    Button("停止", systemImage: "stop.fill") { model.cancelScan() }
                } else {
                    Button("再スキャン", systemImage: "arrow.clockwise") { model.scan() }
                        .disabled(model.isDeleting)
                }
            }
        }
        .sheet(isPresented: isConfirming) {
            ConfirmDeletionSheet(model: model)
        }
        .sheet(isPresented: isDeleting) {
            DeletionProgressSheet(model: model)
        }
        .sheet(item: summary) { identified in
            DeletionResultSheet(summary: identified.summary) { model.dismissDeletionResult() }
        }
        .task {
            // 起動直後にスキャンを始める。ユーザーが最初にやることは 1 つしかない。
            model.scan()
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { model.deletion == .confirming },
            set: { if !$0 { model.cancelDeletionRequest() } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { model.isDeleting }, set: { _ in })
    }

    private var summary: Binding<IdentifiedSummary?> {
        Binding(
            get: {
                guard case .finished(let summary) = model.deletion else { return nil }
                return IdentifiedSummary(summary: summary)
            },
            set: { if $0 == nil { model.dismissDeletionResult() } })
    }
}

/// `sheet(item:)` に渡すための包み。
struct IdentifiedSummary: Identifiable {
    let id = UUID()
    let summary: ScanViewModel.DeletionSummary
}

// MARK: - sidebar

/// ツール別のカテゴリ一覧。
///
/// Why サイドバーに .glassEffect を足さないか: macOS 26 SDK でビルドすると
/// NavigationSplitView のサイドバーは自動的に Liquid Glass になる。手で
/// 重ねると glass on glass のアンチパターンになり、可読性が落ちる。
private struct SidebarView: View {
    let model: ScanViewModel
    @Binding var selection: SidebarSelection

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                Label("すべて", systemImage: "square.grid.2x2")
                    .badge(model.targets.count)
                    .tag(SidebarSelection.all)
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
                    .tag(SidebarSelection.tool(summary.name))
                }
            }
        }
        // Why 幅をハードコードしないか: macOS 27 でサイドバーが floating から
        // edge-to-edge に変わる予定で、固定値を埋めるとレイアウトが崩れる。
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    /// Why Binding を挟むか: List の選択は「未選択」を nil で表す。行の外側を
    /// クリックすると nil が入ってサイドバーの選択が消え、どこを見ているのか
    /// 分からなくなる。nil は「すべて」に丸める。
    private var selectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: { selection },
            set: { selection = $0 ?? .all })
    }

    private var toolSummaries: [(name: String, bytes: Int64)] {
        Dictionary(grouping: model.targets, by: \.toolName)
            .map { (name: $0.key, bytes: $0.value.reclaimableBytes + $0.value.advisoryBytes) }
            .sorted { $0.bytes > $1.bytes }
    }
}

/// サイドバーで選ばれているもの。
///
/// Why String? を使わないか: 「すべて」を nil で表すと、List の選択解除
/// (これも nil) と区別できず、「すべて」をクリックしても選択状態にならない。
enum SidebarSelection: Hashable {
    case all
    case tool(String)

    /// 絞り込みに使うツール名。すべてなら nil。
    var toolName: String? {
        switch self {
        case .all: return nil
        case .tool(let name): return name
        }
    }
}

// MARK: - list

private struct TargetListView: View {
    let model: ScanViewModel
    let tool: String?

    @State private var focusPath: [SunburstNode.ID] = []
    @AppStorage("showsChart") private var showsChart = true

    var body: some View {
        VStack(spacing: 0) {
            if visibleTargets.isEmpty {
                emptyState
            } else {
                if showsChart {
                    SunburstChart(root: tree, focusPath: $focusPath) { node in
                        // 葉をクリックしたら、その候補の選択を切り替える。
                        for id in node.targetIDs {
                            guard let target = model.targets.first(where: { $0.id == id }) else {
                                continue
                            }
                            toggle(target)
                        }
                    }
                    .frame(height: 300)
                    .padding(.top, 12)

                    Divider()
                }
                targetList
            }

            Divider()
            SummaryBar(model: model)
        }
        .navigationTitle(tool ?? "すべて")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $showsChart) {
                    Label("内訳", systemImage: "chart.pie")
                }
                .help("内訳グラフの表示を切り替える")
            }
        }
        // 表示対象が変わったら中心を戻す。別のツールを見ているのに前の
        // ドリルダウン位置が残ると、何を見ているのか分からなくなる。
        .onChange(of: tool) { focusPath = [] }
    }

    private var tree: SunburstNode {
        SunburstNode.build(from: visibleTargets)
    }

    private var targetList: some View {
        List {
            ForEach(visibleTargets) { target in
                TargetRow(
                    target: target,
                    isSelected: model.selection.contains(target.id),
                    toggle: { toggle(target) }
                )
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.isScanning ? "スキャン中" : "掃除するものはありません",
                systemImage: model.isScanning ? "magnifyingglass" : "checkmark.circle")
        } description: {
            Text(model.isScanning ? "キャッシュを探しています…" : "削除できるキャッシュは見つかりませんでした。")
        }
    }

    private func toggle(_ target: CleanTarget) {
        // advisory は soji が消さないので、選択させても意味がない。
        guard !target.isAdvisory else { return }
        if model.selection.contains(target.id) {
            model.selection.remove(target.id)
        } else {
            model.selection.insert(target.id)
        }
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
            let reclaimable = model.reclaimableBytes.formatted(.byteCount(style: .file))
            let advisory = model.advisoryBytes
            guard advisory > 0 else {
                return "\(model.targets.count) 件 / 概算 \(reclaimable)"
            }
            // soji が消さない分は別枠で示す。合計に混ぜると「消せる量」の嘘になる。
            let advisoryText = advisory.formatted(.byteCount(style: .file))
            return "\(model.targets.count) 件 / 概算 \(reclaimable)（別途 \(advisoryText) はコマンドで削除）"
        }
    }
}

private struct TargetRow: View {
    let target: CleanTarget
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in toggle() })) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(target.isAdvisory)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(target.displayName)
                        .fontWeight(.medium)
                    RiskBadge(target: target)
                }

                Text(target.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // 消えると何が起きるかは、ユーザーが判断する唯一の材料なので
                // 必ず出す。
                Text(target.consequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let command = target.advisoryCommand {
                    AdvisoryCommand(command: command)
                }

                if target.skippedCount > 0 {
                    Label(
                        "\(target.skippedCount) 件は権限がなく読めませんでした。実際はこれより大きい可能性があります。",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(target.allocatedSize, format: .byteCount(style: .file))
                    .monospacedDigit()
                Text("\(target.fileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
    }
}

private struct RiskBadge: View {
    let target: CleanTarget

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }

    private var label: String {
        if target.isAdvisory { return "コマンドで削除" }
        switch target.risk {
        case .safe: return "安全"
        case .slowToRebuild: return "再取得が重い"
        case .needsConfirmation: return "要確認"
        }
    }

    private var color: Color {
        if target.isAdvisory { return .purple }
        switch target.risk {
        case .safe: return .green
        case .slowToRebuild: return .orange
        case .needsConfirmation: return .red
        }
    }
}

/// ツール自身に消させるコマンド。コピーできる形で出す。
private struct AdvisoryCommand: View {
    let command: String

    var body: some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("コマンドをコピー")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
    }
}
