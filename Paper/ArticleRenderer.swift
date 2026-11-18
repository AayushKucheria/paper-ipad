import Foundation
import WebKit
import UIKit
import PDFKit
import OSLog

struct RenderedArticle {
    let pdf: Data
    let text: String
    var missingFigureCount: Int = 0
}
enum ArticleRenderError: LocalizedError, Equatable {
    case emptyContent, failed, timedOut, missingImages
    var errorDescription: String? {
        switch self {
        case .emptyContent: return "Reader has no article text to prepare. Open it in Reader and try again."
        case .failed: return "This article couldn’t be laid out for handwriting. Your saved documents are safe."
        case .missingImages: return "Some article figures couldn’t be loaded. Try preparing it again, or open the original in Reader."
        case .timedOut: return "Preparing this article took too long. Please try again."
        }
    }
}

/// WebKit supplies native HTML, image and MathML layout. Print pagination keeps ink geometry stable.
/// Article scripts, frames and network connections are blocked; external images never receive Reader credentials.
@MainActor final class ArticleRenderer: NSObject, WKNavigationDelegate {
    private var navigation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.aayush.paper.reader", category: "ArticleRenderer")

    func render(html: String, title: String, baseURL: URL?) async throws -> RenderedArticle {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ArticleRenderError.emptyContent }
        guard html.utf8.count < 20_000_000 else { throw ArticleRenderError.failed }
        let operation = UUID().uuidString, started = Date()
        var phase = "navigation", completed = false
        defer {
            if !completed { logger.error("article_layout_failure operation=\(operation, privacy: .public) phase=\(phase, privacy: .public) elapsed=\(Date().timeIntervalSince(started))") }
        }
        logger.info("article_layout_start operation=\(operation, privacy: .public)")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 468, height: 680), configuration: configuration)
        web.navigationDelegate = self
        defer { timeout?.cancel(); timeout = nil; web.navigationDelegate = nil; web.stopLoading() }
        let safeBase = baseURL.flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        let document = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; font-src https: data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'">
        <style>
        html,body { margin:0; padding:0; background:white; color:#171717; }
        body { font:17px/1.65 Georgia,serif; overflow-wrap:break-word; }
        h1 { font-size:28px; line-height:1.25; margin:0 0 28px; }
        h2,h3,h4 { break-after:avoid; line-height:1.3; }
        p { orphans:3; widows:3; margin:0 0 18px; }
        img,svg,video,table { max-width:100% !important; height:auto; break-inside:avoid; }
        pre { white-space:pre-wrap; font-size:13px; } code { overflow-wrap:anywhere; }
        blockquote { margin:18px 12px; border-left:2px solid #bbb; padding-left:16px; }
        a { color:inherit; text-decoration:none; } iframe,script,form,button { display:none !important; }
        #paper-reader-source { max-width:100%; }
        .paper-figure-warning { font:14px/1.45 -apple-system,sans-serif; padding:14px; border:2px solid #9d6b10; background:#fff7df; margin:0 0 24px; break-inside:avoid; }
        .paper-figure-warning strong { display:block; margin-bottom:6px; }
        .paper-missing-figure { box-sizing:border-box; font:14px/1.45 -apple-system,sans-serif; padding:14px; border:2px dashed #999; background:#f8f8f8; color:#444; min-height:78px; margin:18px 0; break-inside:avoid; }
        </style></head><body><h1 id="paper-article-title">\(Self.escape(title))</h1><article id="paper-reader-source"></article></body></html>
        """
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigation = continuation
            timeout = Task { [weak self, weak web] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                web?.stopLoading(); self?.finish(.failure(ArticleRenderError.timedOut))
            }
            web.loadHTMLString(document, baseURL: safeBase)
        }
        logger.info("article_phase operation=\(operation, privacy: .public) phase=navigation_complete elapsed=\(Date().timeIntervalSince(started))")
        try Task.checkCancellation()
        phase = "body_insertion"
        logger.info("article_phase operation=\(operation, privacy: .public) phase=body_insertion_start elapsed=\(Date().timeIntervalSince(started))")
        // Reader may return a complete HTML document. Import its body into our page shell;
        // source head styles must not redefine print width, fonts or handwriting margins.
        _ = try await runJavaScript(in: web, body: """
        const parsed = new DOMParser().parseFromString(source, 'text/html');
        parsed.querySelectorAll('script,style,link,meta,iframe,object,embed,form,button,input,textarea').forEach(e => e.remove());
        parsed.querySelectorAll('*').forEach(e => {
            for (const attribute of Array.from(e.attributes)) {
                if (attribute.name.toLowerCase().startsWith('on')) e.removeAttribute(attribute.name);
            }
        });
        parsed.querySelectorAll('img').forEach(image => {
            image.loading = 'eager';
            if (!image.getAttribute('src')) {
                const lazy = image.getAttribute('data-src');
                if (lazy && /^(https:|data:image\\/)/i.test(lazy)) image.setAttribute('src', lazy);
            }
        });
        const container = document.getElementById('paper-reader-source');
        container.replaceChildren(...Array.from(parsed.body.childNodes).map(node => document.importNode(node, true)));
        const heading = container.querySelector('h1');
        const normalize = value => value.replace(/\\s+/g, ' ').trim().toLowerCase();
        if (heading && normalize(heading.textContent) === normalize(title)) {
            document.getElementById('paper-article-title').hidden = true;
        }
        window.paperArticleImages = Array.from(container.querySelectorAll('img')).filter(image => {
            const width = Number(image.getAttribute('width')), height = Number(image.getAttribute('height'));
            return !(width > 0 && width <= 2 && height > 0 && height <= 2)
                && getComputedStyle(image).display !== 'none';
        });
        return true;
        """, arguments: ["source": html, "title": title])
        logger.info("article_phase operation=\(operation, privacy: .public) phase=body_insertion_complete elapsed=\(Date().timeIntervalSince(started))")
        phase = "image_loading"
        logger.info("article_phase operation=\(operation, privacy: .public) phase=image_loading_start elapsed=\(Date().timeIntervalSince(started))")
        // Give late-loading figures a bounded chance to settle without freezing the interface.
        let imageDeadline = Date().addingTimeInterval(8)
        while Date() < imageDeadline {
            let ready = try await evaluateJavaScript(in: web, source: "window.paperArticleImages.every(i => i.complete)") as? Bool ?? true
            if ready { break }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        logger.info("article_phase operation=\(operation, privacy: .public) phase=image_loading_complete elapsed=\(Date().timeIntervalSince(started))")
        phase = "text_extraction"
        logger.info("article_phase operation=\(operation, privacy: .public) phase=text_extraction_start elapsed=\(Date().timeIntervalSince(started))")
        let text = (try await evaluateJavaScript(in: web, source: "document.getElementById('paper-reader-source').innerText") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ArticleRenderError.emptyContent }
        logger.info("article_phase operation=\(operation, privacy: .public) phase=text_extraction_complete characters=\(text.count) elapsed=\(Date().timeIntervalSince(started))")
        // Capture retained Reader text above before adding any Paper-generated labels.
        phase = "figure_placeholders"
        let missingResult = try await runJavaScript(in: web, body: """
        const unavailable = window.paperArticleImages.filter(image => !image.complete || image.naturalWidth === 0);
        if (unavailable.length) {
            const container = document.getElementById('paper-reader-source');
            const warning = document.createElement('aside');
            warning.className = 'paper-figure-warning';
            const heading = document.createElement('strong');
            heading.textContent = unavailable.length === 1 ? 'Paper: 1 figure unavailable' : 'Paper: ' + unavailable.length + ' figures unavailable';
            warning.appendChild(heading);
            warning.appendChild(document.createTextNode('The source could not provide every figure when this copy was prepared. Placeholders mark their positions. Open the original in Reader before relying on diagrams.'));
            container.before(warning);
            unavailable.forEach(image => {
                const placeholder = document.createElement('div');
                placeholder.className = 'paper-missing-figure';
                const label = document.createElement('strong');
                label.textContent = 'Figure unavailable in Paper';
                placeholder.appendChild(label);
                const alt = (image.getAttribute('alt') || '').trim();
                if (alt) {
                    const caption = document.createElement('div');
                    caption.textContent = 'Original label: ' + alt;
                    placeholder.appendChild(caption);
                }
                image.replaceWith(placeholder);
            });
        }
        return unavailable.length;
        """, arguments: [:])
        guard let missingFigureCount = missingResult as? Int else { throw ArticleRenderError.failed }
        logger.info("article_figures_ready operation=\(operation, privacy: .public) missing=\(missingFigureCount) elapsed=\(Date().timeIntervalSince(started))")
        phase = "printing"
        logger.info("article_phase operation=\(operation, privacy: .public) phase=printing_start elapsed=\(Date().timeIntervalSince(started))")
        let printer = ArticlePageRenderer()
        printer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let count = printer.numberOfPages
        guard count > 0 && count <= 2000 else { throw ArticleRenderError.failed }
        printer.prepare(forDrawingPages: NSRange(location: 0, length: count))
        let data = UIGraphicsPDFRenderer(bounds: printer.paperRect).pdfData { context in
            for page in 0..<count {
                context.beginPage()
                printer.drawPage(at: page, in: printer.paperRect)
            }
        }
        logger.info("article_phase operation=\(operation, privacy: .public) phase=printing_complete pages=\(count) bytes=\(data.count) elapsed=\(Date().timeIntervalSince(started))")
        phase = "validation"
        guard let pdf = PDFDocument(data: data), pdf.pageCount == count,
              !(pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ArticleRenderError.failed }
        logger.info("article_layout_complete operation=\(operation, privacy: .public) pages=\(count) elapsed=\(Date().timeIntervalSince(started))")
        completed = true
        return RenderedArticle(pdf: data, text: text, missingFigureCount: missingFigureCount)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(ArticleRenderError.failed)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(ArticleRenderError.failed)) }
    /// Explicitly retain the completion until WebKit finishes the body insertion.
    /// The callback overload's default nil handler is synchronous, even when written with `await`.
    func runJavaScript(in web: WKWebView, body: String, arguments: [String: Any]) async throws -> Any {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            web.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure: continuation.resume(throwing: ArticleRenderError.failed)
                }
            }
        }
    }
    /// Keep evaluation result and error lifetime explicit through the original completion API.
    func evaluateJavaScript(in web: WKWebView, source: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            web.evaluateJavaScript(source) { value, error in
                if error != nil { continuation.resume(throwing: ArticleRenderError.failed) }
                else { continuation.resume(returning: value) }
            }
        }
    }
    private func finish(_ result: Result<Void, Error>) {
        guard let pending = navigation else { return }
        navigation = nil; timeout?.cancel(); timeout = nil
        pending.resume(with: result)
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class ArticlePageRenderer: UIPrintPageRenderer {
    override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 612, height: 792) }
    // Generous right margin for Pencil notes, and stable geometry across device rotations.
    override var printableRect: CGRect { CGRect(x: 42, y: 44, width: 468, height: 704) }
}

extension DocumentStore {
    func importReaderArticle(at source: URL, metadata: ReaderPDF, html: String, text: String, missingFigures: Int = 0) throws -> StoredDocument {
        if let existing = try documents().first(where: { $0.readerID == metadata.id }) { return existing }
        var document = try importReaderPDF(at: source, metadata: metadata)
        if missingFigures > 0 {
            document.preparationWarning = "\(missingFigures) \(missingFigures == 1 ? "figure was" : "figures were") unavailable when this article was prepared. Placeholders mark their positions in the PDF."
        }
        let folder = pdfURL(for: document).deletingLastPathComponent()
        do {
            try Data(html.utf8).write(to: folder.appendingPathComponent("source.html"), options: .atomic)
            try Data(text.utf8).write(to: folder.appendingPathComponent("source.txt"), options: .atomic)
            try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return document
    }
    func articleText(for document: StoredDocument) throws -> String? {
        let url = pdfURL(for: document).deletingLastPathComponent().appendingPathComponent("source.txt")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
