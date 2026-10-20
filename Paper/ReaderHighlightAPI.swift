import Foundation

protocol HighlightServing: Sendable {
    func create(parentID: String, item: ReviewItem) async throws -> String
    func find(parentID: String, item: ReviewItem) async throws -> String?
}
actor ReaderHighlightAPI: HighlightServing {
    let token: String
    let baseURL: URL
    let session: URLSession
    init(token: String, baseURL: URL = URL(string: "https://readwise.io/api/v3/")!, session: URLSession = .shared) {
        self.token = token; self.baseURL = baseURL; self.session = session
    }
    func create(parentID: String, item: ReviewItem) async throws -> String {
        let payload: [String: Any] = ["parent_id":parentID,"content":item.deliveryQuote ?? item.quote,
            "notes":item.deliveryNote ?? item.readerNote,"saved_using":"Paper","tags":["paper-markup"]]
        var request = URLRequest(url: baseURL.appendingPathComponent("save/")); request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let data = try await perform(request, writing: true)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = object["id"] as? String, !id.isEmpty else { throw ReviewError.ambiguous }
        return id
    }
    // Reconcile using a unique local marker in notes, not an undocumented idempotency key.
    func find(parentID: String, item: ReviewItem) async throws -> String? {
        var cursor: String?, seen = Set<String>(), matches: [String] = []
        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("list/"), resolvingAgainstBaseURL: false)!
            var query = [URLQueryItem(name:"category",value:"highlight"),URLQueryItem(name:"limit",value:"100")]
            if let date = item.attemptedAt?.addingTimeInterval(-300) { query.append(URLQueryItem(name:"updatedAfter",value:ISO8601DateFormatter().string(from:date))) }
            if let cursor { query.append(URLQueryItem(name:"pageCursor",value:cursor)) }
            components.queryItems = query
            let data = try await perform(URLRequest(url: components.url!), writing: false)
            guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let results = json["results"] as? [[String:Any]] else { throw ReviewError.invalidResponse }
            for result in results where result["parent_id"] as? String == parentID {
                if let notes = result["notes"] as? String, notes.contains("Paper item: \(item.id.uuidString)"), let id = result["id"] as? String { matches.append(id) }
            }
            cursor = json["nextPageCursor"] as? String
            if let cursor, !seen.insert(cursor).inserted { throw ReviewError.invalidResponse }
            if cursor != nil { try await Task.sleep(nanoseconds: 3_100_000_000) }
        } while cursor != nil
        guard matches.count <= 1 else { throw ReviewError.ambiguous }
        return matches.first
    }
    private func perform(_ initial: URLRequest, writing: Bool) async throws -> Data {
        var request = initial; request.timeoutInterval = 60
        request.setValue("Token \(token)", forHTTPHeaderField:"Authorization")
        request.setValue("application/json", forHTTPHeaderField:"Content-Type")
        do {
            let (data,response) = try await session.data(for:request,delegate:NoCredentialRedirects())
            guard let http = response as? HTTPURLResponse else { throw ReviewError.ambiguous }
            if http.statusCode == 400 { throw ReviewError.unmatched }
            if http.statusCode == 429 { throw ReviewError.rateLimited }
            if [401,403].contains(http.statusCode) { throw ReaderAPIError.authenticationRequired }
            guard (200..<300).contains(http.statusCode) else { throw writing ? ReviewError.ambiguous : ReviewError.unavailable }
            return data
        } catch let e as ReviewError { throw e }
        catch let e as ReaderAPIError { throw e }
        catch { throw writing ? ReviewError.ambiguous : ReviewError.unavailable }
    }
}
