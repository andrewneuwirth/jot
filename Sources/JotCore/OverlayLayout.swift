import AppKit

enum OverlayLayout {
    static let width: CGFloat = 236
    static func textHeight(_ text: String) -> CGFloat {
        let text = text.isEmpty ? "Listening" : text
        let rect = (text as NSString).boundingRect(with: NSSize(width: 204, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 11)])
        return min(48, max(14, ceil(rect.height)))
    }
    static func height(_ text: String) -> CGFloat { 62 + textHeight(text) }
}
