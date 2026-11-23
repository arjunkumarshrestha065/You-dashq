import SwiftUI
import UIKit
import AudioToolbox
import Observation

/// Touch keyboard sized to the visible car screen, with immediate key feedback.
struct YCPCarKeyboard: View {
    @Binding var text: String
    let placeholder: String
    var secure = false
    let onGo: () -> Void
    let onDone: () -> Void
    @State private var symbols = false
    @State private var shifted = false
    @AppStorage("browser.keyboard.arabic") private var arabic = false

    private var rows: [[String]] {
        if symbols {
            return [Array(arabic ? "١٢٣٤٥٦٧٨٩٠" : "1234567890").map(String.init), Array("@#$/&*()-_").map(String.init), Array(arabic ? "،.؟!\":;+=" : ".,?!'\":;+=" ).map(String.init)]
        }
        if arabic {
            return [Array("ضصثقفغعهخحجد").map(String.init), Array("شسيبلاتنمكط").map(String.init),
                    ["ئ", "ء", "ؤ", "ر", "لا", "ى", "ة", "و", "ز", "ظ", "ذ"]]
        }
        return [Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init), Array("zxcvbnm").map(String.init)]
    }

    var body: some View {
        GeometryReader { geometry in
            let canvas = CGSize(width: min(geometry.size.width, 1060), height: min(geometry.size.height, 420))
            let metrics = CarKeyboardMetrics(size: canvas, arabic: arabic && !symbols, symbols: symbols)
            VStack(spacing: metrics.gap) {
                entryBar(metrics: metrics)
                    .padding(.bottom, metrics.gap / 2)
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: metrics.gap) {
                        if index == 2 && !symbols && !arabic {
                            key("shift", metrics: metrics, width: metrics.unit * 1.35,
                                selected: shifted, symbol: true, secondary: true) { shifted.toggle() }
                                .accessibilityLabel("Shift")
                                .accessibilityValue(shifted ? "On" : "Off")
                        }
                        ForEach(rows[index], id: \.self) { character in
                            let label = shifted && !symbols && !arabic ? character.uppercased() : character
                            key(label, metrics: metrics, width: metrics.unit) {
                                text += label
                                if shifted { shifted = false }
                            }
                            .contextMenu {
                                if arabic, character == "ا" {
                                    ForEach(["أ", "إ", "آ"], id: \.self) { variant in
                                        Button(variant) { BrowserKeyboardFeedback.shared.tap(); text += variant }
                                    }
                                }
                            }
                        }
                        if index == 2 {
                            key("delete.left", metrics: metrics, width: metrics.unit * 1.35,
                                symbol: true, secondary: true) {
                                if !text.isEmpty { text.removeLast() }
                            }
                            .accessibilityLabel("Delete last character")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: metrics.gap) {
                    key(symbols ? (arabic ? "أبج" : "ABC") : "123", metrics: metrics,
                        width: metrics.unit * 1.4, secondary: true) { symbols.toggle() }
                        .accessibilityLabel(symbols ? "Letters" : "Numbers and symbols")
                    key(arabic ? "EN" : "عربي", metrics: metrics, width: metrics.unit * 1.4, secondary: true) {
                        arabic.toggle(); shifted = false
                    }
                    .accessibilityLabel(arabic ? "Switch to English keyboard" : "Switch to Arabic keyboard")
                    key(arabic ? "مسافة" : "Space", metrics: metrics) { text += " " }
                        .accessibilityLabel("Space")
                    key(arabic ? "بحث" : "Search", metrics: metrics, width: metrics.unit * 1.8,
                        selected: true, trailingSymbol: "arrow.right", action: onGo)
                        .accessibilityLabel(arabic ? "بحث" : "Go")
                }
            }
            .padding(metrics.inset)
            .frame(width: canvas.width, height: canvas.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(YCPKeyboardTheme.ground)
        .foregroundStyle(YCPKeyboardTheme.ink)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { BrowserKeyboardFeedback.shared.prepare() }
    }

    private func entryBar(metrics: CarKeyboardMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(YCPKeyboardTheme.inkMuted)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Text(text.isEmpty ? placeholder : secure ? String(repeating: "•", count: text.count) : text)
                                .font(.system(size: metrics.entryFont, weight: .medium))
                                .foregroundStyle(text.isEmpty ? YCPKeyboardTheme.inkMuted : YCPKeyboardTheme.ink)
                                .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
                            if !text.isEmpty {
                                RoundedRectangle(cornerRadius: 1).fill(YCPKeyboardTheme.accent)
                                    .frame(width: 2, height: metrics.entryFont + 4)
                            }
                            Color.clear.frame(width: 1).id("caret")
                        }
                        .frame(height: metrics.entryHeight)
                    }
                    .onChange(of: text) { _, _ in proxy.scrollTo("caret", anchor: .trailing) }
                }
                .accessibilityLabel(secure ? "Secure text entry" : "Text entry")
                .accessibilityValue(secure ? "Hidden" : text)
                if !text.isEmpty {
                    Button {
                        BrowserKeyboardFeedback.shared.tap(); text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 44, height: metrics.entryHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(YCPKeyboardTheme.inkMuted)
                    .accessibilityLabel("Clear text")
                }
            }
            .padding(.leading, metrics.inset)
            .background(YCPKeyboardTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(YCPKeyboardTheme.hairline))
            key("xmark", metrics: metrics, width: metrics.entryHeight, height: metrics.entryHeight,
                symbol: true, secondary: true, action: onDone)
                .accessibilityLabel("Close keyboard")
        }
    }

    private func key(_ label: String, metrics: CarKeyboardMetrics, width: CGFloat? = nil,
                     height: CGFloat? = nil, selected: Bool = false, symbol: Bool = false,
                     secondary: Bool = false, trailingSymbol: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button {
            BrowserKeyboardFeedback.shared.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if symbol { Image(systemName: label) }
                else { Text(label).minimumScaleFactor(0.75).lineLimit(1) }
                if let trailingSymbol { Image(systemName: trailingSymbol).font(.system(size: metrics.font * 0.65, weight: .bold)) }
            }
            .font(.system(size: secondary || label.count > 2 ? metrics.font * 0.8 : metrics.font,
                          weight: .medium))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height ?? metrics.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrowserKeyboardKeyStyle(selected: selected, secondary: secondary, primary: trailingSymbol != nil))
    }
}

