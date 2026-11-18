import Foundation
import WebKit

@MainActor
final class DirectArticlePreparation: NSObject, WKNavigationDelegate {
    struct Snapshot {
        let html: String
        let text: String
        let missingFigures: Int
    }

    private var navigation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private static let maximumSourceBytes = 16 * 1024 * 1024

    func prepare(html: String, title: String, baseURL: URL?, phase: (String) -> Void) async throws -> Snapshot {
        guard html.utf8.count <= Self.maximumSourceBytes else { throw ArticleRenderError.failed }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 650, height: 900), configuration: configuration)
        web.navigationDelegate = self
        defer { timeout?.cancel(); web.navigationDelegate = nil; web.stopLoading() }
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.finish(.failure(ArticleRenderError.timedOut))
            }
            web.loadHTMLString(Self.shell + "</body></html>", baseURL: nil)
        }
        try Task.checkCancellation()

        let parsed = try await runJavaScript(in: web, body: #"""
            const page = new DOMParser().parseFromString(source, 'text/html');
            page.querySelectorAll('script,style,link,meta,base,iframe,object,embed,form,button,input,textarea,video,audio,source').forEach(node => node.remove());
            page.querySelectorAll('*').forEach(node => {
                for (const attr of Array.from(node.attributes)) {
                    if (/^(on|style$|srcset$|ping$|contenteditable$|tabindex$)/i.test(attr.name)) node.removeAttribute(attr.name);
                }
                if (node.hasAttribute('href') && !/^(?:#|https:)/i.test(node.getAttribute('href'))) node.removeAttribute('href');
            });
            const main = document.createElement('main');
            main.id = 'paper-content';
            main.append(...page.body.childNodes);
            document.body.replaceChildren(main);
            const text = main.innerText.trim();
            const urls = Array.from(main.querySelectorAll('img')).map(img => {
                const original = img.getAttribute('src') || img.getAttribute('data-src') || '';
                img.removeAttribute('src'); img.removeAttribute('data-src');
                try {
                    const resource = base ? new URL(original, base) : new URL(original);
                    return original && (resource.protocol === 'https:' || resource.protocol === 'data:') ? resource.href : '';
                } catch { return ''; }
            });
            return { text, urls };
            """#, arguments: ["source": html, "base": baseURL?.absoluteString ?? ""])
        guard let result = parsed as? [String: Any], let text = result["text"] as? String, !text.isEmpty,
              let urls = result["urls"] as? [String] else { throw ArticleRenderError.emptyContent }

        phase(urls.isEmpty ? "Saving article" : "Saving article and figures for offline reading")
        let embedded = await Self.cacheImages(urls)
        try Task.checkCancellation()
        let serialized = try await runJavaScript(in: web, body: """
            const main = document.getElementById('paper-content');
            let missing = 0;
            Array.from(main.querySelectorAll('img')).forEach((img, index) => {
                const source = images[index];
                if (source) {
                    img.setAttribute('src', source);
                    img.removeAttribute('loading');
                } else {
                    const missingFigure = document.createElement('div');
                    missingFigure.className = 'paper-missing-figure';
                    missingFigure.textContent = img.alt ? 'Figure unavailable · ' + img.alt : 'Figure unavailable';
                    img.replaceWith(missingFigure);
                    missing++;
                }
            });
            if (!main.querySelector('h1') && title) {
                const heading = document.createElement('h1');
                heading.textContent = title;
                main.prepend(heading);
            }
            return { html: main.outerHTML, missing };
            """, arguments: ["images": embedded, "title": title])
        guard let result = serialized as? [String: Any], let body = result["html"] as? String,
              let missing = result["missing"] as? Int else { throw ArticleRenderError.failed }
        return Snapshot(html: Self.shell + body + "</body></html>", text: text, missingFigures: missing)
    }

    private static let shell = """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'">
        <style>.paper-missing-figure{border:1px dashed #8f928a;padding:1rem;margin:1rem 0;color:#50574e}</style></head><body>
        """

    private nonisolated static func cacheImages(_ urls: [String]) async -> [String] {
        guard !urls.isEmpty else { return [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: HTTPSImageRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var embedded = Array(repeating: "", count: urls.count)
        let supported = ["image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml", "image/avif", "image/heic"]
        let imageLimit = 16
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, original) in urls.prefix(imageLimit).enumerated() {
                group.addTask {
                    guard let url = URL(string: original) else { return (index, "") }
                    if original.hasPrefix("data:") {
                        let prefix = original.split(separator: ";", maxSplits: 1).first.map(String.init)
                        guard original.utf8.count <= 2_800_000, let prefix, supported.contains(String(prefix.dropFirst(5))) else { return (index, "") }
                        return (index, original)
                    }
                    guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return (index, "") }
                    do {
                        let (file, response) = try await session.download(from: url)
                        defer { try? FileManager.default.removeItem(at: file) }
                        let media = response.mimeType ?? ""
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                              supported.contains(media),
                              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, (1...2_000_000).contains(size) else { return (index, "") }
                        let data = try Data(contentsOf: file)
                        return (index, "data:\(media);base64,\(data.base64EncodedString())")
                    } catch { return (index, "") }
                }
            }
            for await (index, data) in group { embedded[index] = data }
        }
        return embedded
    }

    private func runJavaScript(in web: WKWebView, body: String, arguments: [String: Any]) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let navigation else { return }
        self.navigation = nil
        timeout?.cancel()
        navigation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
}

private final class HTTPSImageRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, url.scheme == "https", url.user == nil, url.password == nil { completionHandler(request) }
        else { completionHandler(nil) }
    }
}
