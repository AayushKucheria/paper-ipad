import Foundation
import CryptoKit
import PencilKit

struct DirectInkState {
    var drawing = PKDrawing()
    var offset: CGFloat = 0
}

struct DirectInkStore {
    private struct LegacyState: Decodable {
        struct Stroke: Decodable {
            let points: [CGPoint]
        }

        let strokes: [Stroke]
        let offset: CGFloat

        var converted: DirectInkState {
            let blue = UIColor(red: 0.12, green: 0.29, blue: 0.55, alpha: 1)
            let ink = PKInk(.pen, color: blue)
            let strokes = strokes.compactMap { stroke -> PKStroke? in
                guard let first = stroke.points.first else { return nil }
                let locations = stroke.points.count == 1
                    ? [first, CGPoint(x: first.x + 0.1, y: first.y)]
                    : stroke.points
                let points = locations.enumerated().map { index, location in
                    PKStrokePoint(location: location, timeOffset: Double(index) / 120,
                                  size: CGSize(width: 2.4, height: 2.4), opacity: 1,
                                  force: 1, azimuth: 0, altitude: .pi / 2)
                }
                return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: .now))
            }
            return DirectInkState(drawing: PKDrawing(strokes: strokes), offset: offset)
        }
    }

    private struct SavedDrawing: Codable {
        let drawing: Data
        let offset: CGFloat
    }

    let directory: URL

    init(directory: URL) { self.directory = directory }

    init(document: StoredDocument, store: DocumentStore) {
        self.init(directory: store.reviewURL(for: document).deletingLastPathComponent())
    }

    private func key(for section: String) -> String {
        SHA256.hash(data: Data(section.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func pencilURL(for key: String) -> URL {
        directory.appendingPathComponent("pencil-ink-\(key).json")
    }

    private func readDrawing(at url: URL) throws -> DirectInkState {
        let saved = try JSONDecoder().decode(SavedDrawing.self, from: Data(contentsOf: url))
        return DirectInkState(drawing: try PKDrawing(data: saved.drawing), offset: saved.offset)
    }

    func load(section: String) throws -> DirectInkState {
        let key = key(for: section)
        let current = pencilURL(for: key)
        let files = FileManager.default
        if files.fileExists(atPath: current.path) { return try readDrawing(at: current) }
        let legacy = directory.appendingPathComponent("direct-ink-\(key).json")
        guard files.fileExists(atPath: legacy.path) else { return DirectInkState() }
        let state = try JSONDecoder().decode(LegacyState.self, from: Data(contentsOf: legacy)).converted
        // The original file remains recoverable even if all migrated ink is erased.
        try save(state, section: section)
        return state
    }

    func save(_ state: DirectInkState, section: String) throws {
        let saved = SavedDrawing(drawing: state.drawing.dataRepresentation(), offset: state.offset)
        try JSONEncoder().encode(saved).write(to: pencilURL(for: key(for: section)), options: .atomic)
    }

    var hasInk: Bool {
        let files = FileManager.default
        let urls = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.contains { url in
            guard url.pathExtension == "json" else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix("pencil-ink-") {
                return (try? readDrawing(at: url).drawing.strokes.isEmpty) == false
            }
            guard name.hasPrefix("direct-ink-"),
                  !files.fileExists(atPath: pencilURL(for: String(name.dropFirst("direct-ink-".count))).path),
                  let data = try? Data(contentsOf: url),
                  let legacy = try? JSONDecoder().decode(LegacyState.self, from: data) else { return false }
            return legacy.strokes.contains { !$0.points.isEmpty }
        }
    }
}
