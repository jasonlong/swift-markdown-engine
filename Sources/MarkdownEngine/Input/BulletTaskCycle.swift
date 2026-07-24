import Foundation

struct BulletTaskCycleEdit: Equatable {
    let range: NSRange
    let replacement: String
}

enum BulletTaskCycle {
    private static let prefixRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-+*])([ \t]+)(?:(\[[ xX]\])([ \t]+))?"#
    )

    static func edit(in text: String, at location: Int) -> BulletTaskCycleEdit? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }
        let safeLocation = max(0, min(location, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = nsText.substring(with: lineRange)
        guard let match = prefixRegex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ) else { return nil }

        let markerSpacing = match.range(at: 3)
        let checkbox = match.range(at: 4)
        let checkboxSpacing = match.range(at: 5)
        guard markerSpacing.location != NSNotFound else { return nil }

        if checkbox.location == NSNotFound {
            return BulletTaskCycleEdit(
                range: NSRange(
                    location: lineRange.location + NSMaxRange(markerSpacing),
                    length: 0
                ),
                replacement: "[ ] "
            )
        }

        let globalCheckbox = NSRange(
            location: lineRange.location + checkbox.location,
            length: checkbox.length
        )
        let checkboxText = nsText.substring(with: globalCheckbox)
        if checkboxText.lowercased() == "[ ]" {
            return BulletTaskCycleEdit(range: globalCheckbox, replacement: "[x]")
        }

        guard checkboxSpacing.location != NSNotFound else { return nil }
        return BulletTaskCycleEdit(
            range: NSRange(
                location: globalCheckbox.location,
                length: NSMaxRange(checkboxSpacing) - checkbox.location
            ),
            replacement: ""
        )
    }
}
