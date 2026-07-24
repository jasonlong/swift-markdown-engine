import AppKit

@MainActor
public enum MarkdownEditorCommands {
    @discardableResult
    public static func cycleFocusedBulletTaskState() -> Bool {
        cycleBulletTaskState(in: NSApp.keyWindow?.firstResponder)
    }

    static func cycleBulletTaskState(in responder: NSResponder?) -> Bool {
        responder?.tryToPerform(
            NSSelectorFromString("cycleBulletTaskState:"),
            with: nil
        ) ?? false
    }
}
