import SojiKit
import SwiftUI

/// 同心円リングで容量の内訳を見せる。
///
/// Why not Swift Charts: SectorMark は 1 段のドーナツを前提としており、
/// 任意深度の階層リングとセグメント単位のヒットテストを表現できない。
/// Canvas なら Path.addArc で描画・当たり判定・アニメーションを一元管理できる。
struct SunburstChart: View {
    let root: SunburstNode

    /// 中心から辿っている経路。末尾が現在の表示中心。
    @Binding var focusPath: [SunburstNode.ID]

    /// セグメントをクリックしたとき。葉なら選択のトグルに使う。
    var onSelect: (SunburstNode) -> Void

    @State private var hovered: SunburstNode.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            breadcrumb

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let segments = layout(in: size)

                // Why frame を二重に指定しないか: 内側で正方形に固定してから
                // 外側で最大化すると、Canvas 自身の座標系と GeometryReader の
                // 座標系がずれ、ヒットテストの中心計算が合わなくなる。
                // Canvas を全面に広げ、描画側で中央を出す。
                Canvas { context, canvasSize in
                    draw(segments, in: context, canvasSize: canvasSize)
                }
                .contentShape(.rect)
                .onTapGesture { location in
                    handleTap(at: location, segments: segments, canvasSize: proxy.size, ringSize: size)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered =
                            hit(
                                location, segments: segments, canvasSize: proxy.size, ringSize: size)?.node.id
                    case .ended:
                        hovered = nil
                    }
                }
                .overlay { centerLabel }
                // Why 明示的にアニメーションさせるか: 削除でリングが縮む変化は
                // 「掃除できた」という手応えそのもの。値の変化に追従させる。
                .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: focused.bytes)
            }
        }
    }

    // MARK: - focus

    /// いま中心に据えている節。
    private var focused: SunburstNode {
        var node = root
        for id in focusPath {
            guard let next = node.children.first(where: { $0.id == id }) else { break }
            node = next
        }
        return node
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button("すべて") { focusPath = [] }
                .buttonStyle(.link)
                .disabled(focusPath.isEmpty)

            ForEach(Array(breadcrumbNodes.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button(node.name) { focusPath = Array(focusPath.prefix(index + 1)) }
                    .buttonStyle(.link)
                    .disabled(index == breadcrumbNodes.count - 1)
            }
            Spacer()
        }
        .font(.caption)
        .lineLimit(1)
    }

    /// ホバー中の節。`focused` の子孫から探す。
    private var hoveredNode: SunburstNode? {
        guard let hovered else { return nil }
        func search(_ node: SunburstNode) -> SunburstNode? {
            if node.id == hovered { return node }
            for child in node.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(focused)
    }

    private var breadcrumbNodes: [SunburstNode] {
        var nodes: [SunburstNode] = []
        var current = root
        for id in focusPath {
            guard let next = current.children.first(where: { $0.id == id }) else { break }
            nodes.append(next)
            current = next
        }
        return nodes
    }

    /// 中心の表示。
    ///
    /// ホバー中はその節を出す。細くてラベルが描けないセグメントでも、
    /// 何を指しているかがここで分かる。
    private var centerLabel: some View {
        let shown = hoveredNode ?? focused
        return VStack(spacing: 2) {
            Text(shown.bytes, format: .byteCount(style: .file))
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(shown.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 110)
        }
        .padding(.horizontal, 8)
        // 中心をクリックすると 1 段戻る。
        .contentShape(.rect)
        .onTapGesture {
            guard !focusPath.isEmpty else { return }
            focusPath.removeLast()
        }
        .help(focusPath.isEmpty ? "" : "クリックで 1 つ戻る")
    }

    // MARK: - layout

    /// 描画に必要な情報を持つ 1 セグメント。
    private struct Segment {
        let node: SunburstNode
        let depth: Int
        let start: Angle
        let end: Angle
        /// この節へ移動するための経路。
        let path: [SunburstNode.ID]
    }

    private static let maxDepth = 3

    private func layout(in size: CGFloat) -> [Segment] {
        var segments: [Segment] = []
        let node = focused
        guard node.bytes > 0 else { return segments }

        func place(
            _ children: [SunburstNode], depth: Int, from: Angle,
            total: Int64, path: [SunburstNode.ID]
        ) {
            guard depth <= Self.maxDepth, total > 0 else { return }
            var cursor = from
            for child in children {
                let sweep = Angle.degrees(360 * Double(child.bytes) / Double(total))
                // 1 度未満は描いても見えず、当たり判定も取れない。
                guard sweep.degrees >= 0.5 else { continue }
                let childPath = path + [child.id]
                segments.append(
                    Segment(
                        node: child, depth: depth, start: cursor, end: cursor + sweep, path: childPath))
                place(
                    child.children, depth: depth + 1, from: cursor, total: total, path: childPath)
                cursor += sweep
            }
        }

        place(node.children, depth: 1, from: .degrees(-90), total: node.bytes, path: focusPath)
        return segments
    }

    /// Why 実際の深さで帯幅を決めるか: maxDepth 固定で割ると、階層が 2 段
    /// しかないときに 3 段分の幅で描かれ、外側に空白が残って間延びする。
    /// 描かれる段数に合わせて埋める。
    private func radius(
        forDepth depth: Int, in size: CGFloat, levels: Int
    ) -> (inner: CGFloat, outer: CGFloat) {
        let usable = size / 2 - 8  // 縁に少し余白を残す
        // 中心にラベル用の穴を空ける。段数が少ないほど穴は小さくてよい。
        let hole = usable * (levels >= 3 ? 0.30 : 0.38)
        let band = (usable - hole) / CGFloat(max(levels, 1))
        let inner = hole + band * CGFloat(depth - 1)
        return (inner, inner + band - 2)
    }

    // MARK: - draw

    private func draw(_ segments: [Segment], in context: GraphicsContext, canvasSize: CGSize) {
        let size = min(canvasSize.width, canvasSize.height)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let levels = segments.map(\.depth).max() ?? 1

        for segment in segments {
            let radii = radius(forDepth: segment.depth, in: size, levels: levels)
            let path = arcPath(center: center, radii: radii, from: segment.start, to: segment.end)

            let isHovered = hovered == segment.node.id
            context.fill(
                path,
                with: .color(color(for: segment.node, depth: segment.depth, hovered: isHovered)))

            // 境界線で扇形を分ける。塗りだけだと隣と溶ける。
            context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 0.5)

            drawLabel(for: segment, radii: radii, center: center, in: context)
        }
    }

    /// 十分な幅があるセグメントにだけ名前を描く。
    ///
    /// Why 幅で足切りするか: 細い扇形に文字を置いても読めず、隣と重なって
    /// 全体が汚れる。読めないラベルは無いほうがよい。
    private func drawLabel(
        for segment: Segment, radii: (inner: CGFloat, outer: CGFloat),
        center: CGPoint, in context: GraphicsContext
    ) {
        let sweep = segment.end.degrees - segment.start.degrees
        let bandWidth = radii.outer - radii.inner
        let midRadius = (radii.inner + radii.outer) / 2
        // 弧の長さが確保できないと文字が入らない。
        let arcLength = midRadius * CGFloat(sweep) * .pi / 180
        let hasRoom = sweep >= 24 && bandWidth >= 26 && arcLength >= 54
        guard hasRoom else { return }

        let midAngle = Angle.degrees(segment.start.degrees + sweep / 2)
        let point = CGPoint(
            x: center.x + midRadius * cos(midAngle.radians),
            y: center.y + midRadius * sin(midAngle.radians))

        let text = Text(segment.node.name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
        context.draw(context.resolve(text), at: point, anchor: .center)
    }

    private func arcPath(
        center: CGPoint, radii: (inner: CGFloat, outer: CGFloat), from start: Angle, to end: Angle
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center, radius: radii.outer,
            startAngle: start, endAngle: end, clockwise: false)
        path.addArc(
            center: center, radius: radii.inner,
            startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// 危険度で色相を決め、外側ほど薄くする。
    ///
    /// 内側 (大きな分類) を濃くすることで、階層の向きが色でも分かる。
    private func color(for node: SunburstNode, depth: Int, hovered: Bool) -> Color {
        let base = baseColor(for: node)
        guard !hovered else { return base }
        // depth は 1 始まり。外側 1 段ごとに 12% ずつ薄くする。
        let fade = 0.88 - Double(depth - 1) * 0.12
        return base.opacity(max(0.5, fade))
    }

    private func baseColor(for node: SunburstNode) -> Color {
        if node.containsAdvisory { return .purple }
        switch node.risk {
        case .safe: return .green
        case .slowToRebuild: return .orange
        case .needsConfirmation: return .red
        }
    }

    // MARK: - interaction

    private func handleTap(
        at location: CGPoint, segments: [Segment], canvasSize: CGSize, ringSize: CGFloat
    ) {
        guard let segment = hit(location, segments: segments, canvasSize: canvasSize, ringSize: ringSize)
        else { return }

        // 枝ならドリルダウン、葉なら選択のトグル。
        if segment.node.isLeaf {
            onSelect(segment.node)
        } else {
            focusPath = segment.path
        }
    }

    private func hit(
        _ location: CGPoint, segments: [Segment], canvasSize: CGSize, ringSize: CGFloat
    ) -> Segment? {
        // Canvas は全面に広がっているので、中心はそのまま真ん中。
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        let offsetX = location.x - center.x
        let offsetY = location.y - center.y
        let distance = sqrt(offsetX * offsetX + offsetY * offsetY)

        var degrees = atan2(offsetY, offsetX) * 180 / .pi
        // レイアウトは -90 度から始めているので、同じ基準に揃える。
        if degrees < -90 { degrees += 360 }

        let levels = segments.map(\.depth).max() ?? 1
        return segments.first { segment in
            let radii = radius(forDepth: segment.depth, in: ringSize, levels: levels)
            let inBand = distance >= radii.inner && distance <= radii.outer
            let inSweep = degrees >= segment.start.degrees && degrees < segment.end.degrees
            return inBand && inSweep
        }
    }
}
