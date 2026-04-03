import SwiftUI

struct DemoRGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum DemoPaperPalette {
    static let paperRGB = DemoRGBColor(
        red: 246 / 255,
        green: 240 / 255,
        blue: 230 / 255
    )
    static let inkRGB = DemoRGBColor(
        red: 17 / 255,
        green: 16 / 255,
        blue: 13 / 255
    )

    static let paper = paperRGB.color
    static let ink = inkRGB.color
}
