import SwiftUI

struct PixelFace: View {
    var mood: FaceMood
    var speaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let clock = timeline.date.timeIntervalSinceReferenceDate
                let blink = !reduceMotion && clock.truncatingRemainder(dividingBy: 5.3) > 5.08
                let mouth = speaking && !reduceMotion ? Int(clock * 7) % 3 : 0
                let unit = min(size.width / 80, size.height / 43)
                func pixel(_ x: Int, _ y: Int, _ color: Color = .companionCyan) {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit * 0.94, height: unit * 0.94)), with: .color(color))
                }
                func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: Color = .companionCyan) {
                    guard width > 0, height > 0 else { return }; for a in x..<(x + width) { for b in y..<(y + height) { pixel(a, b, color) } }
                }
                func polygon(_ points: [(Int, Int)]) {
                    guard let minX = points.map(\.0).min(), let maxX = points.map(\.0).max(), let minY = points.map(\.1).min(), let maxY = points.map(\.1).max() else { return }
                    for x in minX...maxX { for y in minY...maxY {
                        var inside = false; var previous = points.count - 1
                        for index in points.indices {
                            let a = points[index], b = points[previous]
                            let px = Double(x) + 0.5, py = Double(y) + 0.5
                            if (Double(a.1) > py) != (Double(b.1) > py), px < Double(b.0-a.0) * (py-Double(a.1)) / Double(b.1-a.1) + Double(a.0) { inside.toggle() }
                            previous = index
                        }
                        if inside { pixel(x, y) }
                    } }
                }
                for (index, x) in [23, 51].enumerated() {
                    if blink || mood == .sleeping { rect(x - 2, 24, 12, 2); continue }
                    switch mood {
                    case .happy:
                        polygon([(x-2,24),(x-2,21),(x,21),(x,19),(x+2,19),(x+2,17),(x+6,17),(x+6,19),(x+8,19),(x+8,21),(x+10,21),(x+10,24),(x+8,24),(x+8,22),(x+6,22),(x+6,20),(x+2,20),(x+2,22),(x,22),(x,24)])
                    case .laughing, .playful where index == 1:
                        let points = [(0,0),(3,0),(3,2),(6,2),(6,4),(9,4),(9,7),(6,7),(6,9),(3,9),(3,11),(0,11),(0,8),(3,8),(3,7),(5,7),(5,4),(3,4),(3,3),(0,3)]
                        polygon(points.map { (x - 1 + (index == 1 ? 9 - $0.0 : $0.0), 16 + $0.1) })
                    case .affectionate:
                        polygon([(x-2,17),(x,17),(x,15),(x+3,15),(x+3,17),(x+5,17),(x+5,15),(x+8,15),(x+8,17),(x+10,17),(x+10,22),(x+8,22),(x+8,24),(x+6,24),(x+6,26),(x+4,28),(x+2,26),(x+2,24),(x,24),(x,22),(x-2,22)])
                    case .surprised: rect(x-1,16,10,2); rect(x-3,18,2,8); rect(x+9,18,2,8); rect(x-1,26,10,2)
                    case .sleepy: rect(x-2,22,12,2); rect(x,24,8,2); rect(x+1,26,6,1)
                    case .sad:
                        polygon(index == 0 ? [(x-2,23),(x+8,17),(x+8,24),(x+5,24),(x+5,27),(x+1,27),(x+1,25),(x-2,25)] : [(x-1,17),(x+9,23),(x+9,25),(x+6,25),(x+6,27),(x+2,27),(x+2,24),(x-1,24)])
                    default:
                        let y = mood == .curious && index == 0 ? 12 : 16
                        let height = mood == .curious && index == 0 ? 18 : 14
                        rect(x+2,y,4,1); rect(x+1,y+1,6,1); rect(x,y+2,8,height-4); rect(x+1,y+height-2,6,1); rect(x+2,y+height-1,4,1)
                    }
                }
                if mood == .shy { rect(19,29,2,2,.pink); rect(22,30,2,2,.pink); rect(61,29,2,2,.pink); rect(58,30,2,2,.pink) }
                if mouth == 2 || mood == .laughing { rect(36,29,9,4); rect(37,33,7,2); rect(38,35,5,1) }
                else if mouth == 1 || mood == .surprised { rect(38,29,4,1); rect(37,30,2,5); rect(41,30,2,5); rect(38,35,4,1) }
                else if mood == .sad { rect(37,32,6,2); rect(36,34,2,1); rect(42,34,2,1) }
                else if mood == .sleeping || mood == .listening || mood == .sleepy {
                    rect(39,32,3,1); if mood == .listening { for index in 0..<3 { rect(63+index*4,32,2,2) } }
                } else { rect(36,30,2,2); rect(43,30,2,2); rect(38,32,5,2) }
            }
        }
        .aspectRatio(320.0 / 172, contentMode: .fit)
        .shadow(color: .companionCyan.opacity(0.3), radius: 7)
        .accessibilityLabel("\(mood.title) face\(speaking ? ", speaking" : "")")
    }
}

extension Color {
    static let companionBackground = Color(red: 0.055, green: 0.075, blue: 0.085)
    static let companionSurface = Color(red: 0.10, green: 0.13, blue: 0.14)
    static let companionCyan = Color(red: 0.40, green: 0.94, blue: 0.96)
    static let companionMint = Color(red: 0.72, green: 0.85, blue: 0.75)
}
