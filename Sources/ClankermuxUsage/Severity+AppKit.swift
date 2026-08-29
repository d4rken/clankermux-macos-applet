import AppKit
import ClankermuxCore
import SwiftUI

// The Cinnamon stylesheet's fixed hexes are tuned for a dark panel. The system palette carries the
// same green/orange/red meanings while adapting to the active appearance.
extension Severity {
    var accentColor: NSColor {
        switch self {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    var accent: Color { Color(nsColor: accentColor) }
}

extension DetailStyle {
    var titleColor: Color {
        switch self {
        case .normal: return Color(nsColor: .labelColor)
        case .warning: return Color(nsColor: .systemOrange)
        case .error: return Color(nsColor: .systemRed)
        }
    }

    var subtitleColor: Color {
        switch self {
        case .normal: return Color(nsColor: .secondaryLabelColor)
        case .warning: return Color(nsColor: .systemOrange)
        case .error: return Color(nsColor: .systemRed)
        }
    }
}

extension StateKey {
    var accent: Color {
        switch self {
        case .available: return Color(nsColor: .systemGreen)
        case .paused, .limited: return Color(nsColor: .systemOrange)
        case .error: return Color(nsColor: .systemRed)
        }
    }
}
