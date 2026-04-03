import Pretext
import SwiftUI

public extension FontDescriptor {
    func makeDisplayFont() -> Font {
        Font(makeCTFont())
    }
}
