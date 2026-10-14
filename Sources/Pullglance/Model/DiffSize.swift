import Foundation

/// "+24 −44" for the row; nil when the size is unknown. Long numbers abbreviate so the line stays a line.
func diffSizeText(additions: Int?, deletions: Int?) -> String? {
    guard let additions else { return nil }
    return "+\(abbreviated(additions)) \u{2212}\(abbreviated(deletions ?? 0))"
}

/// 999, 1k, 1.2k, 12k, 1.2m: one decimal below ten of a unit, none above.
func abbreviated(_ n: Int) -> String {
    func scaled(_ value: Double, _ unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded >= 10 { return "\(Int(rounded.rounded()))\(unit)" }
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return text + unit
    }
    if n >= 1_000_000 { return scaled(Double(n) / 1_000_000, "m") }
    if n >= 1_000 { return scaled(Double(n) / 1_000, "k") }
    return String(n)
}
