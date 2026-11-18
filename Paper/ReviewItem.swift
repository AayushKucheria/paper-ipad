import Foundation
import OSLog

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
    var alternatives: [ReviewAlternative]?
    var directInk: Bool?
    var canSend: Bool { state == .draft && !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var pageLabel: String { pages.map(String.init).joined(separator: ", ") }
    var locationLabel: String { directInk == true ? "Marked region" : "Pages \(pageLabel)" }
    var readerNote: String {
        [note, interpretation.isEmpty ? "" : "AI interpretation: \(interpretation)", "Paper · \(locationLabel)", "Paper item: \(id.uuidString)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
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
        case .noReader: return "This document has no Reader link. You can keep the draft on this iPad."
        case .invalidPages: return "Choose between one and six marked pages or regions for this analysis."
        }
    }
}
struct MarkupExtraction {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Paper", category: "analysis-decode")
    struct Envelope: Decodable { let items: [Candidate] }
    struct Candidate: Decodable {
        let pages: [Int]; let quote: String; let note: String; let interpretation: String; let kind: String
    }
    static func decode(_ data: Data, allowedPages: Set<Int>) throws -> [ReviewItem] {
        guard let result = try? JSONDecoder().decode(Envelope.self, from: data) else { log.error("decode_failure reason=schema_mismatch"); throw ReviewError.invalidResponse }
        guard result.items.count <= 100 else { log.error("decode_failure reason=too_many_items"); throw ReviewError.invalidResponse }
        return try result.items.map { c in
            guard !c.pages.isEmpty else { log.error("decode_failure reason=empty_pages"); throw ReviewError.invalidResponse }
            guard Set(c.pages).isSubset(of: allowedPages) else { log.error("decode_failure reason=pages_not_supplied"); throw ReviewError.invalidResponse }
            guard c.quote.count <= 20000, c.note.count <= 20000, c.interpretation.count <= 20000 else { log.error("decode_failure reason=field_too_long"); throw ReviewError.invalidResponse }
            return ReviewItem(pages: Array(Set(c.pages)).sorted(), quote: c.quote, note: c.note, interpretation: c.interpretation, kind: c.kind)
        }
    }
}


struct AnalysisUsage: Codable, Equatable, Sendable {
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let pages: [Int]
    let date: Date
    var pricingVersion: String? = "2026-10-22"
    var estimatedDollars: Double? {
        guard pricingVersion == "2026-10-22", cacheReadTokens == 0, cacheWriteTokens == 0, inputTokens <= 100_000 else { return nil }
        if model.hasPrefix("claude-haiku-5-5") { return Double(inputTokens) * 0.10 / 1_000_000 + Double(outputTokens) * 0.50 / 1_000_000 }
        if model.hasPrefix("claude-sonnet-5-5") { return Double(inputTokens) * 2 / 1_000_000 + Double(outputTokens) * 10 / 1_000_000 }
        return nil
    }
    var summary: String {
        let price = estimatedDollars.map { String(format: " · estimated $%.4f", $0) } ?? " · see provider bill for cost"
        return "\(model.contains("haiku") ? "Haiku" : "Sonnet") · \(inputTokens) input / \(outputTokens) output tokens" + price
    }
}
struct ReviewAnalysisHistory: Codable {
    var fingerprints: [Int:String] = [:]
    var usage: [AnalysisUsage] = []
}

struct ReviewAlternative: Codable, Equatable, Sendable {
    let note: String
    let interpretation: String
    let date: Date
}

enum SourceQuoteError: LocalizedError, Equatable {
    case sourceUnavailable, missing, repeated
    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return "There’s no searchable source text to verify this quote. Your draft is saved on this iPad."
        case .missing:
            return "This quote doesn’t match the original text. Copy the exact passage or keep your draft here."
        case .repeated:
            return "This quote appears more than once. Add nearby words to identify the right passage."
        }
    }
}

enum SourceQuote {
    static func exactMatch(_ quote: String, in source: String) throws -> String {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceQuoteError.sourceUnavailable
        }
        let words = quote.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, let last = words.last else { throw SourceQuoteError.missing }
        let wordCharacter = #"[\p{L}\p{M}\p{N}_]"#
        func isWordCharacter(_ character: Character?) -> Bool {
            guard let character else { return false }
            return String(character).range(of: wordCharacter, options: .regularExpression) != nil
        }
        func isPunctuation(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
        }

        var pattern = isWordCharacter(first.first) ? "(?<!\(wordCharacter))" : ""
        pattern += NSRegularExpression.escapedPattern(for: first)
        for index in words.indices.dropFirst() {
            let layoutBoundary = isPunctuation(words[index - 1].last) || isPunctuation(words[index].first)
            pattern += layoutBoundary ? #"\s*"# : #"\s+"#
            pattern += NSRegularExpression.escapedPattern(for: words[index])
        }
        if isWordCharacter(last.last) { pattern += "(?!\(wordCharacter))" }

        // A zero-width match also counts overlapping occurrences, e.g. "a a" in "a a a".
        let regex = try NSRegularExpression(pattern: "(?=(\(pattern)))")
        var match: NSRange?
        var repeated = false
        regex.enumerateMatches(in: source, range: NSRange(source.startIndex..., in: source)) { result, _, stop in
            guard let result else { return }
            if match != nil { repeated = true; stop.pointee = true }
            else { match = result.range(at: 1) }
        }
        guard !repeated else { throw SourceQuoteError.repeated }
        guard let match, let range = Range(match, in: source) else { throw SourceQuoteError.missing }
        return String(source[range])
    }
}
