import AppKit
import SwiftUI
import SlimPomoCore

/// sRGB channels shared by the SwiftUI and AppKit tokens.
struct ThemeRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    func color(alpha: Double) -> Color {
        Color(red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Deep-water colors. Every painted color in the windows comes from here.
enum Theme {
    static let bgBaseRGB = ThemeRGB(hex: 0x0E1A21)
    static let bgCardRGB = ThemeRGB(hex: 0x13262E)
    static let bgCardHoverRGB = ThemeRGB(hex: 0x183640)
    static let bgCardActiveRGB = ThemeRGB(hex: 0x17343F)
    static let bgFieldRGB = ThemeRGB(hex: 0x0B161C)
    static let lineFieldRGB = ThemeRGB(hex: 0x22404A)
    static let lineSubtleRGB = ThemeRGB(hex: 0x1A2D35)
    static let tankAirRGB = ThemeRGB(hex: 0x15303A)
    static let gaugeInnerRGB = ThemeRGB(hex: 0x1D3640)
    static let textStrongRGB = ThemeRGB(hex: 0xFFFFFF)
    static let textPrimaryRGB = ThemeRGB(hex: 0xE6F2F3)
    static let textOnWaterRGB = ThemeRGB(hex: 0xCFE9EC)
    static let textSecondaryRGB = ThemeRGB(hex: 0x7FA7AD)
    static let textTertiaryRGB = ThemeRGB(hex: 0x58808A)
    static let textHeaderLabelRGB = ThemeRGB(hex: 0xA9CDD1)
    static let textMutedRGB = ThemeRGB(hex: 0x6F9AA0)
    static let linkRGB = ThemeRGB(hex: 0x8FC9CF)
    static let linkDisabledRGB = ThemeRGB(hex: 0x2F4C55)
    static let countRingRGB = ThemeRGB(hex: 0xCFE6E8)
    static let destructiveRGB = ThemeRGB(hex: 0xF09A8F)

    static let dipSurfaceRGB = ThemeRGB(hex: 0x9BE59A)
    static let dipWaterRGB = ThemeRGB(hex: 0x2F8A5C)
    static let diveSurfaceRGB = ThemeRGB(hex: 0x2EC4D6)
    static let diveWaterRGB = ThemeRGB(hex: 0x1A7686)
    static let deepSurfaceRGB = ThemeRGB(hex: 0x6F7CF2)
    static let deepWaterRGB = ThemeRGB(hex: 0x2E3F9A)

    static let breakCardRGB = ThemeRGB(hex: 0xF1DFB8)
    static let breakWaterRGB = ThemeRGB(hex: 0xDCBD82)
    static let breakSurfaceRGB = ThemeRGB(hex: 0xC9A868)
    static let breakTextRGB = ThemeRGB(hex: 0x2A2415)
    static let breakTextSecondaryRGB = ThemeRGB(hex: 0x4A3F28)
    static let breakScaleRGB = ThemeRGB(hex: 0x7A6A45)
    static let breakPillRGB = ThemeRGB(hex: 0xE8CF9E)

    static let bgBase = bgBaseRGB.color
    static let bgBaseNS = bgBaseRGB.nsColor
    static let bgCard = bgCardRGB.color
    static let bgCardHover = bgCardHoverRGB.color
    static let bgCardActive = bgCardActiveRGB.color
    static let bgField = bgFieldRGB.color
    static let lineField = lineFieldRGB.color
    static let lineSubtle = lineSubtleRGB.color
    static let tankAir = tankAirRGB.color
    static let gaugeInner = gaugeInnerRGB.color
    static let textStrong = textStrongRGB.color
    static let textPrimary = textPrimaryRGB.color
    static let textOnWater = textOnWaterRGB.color
    static let textSecondary = textSecondaryRGB.color
    static let textTertiary = textTertiaryRGB.color
    static let textHeaderLabel = textHeaderLabelRGB.color
    static let textMuted = textMutedRGB.color
    static let link = linkRGB.color
    static let linkDisabled = linkDisabledRGB.color
    static let countRing = countRingRGB.color
    static let countRingNS = countRingRGB.nsColor
    static let destructive = destructiveRGB.color
    static let destructiveNS = destructiveRGB.nsColor

    static let breakCard = breakCardRGB.color
    static let breakWater = breakWaterRGB.color
    static let breakSurface = breakSurfaceRGB.color
    static let breakText = breakTextRGB.color
    static let breakTextSecondary = breakTextSecondaryRGB.color
    static let breakScale = breakScaleRGB.color
    static let breakPill = breakPillRGB.color

    static let diveSurface = diveSurfaceRGB.color

    /// Icon hover and press from the UI basics: white at 6% and 10%.
    static let hoverWashNS = NSColor(white: 1, alpha: 0.06)
    static let pressedWashNS = NSColor(white: 1, alpha: 0.10)
    /// Whole-row hover on a collapsible section header: white at 4%.
    static let headerHoverWashNS = NSColor(white: 1, alpha: 0.04)
    /// Lifted queue card. Black at 35%.
    static let dragShadow = Color.black.opacity(0.35)
    /// Tour dim. Unchanged at about 55% black.
    static let tourScrim = Color.black.opacity(0.55)

    static func surfaceRGB(_ mode: Intensity) -> ThemeRGB {
        switch mode {
        case .regular: dipSurfaceRGB
        case .focus: diveSurfaceRGB
        case .intense: deepSurfaceRGB
        }
    }

    static func waterRGB(_ mode: Intensity) -> ThemeRGB {
        switch mode {
        case .regular: dipWaterRGB
        case .focus: diveWaterRGB
        case .intense: deepWaterRGB
        }
    }

    static func surface(_ mode: Intensity) -> Color { surfaceRGB(mode).color }
    static func water(_ mode: Intensity) -> Color { waterRGB(mode).color }
}
