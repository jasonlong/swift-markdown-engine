import Foundation

struct OutlineListItem: Equatable {
    let lineRange: NSRange
    let markerRange: NSRange
    let depth: Int
    let isBullet: Bool
    let isTask: Bool
    let hasChildren: Bool
    let descendantRange: NSRange?
    let reference: OutlineItemReference
}

enum OutlineListModel {
    static func items(in text: String) -> [OutlineListItem] {
        let nsText = text as NSString
        var result: [OutlineListItem] = []

        for block in DocumentAST.parse(text) {
            guard case .list(_, let listItems) = block else { continue }
            let depths = listItems.map { item in
                let whitespaceRange = NSRange(
                    location: item.range.location,
                    length: item.marker.location - item.range.location
                )
                return MarkdownLists.indentLevel(from: nsText.substring(with: whitespaceRange))
            }

            for (index, item) in listItems.enumerated() {
                let depth = depths[index]
                let hasChildren = index + 1 < listItems.count && depths[index + 1] > depth
                var descendantRange: NSRange?
                if hasChildren {
                    var descendantEnd = NSMaxRange(listItems[index + 1].range)
                    var childIndex = index + 2
                    while childIndex < listItems.count, depths[childIndex] > depth {
                        descendantEnd = NSMaxRange(listItems[childIndex].range)
                        childIndex += 1
                    }
                    descendantRange = NSRange(
                        location: listItems[index + 1].range.location,
                        length: descendantEnd - listItems[index + 1].range.location
                    )
                }

                let lineText = nsText.substring(with: trimmedLineRange(item.range, in: nsText))
                result.append(
                    OutlineListItem(
                        lineRange: item.range,
                        markerRange: item.marker,
                        depth: depth,
                        isBullet: !item.ordered && item.checkbox == nil,
                        isTask: !item.ordered && item.checkbox != nil,
                        hasChildren: hasChildren,
                        descendantRange: descendantRange,
                        reference: OutlineItemReference(
                            markerLocation: item.marker.location,
                            lineFingerprint: fingerprint(lineText)
                        )
                    )
                )
            }
        }

        return result
    }

    private static func trimmedLineRange(_ range: NSRange, in text: NSString) -> NSRange {
        var result = range
        while result.length > 0 {
            let last = text.character(at: NSMaxRange(result) - 1)
            guard last == 0x0A || last == 0x0D else { break }
            result.length -= 1
        }
        return result
    }

    private static func fingerprint(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
