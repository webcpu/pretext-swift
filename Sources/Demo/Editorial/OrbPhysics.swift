import CoreGraphics
import Foundation

struct OrbState: Equatable, Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var radius: Double
    var vx: Double
    var vy: Double
    var color: RGBColor
    var paused = false
    var dragging = false
}

struct RGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

struct OrbDragState: Equatable {
    var orbIndex: Int
    var startPointer: CGPoint
    var startCenter: CGPoint
}

private struct OrbDefinition {
    var fx: Double
    var fy: Double
    var radius: Double
    var vx: Double
    var vy: Double
    var color: RGBColor
}

private let orbDefinitions: [OrbDefinition] = [
    OrbDefinition(fx: 0.52, fy: 0.22, radius: 110, vx: 24, vy: 16, color: RGBColor(red: 196 / 255, green: 163 / 255, blue: 90 / 255)),
    OrbDefinition(fx: 0.18, fy: 0.48, radius: 85, vx: -19, vy: 26, color: RGBColor(red: 100 / 255, green: 140 / 255, blue: 1)),
    OrbDefinition(fx: 0.74, fy: 0.58, radius: 95, vx: 16, vy: -21, color: RGBColor(red: 232 / 255, green: 100 / 255, blue: 130 / 255)),
    OrbDefinition(fx: 0.38, fy: 0.72, radius: 75, vx: -26, vy: -14, color: RGBColor(red: 80 / 255, green: 200 / 255, blue: 140 / 255)),
    OrbDefinition(fx: 0.86, fy: 0.18, radius: 65, vx: -13, vy: 19, color: RGBColor(red: 150 / 255, green: 100 / 255, blue: 220 / 255)),
]

private func visibleOrbDefinitions(
    for platform: DemoNavigationPlatform
) -> [(index: Int, definition: OrbDefinition)] {
    let indexedDefinitions = orbDefinitions.enumerated().map { (index: $0.offset, definition: $0.element) }
    guard platform == .watchOS else {
        return indexedDefinitions
    }

    let hiddenIndices = Set(
        indexedDefinitions
            .sorted { $0.definition.radius > $1.definition.radius }
            .prefix(2)
            .map(\.index)
    )

    return indexedDefinitions.filter { !hiddenIndices.contains($0.index) }
}

private func orbRadiusScale(
    for pageSize: CGSize,
    platform: DemoNavigationPlatform
) -> Double {
    if platform == .watchOS {
        return 1.0 / 3.0
    }

    return min(pageSize.width, pageSize.height) <= 640 ? (2.0 / 3.0) : 1.0
}

func makeInitialOrbStates(
    pageSize: CGSize,
    platform: DemoNavigationPlatform = .current
) -> [OrbState] {
    let radiusScale = orbRadiusScale(for: pageSize, platform: platform)
    return visibleOrbDefinitions(for: platform).map { index, definition in
        OrbState(
            id: index,
            x: definition.fx * pageSize.width,
            y: definition.fy * pageSize.height,
            radius: definition.radius * radiusScale,
            vx: definition.vx,
            vy: definition.vy,
            color: definition.color
        )
    }
}

func hitTestOrb(at point: CGPoint, in orbs: [OrbState]) -> Int? {
    for index in orbs.indices.reversed() {
        let orb = orbs[index]
        let dx = Double(point.x) - orb.x
        let dy = Double(point.y) - orb.y
        if dx * dx + dy * dy <= orb.radius * orb.radius {
            return index
        }
    }
    return nil
}

func stepOrbPhysics(
    _ orbs: inout [OrbState],
    pageSize: CGSize,
    dt: Double,
    topInset: Double,
    bottomInset: Double
) {
    guard !orbs.isEmpty else {
        return
    }

    let cappedDt = min(max(0, dt), 0.05)
    let pageWidth = Double(pageSize.width)
    let pageHeight = Double(pageSize.height)

    for index in orbs.indices {
        if orbs[index].paused || orbs[index].dragging {
            continue
        }

        orbs[index].x += orbs[index].vx * cappedDt
        orbs[index].y += orbs[index].vy * cappedDt

        if orbs[index].x - orbs[index].radius < 0 {
            orbs[index].x = orbs[index].radius
            orbs[index].vx = abs(orbs[index].vx)
        }

        if orbs[index].x + orbs[index].radius > pageWidth {
            orbs[index].x = pageWidth - orbs[index].radius
            orbs[index].vx = -abs(orbs[index].vx)
        }

        if orbs[index].y - orbs[index].radius < topInset {
            orbs[index].y = topInset + orbs[index].radius
            orbs[index].vy = abs(orbs[index].vy)
        }

        if orbs[index].y + orbs[index].radius > pageHeight - bottomInset {
            orbs[index].y = pageHeight - bottomInset - orbs[index].radius
            orbs[index].vy = -abs(orbs[index].vy)
        }
    }

    for leftIndex in orbs.indices {
        for rightIndex in orbs.indices where rightIndex > leftIndex {
            let dx = orbs[rightIndex].x - orbs[leftIndex].x
            let dy = orbs[rightIndex].y - orbs[leftIndex].y
            let distance = sqrt(dx * dx + dy * dy)
            let minimumDistance = orbs[leftIndex].radius + orbs[rightIndex].radius + 20

            if distance >= minimumDistance || distance <= 0.1 {
                continue
            }

            let force = (minimumDistance - distance) * 0.8
            let nx = dx / distance
            let ny = dy / distance

            if !orbs[leftIndex].paused, !orbs[leftIndex].dragging {
                orbs[leftIndex].vx -= nx * force * cappedDt
                orbs[leftIndex].vy -= ny * force * cappedDt
            }

            if !orbs[rightIndex].paused, !orbs[rightIndex].dragging {
                orbs[rightIndex].vx += nx * force * cappedDt
                orbs[rightIndex].vy += ny * force * cappedDt
            }
        }
    }
}