/// Calculated from the actual keyboard bounds, independently of the page's design canvas.
private struct CarKeyboardMetrics {
    let gap: CGFloat
    let inset: CGFloat
    let entryHeight: CGFloat
    let keyHeight: CGFloat
    let unit: CGFloat
    let font: CGFloat
    let entryFont: CGFloat

    init(size: CGSize, arabic: Bool, symbols: Bool) {
        gap = size.height < 300 ? 4 : size.width < 600 ? 6 : 8
        inset = size.width < 600 ? 8 : 16
        entryHeight = min(58, max(44, size.height * 0.14))
        keyHeight = min(76, max(26, (size.height - entryHeight - inset * 2 - gap * 4.5) / 4))
        let columns: CGFloat = arabic ? 13 : symbols ? 12 : 10
        unit = max(16, (size.width - inset * 2 - gap * (columns - 1)) / columns)
        font = min(30, max(20, unit * 0.38))
        entryFont = min(26, max(20, entryHeight * 0.42))
    }
}

private struct BrowserKeyboardKeyStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast
    let selected: Bool
    let secondary: Bool
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fill = primary ? YCPKeyboardTheme.accent : selected ? YCPKeyboardTheme.ink : configuration.isPressed ? Color(white: 0.32) : secondary ? YCPKeyboardTheme.surface : YCPKeyboardTheme.raised
        configuration.label
            .foregroundStyle(selected && !primary ? YCPKeyboardTheme.ground : YCPKeyboardTheme.ink)
            .background(fill,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                focused ? YCPKeyboardTheme.accent : contrast == .increased ? YCPKeyboardTheme.inkMuted : YCPKeyboardTheme.hairline,
                lineWidth: focused ? 3 : 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.16), radius: 0, y: 2)
            // Keep the entire hit target stable; only its color changes under the finger.
    }
}

@MainActor
private final class BrowserKeyboardFeedback {
    static let shared = BrowserKeyboardFeedback()
    private let selection = UISelectionFeedbackGenerator()
    private var click: SystemSoundID = 0
    private init() {
        if let file = Bundle.main.url(forResource: "keyboard-click", withExtension: "wav")
            ?? Bundle.main.url(forResource: "keyboard-click", withExtension: "wav", subdirectory: "Browser") {
            AudioServicesCreateSystemSoundID(file as CFURL, &click)
        }
    }
    func prepare() { selection.prepare() }
    func tap() {
        selection.selectionChanged()
        selection.prepare()
        if click != 0 { AudioServicesPlaySystemSound(click) }
    }
}


private enum YCPKeyboardTheme {
    static let ground = Color(white: 0.059)
    static let surface = Color(white: 0.125)
    static let raised = Color(white: 0.18)
    static let ink = Color.white
    static let inkMuted = Color(white: 0.67)
    static let accent = Color(red: 1, green: 0, blue: 0)
    static let hairline = Color.white.opacity(0.08)
}

private struct YCPKeyboardRoot: View {
    @State var text: String
    let secure: Bool
    let onChange: (String) -> Void
    let onGo: () -> Void
    let onDone: () -> Void
    var body: some View {
        YCPCarKeyboard(text: $text, placeholder: "Search YouTube", secure: secure, onGo: onGo, onDone: onDone)
            .preferredColorScheme(.dark)
            .onChange(of: text) { _, value in onChange(value) }
    }
}

@objc(YCPKeyboardFactory)
@MainActor final class YCPKeyboardFactory: NSObject {
    @objc(makeWithText:secure:onChange:onGo:onDone:)
    static func make(text: String, secure: Bool, onChange: @escaping (String) -> Void,
                     onGo: @escaping () -> Void, onDone: @escaping () -> Void) -> UIViewController {
        UIHostingController(rootView: YCPKeyboardRoot(text: text, secure: secure, onChange: onChange, onGo: onGo, onDone: onDone))
    }
}
