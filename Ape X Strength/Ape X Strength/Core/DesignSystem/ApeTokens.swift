import SwiftUI

enum ApeColor {
    // Sampled from the original Reach the Ape-x screens.
    static let background = Color(red: 0.005, green: 0.006, blue: 0.12)
    static let navigation = Color(red: 0.105, green: 0.11, blue: 0.23)
    static let surface = Color(red: 0.12, green: 0.125, blue: 0.25)
    static let elevated = Color(red: 0.225, green: 0.235, blue: 0.35)
    static let control = Color(red: 0.285, green: 0.30, blue: 0.44)
    static let primary = Color(red: 0.54, green: 0.77, blue: 1.00)
    static let primaryPressed = Color(red: 0.40, green: 0.66, blue: 0.93)
    static let primarySoft = Color(red: 0.27, green: 0.29, blue: 0.44)
    static let secondary = Color(red: 0.38, green: 0.64, blue: 1.00)
    static let accent = Color(red: 0.43, green: 0.92, blue: 0.94)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.66, green: 0.66, blue: 0.68)
    static let divider = Color.white.opacity(0.52)
    static let success = Color(red: 0.10, green: 0.68, blue: 0.39)
    static let warning = Color(red: 0.96, green: 0.60, blue: 0.10)
    static let destructive = Color(red: 1.00, green: 0.34, blue: 0.38)
}

enum ApeSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum ApeRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let pill: CGFloat = 100
}

extension Font {
    static let apeLargeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let apeTitle = Font.system(size: 24, weight: .bold, design: .rounded)
    static let apeHeadline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let apeBody = Font.system(size: 16, weight: .regular, design: .rounded)
    static let apeCallout = Font.system(size: 14, weight: .medium, design: .rounded)
    static let apeCaption = Font.system(size: 12, weight: .semibold, design: .rounded)
}
