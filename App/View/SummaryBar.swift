import SojiKit
import SwiftUI

// MARK: - summary bar

/// 底部の固定サマリーバー。
///
/// ここが soji で唯一 Liquid Glass を手で足す場所。サイドバーやツールバーは
/// システムが自動で glass 化するが、この行はコンテンツの上に浮く独自要素で
/// 自動適用の対象外になる。
struct SummaryBar: View {
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
