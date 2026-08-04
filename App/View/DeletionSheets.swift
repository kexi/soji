import SojiKit
import SwiftUI

/// 削除前の確認。
///
/// Why 確認を挟むか: 削除は取り消せない。既定選択が safe だけとはいえ、
/// ユーザーが要確認の項目を足していることがある。
struct ConfirmDeletionSheet: View {
    let model: ScanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(model.deletableTargets.count) 件を削除します", systemImage: "trash")
                .font(.title3)
                .fontWeight(.semibold)

            Text("概算 \(model.selectedBytes, format: .byteCount(style: .file)) を解放します。ゴミ箱には入らず、完全に削除されます。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.riskySelection.isEmpty {
                riskyList
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                // Why 既定ボタンにしないか: keyboardShortcut(.defaultAction) を
                // 付けると Enter 連打で削除が走る。取り消せない操作なので
                // マウスで明示的に押させる。
                Button("削除する") { model.confirmDeletion() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    /// 取り返しがつかない可能性がある項目は個別に列挙する。
    private var riskyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("以下は再生成に手間がかかります", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .fontWeight(.medium)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.riskySelection) { target in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(target.toolName) / \(target.displayName)")
                                .font(.callout)
                            Text(target.consequence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
        .padding(12)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}

/// 削除中の進捗。
struct DeletionProgressSheet: View {
    let model: ScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("削除しています")
                .font(.title3)
                .fontWeight(.semibold)

            if case .running(let path, let completed, let total) = model.deletion {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))

                Text("\(completed) / \(total)")
                    .font(.callout)
                    .monospacedDigit()

                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("中止") { model.cancelDeletion() }
            }
        }
        .padding(24)
        .frame(width: 460)
        // 削除中に閉じられると進捗が見えなくなる。閉じる手段は中止だけ。
        .interactiveDismissDisabled()
    }
}

/// 削除後のレポート。
struct DeletionResultSheet: View {
    let summary: ScanViewModel.DeletionSummary
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(summary.failures.isEmpty ? Color.primary : Color.orange)

            // Why 概算と実測を並べるか: APFS のクローンで概算は必ず過大に出る。
            // 事後に実測を見せて、数字の意味を学習してもらう。
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("削除した項目") {
                    Text("\(summary.deletedCount) 件").monospacedDigit()
                }
                LabeledContent("概算") {
                    Text(summary.estimatedBytes, format: .byteCount(style: .file))
                        .monospacedDigit()
                }
                if let freed = summary.freedBytes {
                    LabeledContent("実際に解放された容量") {
                        Text(freed, format: .byteCount(style: .file))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                }
            }

            if !summary.failures.isEmpty {
                failureList
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("閉じる", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        if summary.wasCancelled { return "削除を中止しました" }
        if summary.failures.isEmpty { return "削除しました" }
        return "一部を削除できませんでした"
    }

    private var icon: String {
        summary.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var failureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(summary.failures.count) 件は削除できませんでした")
                .font(.callout)
                .fontWeight(.medium)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.failures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.url.path(percentEncoded: false))
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(failure.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let suggestion = failure.suggestion {
                                Text(suggestion)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
    }
}
