import Foundation
import OSLog

struct ReaderPDF: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var title: String?
    var author: String?
    var summary: String?
    var readerURL: URL?
    var sourceURL: URL?
    var savedAt: String?
    var hasDownload: Bool
    var canDownload: Bool { hasDownload || githubRawURL != nil }

    /// GitHub's public PDF preview has a known raw-file route; other wrappers need explicit support.
    fileprivate var githubRawURL: URL? {
        guard let sourceURL, sourceURL.scheme?.lowercased() == "https",
              sourceURL.host?.lowercased() == "github.com",
              sourceURL.user == nil, sourceURL.password == nil,
              sourceURL.port == nil || sourceURL.port == 443,
              sourceURL.pathExtension.lowercased() == "pdf" else { return nil }
        let parts = sourceURL.path.split(separator: "/")
        guard parts.count >= 5, parts[2] == "blob",
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "raw" } + [URLQueryItem(name: "raw", value: "true")]
        components.fragment = nil
        return components.url
    }

    init(id: String, title: String? = nil, author: String? = nil, summary: String? = nil, readerURL: URL? = nil, sourceURL: URL? = nil, savedAt: String? = nil, hasDownload: Bool = true) {
        self.id = id; self.title = title; self.author = author; self.summary = summary
        self.readerURL = readerURL; self.sourceURL = sourceURL; self.savedAt = savedAt; self.hasDownload = hasDownload
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, author, summary, hasDownload
        case readerURL = "url", sourceURL = "source_url", savedAt = "saved_at", rawSource = "raw_source_url"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        readerURL = try c.decodeIfPresent(URL.self, forKey: .readerURL)
        sourceURL = try c.decodeIfPresent(URL.self, forKey: .sourceURL)
        savedAt = try c.decodeIfPresent(String.self, forKey: .savedAt)
        if c.contains(.rawSource) {
            hasDownload = !(try c.decodeIfPresent(String.self, forKey: .rawSource) ?? "").isEmpty
        } else { hasDownload = try c.decodeIfPresent(Bool.self, forKey: .hasDownload) ?? true }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(title, forKey: .title); try c.encodeIfPresent(author, forKey: .author)
        try c.encodeIfPresent(summary, forKey: .summary); try c.encodeIfPresent(readerURL, forKey: .readerURL)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL); try c.encodeIfPresent(savedAt, forKey: .savedAt)
        try c.encode(hasDownload, forKey: .hasDownload)
    }
}
protocol ReaderServing: Sendable {
    func listPDFs(progress: @escaping @Sendable (Int) -> Void) async throws -> [ReaderPDF]
    func downloadPDF(id: String, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL
}
enum ReaderAPIError: LocalizedError {
    case authenticationRequired, throttled, unavailableSource, insecureSource, malformedResponse, paginationLoop, serverFailure, networkFailure
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "Reader could not authenticate. Check or replace your access token."
        case .throttled: return "Reader is busy. Please wait a minute and try again."
        case .unavailableSource: return "Reader has no downloadable original for this PDF. Open it in Reader to check the source."
        case .insecureSource: return "This PDF source does not provide a secure download. Open it in Reader."
        case .malformedResponse, .paginationLoop: return "Reader returned an incomplete library response. Please try refreshing again."
        case .serverFailure: return "The PDF service could not complete this request. Please try again."
        case .networkFailure: return "Could not connect. Check your internet connection and try again."
        }
    }
}
private struct ReaderRecord: Decodable {
    let pdf: ReaderPDF
    let category: String?
    let parentID: String?
    let rawSource: URL?
    enum CodingKeys: String, CodingKey { case category; case parentID = "parent_id", rawSource = "raw_source_url" }
    init(from decoder: Decoder) throws {
        var decodedPDF = try ReaderPDF(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        let rawString = try c.decodeIfPresent(String.self, forKey: .rawSource)?.trimmingCharacters(in: .whitespacesAndNewlines)
        rawSource = rawString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        decodedPDF.hasDownload = rawSource != nil
        pdf = decodedPDF
    }
}
private struct ReaderPage: Decodable { let results: [ReaderRecord]; let nextPageCursor: String? }

/// Restrict redirects before Foundation can forward a credential or follow an insecure URL.
private final class ReaderTransferDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let authorizedOrigin: URL?
    let progress: @Sendable (Int64, Int64?) -> Void
    init(authorizedOrigin: URL? = nil, progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }) {
        self.authorizedOrigin = authorizedOrigin; self.progress = progress
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ReaderAPI.isSecure(url) else { completionHandler(nil); return }
        if let origin = authorizedOrigin, (url.host != origin.host || url.port != origin.port || url.scheme != origin.scheme) {
            completionHandler(nil); return
        }
        var clean = request
        if authorizedOrigin == nil { clean.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(clean)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite >= 0 ? totalBytesExpectedToWrite : nil)
    }
}
actor ReaderAPI: ReaderServing {
    private let token: String
    private let baseURL: URL
    private let session: URLSession
    private let minimumRequestInterval: TimeInterval
    private var nextRequest = Date.distantPast
    private let logger = Logger(subsystem: "com.aayush.paper.reader", category: "ReaderAPI")
    init(token: String, baseURL: URL = URL(string: "https://readwise.io/api/v3/")!, session: URLSession = .shared, minimumRequestInterval: TimeInterval = 3.1) {
        self.token = token; self.baseURL = baseURL; self.session = session; self.minimumRequestInterval = max(0, minimumRequestInterval)
    }
    nonisolated fileprivate static func isSecure(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return url.host != nil && url.user == nil && url.password == nil }
        #if DEBUG
        return url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
        #else
        return false
        #endif
    }
    func listPDFs(progress: @escaping @Sendable (Int) -> Void) async throws -> [ReaderPDF] {
        let operation = UUID().uuidString, start = Date()
        logger.info("catalog_start operation=\(operation, privacy: .public)")
        var cursor: String?, cursors = Set<String>(), ids = Set<String>(), result: [ReaderPDF] = []
        do {
            repeat {
                var query = [URLQueryItem(name: "category", value: "pdf"), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "withRawSourceUrl", value: "true")]
                if let cursor { query.append(URLQueryItem(name: "pageCursor", value: cursor)) }
                let page = try await fetchPage(query: query)
                for record in page.results where record.category == "pdf" && record.parentID == nil {
                    if ids.insert(record.pdf.id).inserted { result.append(record.pdf) }
                }
                progress(result.count)
                logger.info("catalog_page operation=\(operation, privacy: .public) count=\(result.count) elapsed=\(Date().timeIntervalSince(start))")
                cursor = page.nextPageCursor
                if let cursor, !cursors.insert(cursor).inserted { throw ReaderAPIError.paginationLoop }
            } while cursor != nil
            logger.info("catalog_complete operation=\(operation, privacy: .public) count=\(result.count) elapsed=\(Date().timeIntervalSince(start))")
            return result
        } catch { logger.error("catalog_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(start))"); throw safe(error) }
    }
    func downloadPDF(id: String, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL {
        let operation = UUID().uuidString, start = Date()
        do {
            for attempt in 0...1 {
                logger.info("source_resolution operation=\(operation, privacy: .public)")
                let page = try await fetchPage(query: [URLQueryItem(name: "id", value: id), URLQueryItem(name: "withRawSourceUrl", value: "true")])
                guard let record = page.results.first(where: { $0.pdf.id == id }),
                      let url = record.rawSource ?? record.pdf.githubRawURL else { throw ReaderAPIError.unavailableSource }
                guard Self.isSecure(url) else { throw ReaderAPIError.insecureSource }
                logger.info("download_start operation=\(operation, privacy: .public)")
                let (file, response) = try await transfer(url: url, progress: progress)
                if [401, 403].contains(response.statusCode), attempt == 0 { try? FileManager.default.removeItem(at: file); continue }
                guard (200..<300).contains(response.statusCode) else {
                    try? FileManager.default.removeItem(at: file)
                    throw ReaderAPIError.serverFailure
                }
                logger.info("download_complete operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(start))")
                return file
            }
            throw ReaderAPIError.serverFailure
        } catch { logger.error("download_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(start))"); throw safe(error) }
    }
    private func fetchPage(query: [URLQueryItem]) async throws -> ReaderPage {
        guard Self.isSecure(baseURL), var components = URLComponents(url: baseURL.appendingPathComponent("list/"), resolvingAgainstBaseURL: false) else { throw ReaderAPIError.insecureSource }
        components.queryItems = query
        guard let url = components.url else { throw ReaderAPIError.malformedResponse }
        for attempt in 0...2 {
            try await pace()
            var request = URLRequest(url: url)
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 60
            let (data, response) = try await session.data(for: request, delegate: ReaderTransferDelegate(authorizedOrigin: baseURL))
            guard let response = response as? HTTPURLResponse else { throw ReaderAPIError.malformedResponse }
            if response.statusCode == 429 {
                guard attempt < 2 else { throw ReaderAPIError.throttled }
                try await waitForRetry(response); continue
            }
            if [401, 403].contains(response.statusCode) { throw ReaderAPIError.authenticationRequired }
            guard (200..<300).contains(response.statusCode) else { throw ReaderAPIError.serverFailure }
            do { return try JSONDecoder().decode(ReaderPage.self, from: data) }
            catch { throw ReaderAPIError.malformedResponse }
        }
        throw ReaderAPIError.throttled
    }
    private func transfer(url: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> (URL, HTTPURLResponse) {
        for attempt in 0...2 {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            let (temporary, response) = try await session.download(for: request, delegate: ReaderTransferDelegate(progress: progress))
            guard let response = response as? HTTPURLResponse else { try? FileManager.default.removeItem(at: temporary); throw ReaderAPIError.malformedResponse }
            if response.statusCode == 429 {
                try? FileManager.default.removeItem(at: temporary)
                guard attempt < 2 else { throw ReaderAPIError.throttled }
                try await waitForRetry(response); continue
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: temporary.path)
            let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            progress(bytes, response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
            return (temporary, response)
        }
        throw ReaderAPIError.throttled
    }
    private func pace() async throws {
        let now = Date(), reserved = max(now, nextRequest)
        nextRequest = reserved.addingTimeInterval(minimumRequestInterval)
        try await pause(reserved.timeIntervalSince(now))
    }
    private func waitForRetry(_ response: HTTPURLResponse) async throws {
        let raw = response.value(forHTTPHeaderField: "Retry-After") ?? "3.1"
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        let seconds = max(0, Double(raw) ?? formatter.date(from: raw)?.timeIntervalSinceNow ?? 3.1)
        guard seconds <= 60 else { throw ReaderAPIError.throttled }
        try await pause(seconds)
    }
    private func pause(_ seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    }
    private func safe(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let known = error as? ReaderAPIError { return known }
        if (error as? URLError)?.code == .cancelled { return CancellationError() }
        return ReaderAPIError.networkFailure
    }
}
