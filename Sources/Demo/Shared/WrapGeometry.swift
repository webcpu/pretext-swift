import Foundation

struct WrapRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
}

struct WrapInterval: Equatable {
    var left: Double
    var right: Double
}

struct WrapPoint: Equatable {
    var x: Double
    var y: Double
}

enum WrapHullMode: Equatable {
    case mean
    case envelope
}

func transformWrapPoints(_ points: [WrapPoint], rect: WrapRect, angle: Double) -> [WrapPoint] {
    guard angle != 0 else {
        return points.map { point in
            WrapPoint(
                x: rect.x + point.x * rect.width,
                y: rect.y + point.y * rect.height
            )
        }
    }

    let centerX = rect.midX
    let centerY = rect.midY
    let cosine = cos(angle)
    let sine = sin(angle)

    return points.map { point in
        let localX = (point.x - 0.5) * rect.width
        let localY = (point.y - 0.5) * rect.height
        return WrapPoint(
            x: centerX + localX * cosine - localY * sine,
            y: centerY + localX * sine + localY * cosine
        )
    }
}

func isPointInPolygon(_ points: [WrapPoint], x: Double, y: Double) -> Bool {
    guard points.count >= 3 else {
        return false
    }

    var inside = false
    var previous = points.count - 1
    for index in points.indices {
        let a = points[index]
        let b = points[previous]
        let intersects =
            ((a.y > y) != (b.y > y)) &&
            (x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x)
        if intersects {
            inside.toggle()
        }
        previous = index
    }
    return inside
}

func getPolygonIntervalForBand(
    points: [WrapPoint],
    bandTop: Double,
    bandBottom: Double,
    hPad: Double,
    vPad: Double
) -> WrapInterval? {
    let sampleTop = bandTop - vPad
    let sampleBottom = bandBottom + vPad
    let startY = Int(floor(sampleTop))
    let endY = Int(ceil(sampleBottom))

    var left = Double.infinity
    var right = -Double.infinity

    for y in startY...endY {
        let xs = getPolygonXsAtY(points: points, y: Double(y) + 0.5)
        var index = 0
        while index + 1 < xs.count {
            let runLeft = xs[index]
            let runRight = xs[index + 1]
            left = min(left, runLeft)
            right = max(right, runRight)
            index += 2
        }
    }

    guard left.isFinite, right.isFinite else {
        return nil
    }

    return WrapInterval(left: left - hPad, right: right + hPad)
}

func getRectIntervalsForBand(
    rects: [WrapRect],
    bandTop: Double,
    bandBottom: Double,
    hPad: Double,
    vPad: Double
) -> [WrapInterval] {
    var intervals: [WrapInterval] = []
    for rect in rects {
        if bandBottom <= rect.y - vPad || bandTop >= rect.y + rect.height + vPad {
            continue
        }
        intervals.append(
            WrapInterval(
                left: rect.x - hPad,
                right: rect.x + rect.width + hPad
            )
        )
    }
    return intervals
}

func circleIntervalForBand(
    cx: Double,
    cy: Double,
    r: Double,
    bandTop: Double,
    bandBottom: Double,
    hPad: Double,
    vPad: Double
) -> WrapInterval? {
    let top = bandTop - vPad
    let bottom = bandBottom + vPad

    if top >= cy + r || bottom <= cy - r {
        return nil
    }

    let minDy: Double
    if cy >= top, cy <= bottom {
        minDy = 0
    } else if cy < top {
        minDy = top - cy
    } else {
        minDy = cy - bottom
    }

    if minDy >= r {
        return nil
    }

    let maxDx = sqrt(r * r - minDy * minDy)
    return WrapInterval(left: cx - maxDx - hPad, right: cx + maxDx + hPad)
}

func carveTextLineSlots(
    base: WrapInterval,
    blocked: [WrapInterval],
    minimumWidth: Double = 24
) -> [WrapInterval] {
    var slots = [base]

    for interval in blocked {
        var next: [WrapInterval] = []
        for slot in slots {
            if interval.right <= slot.left || interval.left >= slot.right {
                next.append(slot)
                continue
            }
            if interval.left > slot.left {
                next.append(WrapInterval(left: slot.left, right: interval.left))
            }
            if interval.right < slot.right {
                next.append(WrapInterval(left: interval.right, right: slot.right))
            }
        }
        slots = next
    }

    return slots.filter { $0.right - $0.left >= minimumWidth }
}

func makeConvexHull(_ points: [WrapPoint]) -> [WrapPoint] {
    guard points.count > 3 else {
        return points
    }

    let sorted = points.sorted {
        if $0.x == $1.x {
            return $0.y < $1.y
        }
        return $0.x < $1.x
    }

    var lower: [WrapPoint] = []
    for point in sorted {
        while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
            lower.removeLast()
        }
        lower.append(point)
    }

    var upper: [WrapPoint] = []
    for point in sorted.reversed() {
        while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
            upper.removeLast()
        }
        upper.append(point)
    }

    lower.removeLast()
    upper.removeLast()
    return lower + upper
}

private func getPolygonXsAtY(points: [WrapPoint], y: Double) -> [Double] {
    guard var a = points.last else {
        return []
    }

    var xs: [Double] = []
    for b in points {
        if (a.y <= y && y < b.y) || (b.y <= y && y < a.y) {
            xs.append(a.x + ((y - a.y) * (b.x - a.x)) / (b.y - a.y))
        }
        a = b
    }
    return xs.sorted()
}

private func cross(_ origin: WrapPoint, _ a: WrapPoint, _ b: WrapPoint) -> Double {
    (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
}
