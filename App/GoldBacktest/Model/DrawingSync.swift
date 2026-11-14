import Foundation
import SwiftUI

/// Drawings shared between the app and the website through the VPS: one list per market (XAUUSDm and XAUUSD
/// are one), in the website's format; the copy saved last wins. Only for charts fed by the VPS (MT5).
@MainActor
final class DrawingSync {
    /// The website's fields of each drawing (fills, Fibonacci levels, extensions…), kept so that a drawing
    /// changed in the app goes back with them; by the app's id.
    private var webFields: [UUID: [String: Any]] = [:]
    private var webIDs: [UUID: String] = [:]
    /// The list last taken from or sent to the VPS, per chart key: a change equal to it is not sent back.
    private var lastSynced: [String: [Drawing]] = [:]
    private var pushTask: Task<Void, Never>?

    private func updatedKey(_ symbol: String) -> String { "drawSync.updated." + Self.base(symbol) }
    private func localUpdated(_ symbol: String) -> Double { UserDefaults.standard.double(forKey: updatedKey(symbol)) }
    private func setLocalUpdated(_ symbol: String, _ value: Double) { UserDefaults.standard.set(value, forKey: updatedKey(symbol)) }

    /// XAUUSDm, XAUUSD.r, #XAUUSD → XAUUSD.
    static func base(_ symbol: String) -> String {
        var rest = Substring(symbol)
        if let first = rest.first, first == "#" || first == "." { rest = rest.dropFirst() }
        let base = String(rest.prefix(while: { $0.isUppercase || $0.isNumber }))
        return base.isEmpty ? symbol : base
    }

    /// Takes the VPS copy when it is newer than this app's; sends this app's when the VPS has none yet.
    func pull(symbol: String, key: String, store: AppStore) async {
        guard let client = RemoteBotSettings.client(), let shared = try? await client.sharedDrawings(symbol: symbol) else { return }
        if shared.updated > localUpdated(symbol) + 0.001 {
            let list = shared.items.compactMap { item -> Drawing? in
                guard let converted = Drawing.fromWeb(item) else { return nil }
                let (drawing, webID) = converted
                webFields[drawing.id] = item
                webIDs[drawing.id] = webID
                return drawing
            }
            setLocalUpdated(symbol, shared.updated)
            lastSynced[key] = list
            store.replaceDrawings(list, key: key)
        } else if shared.updated == 0, !store.drawings(for: key).isEmpty {
            push(symbol: symbol, key: key, drawings: store.drawings(for: key), now: true)
        }
    }

    /// Sends the chart's drawings a moment after the last change (not the copy just taken from the VPS).
    func push(symbol: String, key: String, drawings: [Drawing], now: Bool = false) {
        guard lastSynced[key] != drawings else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if !now { try? await Task.sleep(nanoseconds: 1_200_000_000) }
            guard let self, !Task.isCancelled, let client = RemoteBotSettings.client() else { return }
            let items = drawings.map { $0.webDict(base: self.webFields[$0.id], webID: self.webIDs[$0.id] ?? $0.id.uuidString) }
            let updated = Date().timeIntervalSince1970
            self.setLocalUpdated(symbol, updated)
            self.lastSynced[key] = drawings
            _ = try? await client.saveSharedDrawings(symbol: symbol, updated: updated, items: items)
        }
    }
}

extension Drawing {
    /// A drawing of the website (its id too, which may not be a UUID there); nil for a tool the app lacks.
    static func fromWeb(_ d: [String: Any]) -> (Drawing, String)? {
        guard let name = d["tool"] as? String, let tool = DrawingTool(rawValue: name), let pts = d["pts"] as? [[String: Any]] else { return nil }
        var points = pts.compactMap { p -> ChartPoint? in
            guard let t = (p["t"] as? NSNumber)?.doubleValue, let price = (p["p"] as? NSNumber)?.doubleValue else { return nil }
            return ChartPoint(time: Date(timeIntervalSince1970: t), price: price)
        }
        guard !points.isEmpty else { return nil }
        var rr = (d["rr"] as? NSNumber)?.doubleValue ?? 2
        // Positions: the website keeps entry, stop and target; the app entry and stop, the target by R:R.
        if tool == .longPosition || tool == .shortPosition, points.count >= 3 {
            let risk = abs(points[1].price - points[0].price)
            if risk > 0 { rr = abs(points[2].price - points[0].price) / risk }
            points = Array(points.prefix(2))
        }
        let webID = (d["id"] as? String) ?? UUID().uuidString
        var drawing = Drawing(tool: tool, points: points)
        drawing.id = UUID(uuidString: webID) ?? Self.stableID(webID)
        drawing.text = (d["text"] as? String) ?? ""
        if let hex = d["color"] as? String, let color = RGBAColor(hex: hex) { drawing.customColor = color }
        if let width = (d["width"] as? NSNumber)?.doubleValue { drawing.lineWidth = width }
        drawing.lineStyle = LineStyle(rawValue: (d["style"] as? String) ?? "") ?? .solid
        drawing.locked = (d["locked"] as? Bool) ?? false
        drawing.riskReward = rr
        return (drawing, webID)
    }

    /// The drawing in the website's format, over its website fields (`base`) when it came from there.
    func webDict(base: [String: Any]?, webID: String) -> [String: Any] {
        var d = base ?? [:]
        let hex = RGBAColor(color).hex
        d["id"] = webID
        d["tool"] = tool.rawValue
        var pts: [[String: Any]] = points.map { ["t": $0.time.timeIntervalSince1970, "p": $0.price] }
        if let levels = positionLevels, points.count >= 2 {
            pts.append(["t": points[1].time.timeIntervalSince1970, "p": levels.target])
        }
        d["pts"] = pts
        d["color"] = hex
        if base == nil {
            d["fillColor"] = hex
            d["textColor"] = hex
        }
        d["width"] = lineWidth
        d["style"] = lineStyle.rawValue
        d["text"] = text
        d["locked"] = locked
        d["rr"] = riskReward
        return d
    }

    /// The same UUID every time for a website id that is not one (FNV-1a over its bytes, twice).
    static func stableID(_ text: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h: UInt64 = seed
            for byte in text.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
            return h
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8((a >> (8 * UInt64(i))) & 0xff); bytes[8 + i] = UInt8((b >> (8 * UInt64(i))) & 0xff) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

extension RGBAColor {
    /// "#rrggbb" or "#rrggbbaa".
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let full = text.count == 6 ? (value << 8) | 0xff : value
        self.init(red: Double((full >> 24) & 0xff) / 255, green: Double((full >> 16) & 0xff) / 255,
                  blue: Double((full >> 8) & 0xff) / 255, alpha: Double(full & 0xff) / 255)
    }

    /// "#rrggbb" (with "aa" when not opaque).
    var hex: String {
        func byte(_ v: Double) -> String { String(format: "%02x", Int((max(0, min(1, v)) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 0.999 ? byte(alpha) : "")
    }
}
