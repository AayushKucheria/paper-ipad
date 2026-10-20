import Foundation

struct ReviewItem: Codable, Identifiable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case draft, sending, sent, skipped }
    var id = UUID()
    var pages: [Int]
    var quote: String
    var note: String
    var interpretation: String
    var kind: String
    var state: State = .draft
    var remoteID: String?
    var attemptedAt: Date?
    var deliveryQuote: String?
    var deliveryNote: String?
    var canSend: Bool { state == .draft && !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var pageLabel: String { pages.map(String.init).joined(separator: ", ") }
    var readerNote: String {
        [note, interpretation.isEmpty ? "" : "AI interpretation: \(interpretation)", "Paper · PDF pages \(pageLabel)", "Paper item: \(id.uuidString)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
struct ReviewStore {
    let url: URL
    func load() throws -> [ReviewItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ReviewItem].self, from: Data(contentsOf: url))
    }
    func save(_ items: [ReviewItem]) throws {
        try JSONEncoder().encode(items).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
enum ReviewError: LocalizedError, Equatable {
    case invalidResponse, noKey, rateLimited, unavailable, unmatched, ambiguous, noReader, invalidPages
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The analysis was incomplete. Your saved drafts are safe. Try again."
        case .noKey: return "Add your Anthropic API key in AI settings."
        case .rateLimited: return "The service is busy or your account has reached its limit. Wait and try again."
        case .unavailable: return "The request couldn’t be completed. Check your connection and API account. Your drafts are saved."
        case .unmatched: return "Reader couldn’t match this passage. Check the quote against Reader’s text, especially across pages. Nothing was created."
        case .ambiguous: return "Delivery couldn’t be confirmed. Use Check delivery before trying again, to avoid duplicates."
        case .noReader: return "This PDF has no Reader document link. Keep the draft here or export the annotated PDF."
        case .invalidPages: return "Choose between one and six valid PDF pages for this analysis."
        }
    }
}
struct MarkupExtraction {
    struct Envelope: Decodable { let items: [Candidate] }
    struct Candidate: Decodable {
        let pages: [Int]; let quote: String; let note: String; let interpretation: String; let kind: String
    }
    static func decode(_ data: Data, allowedPages: Set<Int>) throws -> [ReviewItem] {
        guard let result = try? JSONDecoder().decode(Envelope.self, from: data), result.items.count <= 100 else { throw ReviewError.invalidResponse }
        return try result.items.map { c in
            guard !c.pages.isEmpty, Set(c.pages).isSubset(of: allowedPages), c.quote.count <= 20000,
                  c.note.count <= 20000, c.interpretation.count <= 20000 else { throw ReviewError.invalidResponse }
            return ReviewItem(pages: Array(Set(c.pages)).sorted(), quote: c.quote, note: c.note, interpretation: c.interpretation, kind: c.kind)
        }
    }
}
