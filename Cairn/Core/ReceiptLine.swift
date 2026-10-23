import Foundation

/// One friendly sentence under a receipt's number that turns bytes into
/// something real. Each size has a few lines; the receipt's own date picks
/// one, so a receipt always reads the same but receipts don't all match.
/// The comparisons are rounded on purpose: a phone photo is about 3 MB,
/// a song about 8 MB, a minute of iPhone 4K video about 350 MB, an HD film about 4 GB.
enum ReceiptLine {
    static func text(freed bytes: Int64, seed: Date) -> String? {
        guard bytes > 0 else { return nil }
        let mb = Double(bytes) / 1_000_000
        let gb = mb / 1000
        let lines: [String]
        switch gb {
        case ..<0.1:
            lines = ["Small, but every bit counts.",
                     "Room for about \(count(mb / 3)) more photos.",
                     "That's about \(count(mb / 8)) songs' worth of space."]
        case ..<2:
            lines = ["Room for about \(count(mb / 3)) more photos.",
                     "That's about \(count(mb / 8)) songs' worth of space.",
                     "Enough for about \(count(mb / 350, unit: "minute")) of 4K video."]
        case ..<12:
            lines = ["That's about \(count(gb / 4, unit: "film")) worth of space back.",
                     "Room for about \(count(mb / 3)) more photos.",
                     "Enough for about \(count(mb / 350, unit: "minute")) of 4K video."]
        case ..<30:
            lines = ["That's about \(count(gb / 4, unit: "film")) worth of space back.",
                     "Room for a macOS update, with plenty to spare.",
                     "Room for about \(count(mb / 3)) more photos."]
        default:
            lines = ["That's about \(count(gb / 4, unit: "film")) worth of space back.",
                     "Room for about \(count(gb * 1000 / 350 / 60, unit: "hour")) of 4K video.",
                     "That's a whole extra game's worth of room, or more."]
        }
        let pick = Int(seed.timeIntervalSinceReferenceDate.rounded()) % lines.count
        return lines[abs(pick)]
    }

    /// "four films'", "120", "2,400": words under ten, round numbers above.
    private static func count(_ value: Double, unit: String? = nil) -> String {
        let n = max(1, Int(value.rounded()))
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        let number: String
        if n < 10 { number = words[n - 1] }
        else {
            let step = n < 100 ? 10 : n < 1000 ? 50 : 100
            number = ((n + step / 2) / step * step).formatted(.number)
        }
        guard let unit else { return number }
        if unit == "film" { return "\(number) \(n == 1 ? "film's" : "films'")" }
        return "\(number) \(unit)\(n == 1 ? "" : "s")"
    }
}
