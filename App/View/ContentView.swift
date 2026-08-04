import SojiKit
import SwiftUI

struct ContentView: View {
    @State private var model = ScanViewModel()
    @State private var selectedTool: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, selectedTool: $selectedTool)
        } detail: {
            TargetListView(model: model, tool: selectedTool)
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
    @Binding var selectedTool: String?

    var body: some View {
        List(selection: $selectedTool) {
            Section {
                Label("すべて", systemImage: "square.grid.2x2")
                    .badge(model.targets.count)
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
        // Why 幅をハードコードしないか: macOS 27 でサイドバーが floating から
        // edge-to-edge に変わる予定で、固定値を埋めるとレイアウトが崩れる。
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    private var toolSummaries: [(name: String, bytes: Int64)] {
        Dictionary(grouping: model.targets, by: \.toolName)
            .map { (name: $0.key, bytes: $0.value.reclaimableBytes + $0.value.advisoryBytes) }
            .sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - list

private struct TargetListView: View {
    let model: ScanViewModel
    let tool: String?

    var body: some View {
        VStack(spacing: 0) {
            if visibleTargets.isEmpty {
                emptyState
            } else {
                targetList
            }

            Divider()
            SummaryBar(model: model)
        }
        .navigationTitle(tool ?? "すべて")
        .navigationSubtitle(subtitle)
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

// MARK: - summary bar

/// 底部の固定サマリーバー。
///
/// ここが soji で唯一 Liquid Glass を手で足す場所。サイドバーやツールバーは
/// システムが自動で glass 化するが、この行はコンテンツの上に浮く独自要素で
/// 自動適用の対象外になる。
private struct SummaryBar: View {
    let model: ScanViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.deletableTargets.count) 件を選択中")
                        .fontWeight(.medium)
                    // 「概算」を必ず出す。APFS のクローンは du を含めて
                    // 二重計上するため、実解放量は必ずこれ以下になる。
                    Text("概算 \(model.selectedBytes, format: .byteCount(style: .file)) を解放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let capacity = model.capacity {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("空き \(capacity.available, format: .byteCount(style: .file))")
                            .monospacedDigit()
                        // Finder の表示と食い違う理由を先に示す。
                        Text("ほかに \(capacity.purgeable, format: .byteCount(style: .file)) は自動解放")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Button("削除", systemImage: "trash") {
                    model.requestDeletion()
                }
                .buttonStyle(.glassProminent)
                .disabled(model.deletableTargets.isEmpty || model.isDeleting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            // Why .regular not .clear: .clear は背後に減光レイヤーを敷かないと
            // 文字が読めなくなる。この行はコンテンツの上に直接浮くので背景を
            // 制御できず、.regular が唯一の正解。
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .padding(12)
        // Why 枠線を自前で足すか: Reduce Transparency 時に glassEffect の
        // 透明度はシステムが落としてくれるが、カード境界の消失までは
        // 補われない。分岐は枠線の有無だけに留める。
        .overlay {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
                    .padding(12)
            }
        }
    }
}
