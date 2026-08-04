import Foundation

extension Collection where Element == CleanTarget {

    /// soji が実際に削除できる候補だけを合計したバイト数。
    ///
    /// Why 素朴な reduce を各所で書かないか: 同じ場所を複数のルールが指すこと
    /// がある。実際に pnpm のストアは「未参照分だけを pnpm に消させる advisory」
    /// と「全体を soji が消す」の 2 ルールが同じ 36.6 GB を指し、素朴に足すと
    /// 合計が 71 GB から 108 GB に水増しされた。advisory は soji が消さない
    /// ものなので合計から外し、同じ場所は 1 回だけ数える。
    public var reclaimableBytes: Int64 {
        var seenPaths = Set<String>()
        var total: Int64 = 0

        for target in self where !target.isAdvisory {
            // 同一ルールから展開された兄弟同士は別パスなので衝突しない。
            // ここで弾きたいのは「別ルールが同じ場所を指した」場合。
            let path = target.url.standardizedFileURL.path(percentEncoded: false)
            guard seenPaths.insert(path).inserted else { continue }
            total += target.allocatedSize
        }
        return total
    }

    /// soji が削除せず、ツール自身のコマンドに委ねる候補の合計。
    ///
    /// 「見えてはいるが soji では消さない」量を別枠で示すために使う。
    public var advisoryBytes: Int64 {
        var seenPaths = Set<String>()
        var total: Int64 = 0

        for target in self where target.isAdvisory {
            let path = target.url.standardizedFileURL.path(percentEncoded: false)
            guard seenPaths.insert(path).inserted else { continue }
            total += target.allocatedSize
        }
        return total
    }
}
