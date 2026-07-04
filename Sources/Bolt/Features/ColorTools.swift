import AppKit

// Screen eyedropper (NSColorSampler) + conversions for typed hex colors.
enum ColorTools {

    // Launches the native magnifier eyedropper. Called after the panel
    // hides so the loupe isn't sampling our own window.
    static func pickColor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSColorSampler().show { color in
                guard let color = color?.usingColorSpace(.sRGB) else { return }
                let hex = hexString(color)
                ClipboardManager.shared.ignoreNextChange = true
                PasteHelper.copy(text: hex)
                Toast.show("\(hex) copied  ·  \(rgbString(color))", symbol: "eyedropper.halffull", duration: 2.6)
            }
        }
    }

    static func hexString(_ color: NSColor) -> String {
        String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }

    static func rgbString(_ color: NSColor) -> String {
        String(
            format: "rgb(%d, %d, %d)",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }

    static func hslString(_ color: NSColor) -> String {
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        if maxV != minV {
            let d = maxV - minV
            s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            switch maxV {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h /= 6
        }
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h * 360, s * 100, l * 100)
    }

    // Parses "#ff8800", "ff8800", "#f80".
    static func parseHex(_ input: String) -> NSColor? {
        var hex = input.trimmingCharacters(in: .whitespaces).lowercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 3 || hex.count == 6,
              hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
