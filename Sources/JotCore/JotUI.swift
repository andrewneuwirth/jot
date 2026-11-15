import SwiftUI
import AppKit
import MacToolsKit

/// Jot's surfaces: the family's neutrals from MacToolsKit, plus the raised panel the content sits on (Dispatch's shape).
enum Look {
    static let accent = Color.mtJot
    static let canvas = Color.mtGround
    static let panel = Color.dynamic(light: 0xfcfcfd, dark: 0x16171b)
    static let card = Color.mtSurface
    static let line = Color.mtHairline
    static let fill = Color.mtFillInset
    static let hover = Color.mtFillHover
    static let ink = Color.mtInk
    static let muted = Color.mtInkMuted
    static let selected = Color.mtJot.opacity(0.12)
}

struct Card<Content: View>: View {
    var padding: CGFloat = MT.Space.s18
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MT.Radius.card).fill(Look.card))
            .overlay(RoundedRectangle(cornerRadius: MT.Radius.card).strokeBorder(Look.line))
            .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
    }
}

/// The filled blue capsule: the one main action on a page.
struct PrimaryButton: View {
    let title: String
    let symbol: String
    var tint = Look.accent
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1).fixedSize()
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).frame(minHeight: 32)
                .background(Capsule().fill(tint.opacity(disabled ? 0.45 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// A quiet capsule with a hairline: secondary actions.
struct SoftButton: View {
    let title: String
    let symbol: String
    var role: ButtonRole?
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1).fixedSize()   // a squeezed row wraps the text instead of the button
                .foregroundStyle(role == .destructive ? Color.mtBad : Look.ink)
                .padding(.horizontal, 12).frame(minHeight: 28)
                .background(Pill().fill(Look.fill))
                .contentShape(Pill())
                .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Look.accent : Look.muted)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(on ? Look.selected : .clear))
                .contentShape(RoundedRectangle(cornerRadius: MT.Radius.control))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color?
    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(tint ?? Look.muted)
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .background(Capsule().fill(tint?.opacity(0.12) ?? Look.fill))
        .fixedSize()
    }
}

/// A keyboard key: shortcuts read as keys, not prose.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .lineLimit(1).fixedSize()
            .foregroundStyle(Look.ink)
            .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Look.card))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.line))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

struct SearchPill: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Look.muted)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(width: 260, height: 32)
        .background(Pill().fill(Look.fill))
    }
}

/// "Notes · 12" with the page's actions on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 21, weight: .semibold)).foregroundStyle(Look.ink)
            if let detail {
                Circle().fill(.tertiary).frame(width: 4, height: 4)
                Text(detail).font(.system(size: 15)).foregroundStyle(Look.muted).lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 26)
        .frame(height: 64)
    }
}

/// Granted / not yet, always with a symbol and a word.
struct StatusPill: View {
    let ok: Bool?
    let text: String
    var body: some View {
        let tint: Color = ok == true ? .mtGood : (ok == false ? .mtWarn : Look.muted)
        Chip(text: text, symbol: ok == true ? "checkmark.circle.fill" : (ok == false ? "exclamationmark.circle.fill" : "clock"), tint: tint)
    }
}

/// A model's mark: a soft gradient tile with a symbol. Drawn here rather than copying anyone's brand artwork.
struct ModelMark: View {
    let model: SpeechModel
    var size: CGFloat = 44
    var body: some View {
        let apple = model.mode == nil
        let top = apple ? Color(white: 0.32) : Color(hue: model.hue, saturation: 0.55, brightness: 0.98)
        let bottom = apple ? Color(white: 0.12) : Color(hue: model.hue + 0.03, saturation: 0.78, brightness: 0.78)
        RoundedRectangle(cornerRadius: size * 0.26)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(.white.opacity(0.18)))
            .overlay(Image(systemName: model.symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: bottom.opacity(0.25), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

/// Speed and accuracy as five small bars.
struct Meter: View {
    let label: String
    let value: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(Look.muted)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5).fill(i <= value ? Look.accent : Look.line).frame(width: 10, height: 5)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) \(value) of 5")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Look.accent)
                .frame(width: 64, height: 64).background(Circle().fill(Look.selected))
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Look.ink)
            Text(message).font(.system(size: 13)).foregroundStyle(Look.muted).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// A list row that highlights in Jot blue when picked; the whole row clicks.
struct RowButton<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: MT.Radius.row).fill(selected ? Look.selected : (hovering ? Look.fill : .clear)))
                .contentShape(RoundedRectangle(cornerRadius: MT.Radius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A labelled settings row: title and explanation on the left, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Look.ink)
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 6)
    }
}

func saveText(_ text: String, name: String) {
    let panel = NSSavePanel(); panel.nameFieldStringValue = name
    if panel.runModal() == .OK, let url = panel.url { try? text.write(to: url, atomically: true, encoding: .utf8) }
}

func formatDuration(_ seconds: Double) -> String {
    let t = Int(max(0, seconds))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

/// A capsule drawn as a rounded rectangle: Capsule's hairline stroke left a sliver on its left edge when rendered.
struct Pill: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return Capsule().path(in: r)   // a continuous rounded rect at half-height radius flattens the ends into lines
    }
    func inset(by amount: CGFloat) -> Pill { Pill(inset: inset + amount) }
}

/// A thin progress bar in Jot blue (the system one turns grey in an inactive window).
struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Look.line)
                Capsule().fill(Look.accent).frame(width: max(6, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 6)
        .accessibilityElement().accessibilityLabel("Downloaded").accessibilityValue("\(Int(value * 100)) percent")
    }
}
