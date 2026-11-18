import SwiftUI
import PencilKit
import WebKit
import OSLog

struct DirectArticleReader: View {
    let document: StoredDocument
    let sections: [DirectReadingSection]
    let store: DocumentStore
    let onClose: () -> Void
    let makeReview: ([AnalysisPage], String) -> ReviewModel

    @State private var index = 0
    @State private var controller: DirectInkController?
    private struct ReviewPresentation: Identifiable {
        let id = UUID()
        let model: ReviewModel
    }

    @State private var review: ReviewPresentation?
    @State private var visibleInk = false
    @State private var capturing = false
    @State private var error: String?

    private var chapterKey: String { "paper.direct.chapter." + document.id.uuidString }

    var body: some View {
        NavigationStack {
            DirectInkSurface(section: sections[index], ink: DirectInkStore(document: document, store: store),
                onController: { controller = $0 },
                onState: { visibleInk = $0 },
                onError: { error = $0 })
                .background(Color.white)
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { controller?.persist(); onClose() }.accessibilityIdentifier("direct-reader-done")
                    }
                    if sections.count > 1 {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu("Contents", systemImage: "list.bullet") {
                                ForEach(sections.indices, id: \.self) { destination in
                                    Button(sections[destination].title) {
                                        controller?.persist()
                                        index = destination
                                        UserDefaults.standard.set(index, forKey: chapterKey)
                                    }
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Review markup", systemImage: "square.and.pencil", action: openReview)
                            .disabled(capturing)
                    }
                }
        }
        .preferredColorScheme(.light)
        .onAppear {
            index = min(max(0, UserDefaults.standard.integer(forKey: chapterKey)), sections.count - 1)
        }
        .alert("Paper", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .fullScreenCover(item: $review, onDismiss: { controller?.showTools() }) {
            ReviewView(model: $0.model)
        }
        .overlay(alignment: .bottom) {
            if capturing {
                ProgressView("Capturing marked text")
                    .padding(12).background(.regularMaterial, in: Capsule()).padding()
            }
        }
    }

    private var canonicalText: String { (try? store.articleText(for: document)) ?? "" }

    private func openReview() {
        guard let controller else { return }
        guard visibleInk else {
            controller.hideTools()
            review = ReviewPresentation(model: makeReview([], canonicalText))
            return
        }
        capturing = true
        Task {
            defer { capturing = false }
            do {
                let page = try await controller.capture(chapter: index)
                controller.hideTools()
                review = ReviewPresentation(model: makeReview([page], canonicalText))
            } catch {
                self.error = "Paper couldn’t capture this marked region. Try scrolling slightly and reopening review."
            }
        }
    }
}

private struct DirectInkSurface: UIViewControllerRepresentable {
    let section: DirectReadingSection
    let ink: DirectInkStore
    let onController: (DirectInkController) -> Void
    let onState: (Bool) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> DirectInkController {
        let controller = DirectInkController(ink: ink)
        DispatchQueue.main.async { onController(controller) }
        return controller
    }

    func updateUIViewController(_ controller: DirectInkController, context: Context) {
        controller.onState = onState
        controller.onError = onError
        controller.open(section)
    }
}

final class DirectInkController: UIViewController, WKNavigationDelegate, PKCanvasViewDelegate {
    private static let layoutWidth: CGFloat = 820
    private let inkStore: DirectInkStore
    private let web: WKWebView
    private let surface = UIView()
    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private let inkUndo = UndoManager()
    private let log = Logger(subsystem: "com.aayush.paper.reader", category: "DirectReader")
    private var contentSizeObservation: NSKeyValueObservation?
    private var sectionID: String?
    private var loadTask: Task<Void, Never>?
    private var activeNavigation: WKNavigation?
    private var blockingRulesInstalled = false
    private var ready = false
    private var readableInkFile = true
    private var appeared = false
    private var restorePosition: CGFloat?
    private var documentHeightAtLoad: CGFloat?
    private var pendingPositionSave: Task<Void, Never>?
    private var savedOffset: CGFloat = 0
    private var drawingNeedsSave = false
    var onState: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    override var undoManager: UndoManager? { inkUndo }

    init(ink: DirectInkStore) {
        inkStore = ink
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(source: Self.layoutScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        self.web = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        surface.clipsToBounds = true
        view.addSubview(surface)
        surface.addSubview(web)
        surface.addSubview(canvas)
        web.navigationDelegate = self
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.isScrollEnabled = false
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.allowsLinkPreview = false

        // Both views use the same 820-point document width. The canvas owns scrolling.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bounces = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = self
        canvas.isUserInteractionEnabled = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAPER_UI_TEST"] == "1",
           ProcessInfo.processInfo.environment["PAPER_TEST_DIRECT_DRAW"] == "1" {
            canvas.drawingPolicy = .anyInput
        }
        #endif
        toolPicker.addObserver(canvas)
        contentSizeObservation = web.scrollView.observe(\.contentSize) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateScrollGeometry() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = Self.layoutWidth
        let scale = min(1, view.bounds.width / width)
        guard scale > 0 else { return }
        surface.bounds = CGRect(x: 0, y: 0, width: width, height: view.bounds.height / scale)
        surface.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        surface.transform = CGAffineTransform(scaleX: scale, y: scale)
        web.frame = surface.bounds
        canvas.frame = surface.bounds
        updateScrollGeometry()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
        showTools()
    }

    override func viewWillDisappear(_ animated: Bool) {
        appeared = false
        hideTools()
        persist()
        super.viewWillDisappear(animated)
    }

    func showTools() {
        guard appeared, ready, restorePosition == nil, readableInkFile, canvas.window != nil else { return }
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    func hideTools() {
        toolPicker.setVisible(false, forFirstResponder: canvas)
        canvas.resignFirstResponder()
    }

    func open(_ section: DirectReadingSection) {
        guard sectionID != section.id else { return }
        persist()
        loadViewIfNeeded()
        ready = false
        sectionID = section.id
        activeNavigation = nil
        hideTools()
        canvas.isUserInteractionEnabled = false
        inkUndo.removeAllActions()
        let state: DirectInkState
        do {
            state = try inkStore.load(section: section.id)
            readableInkFile = true
        } catch {
            state = DirectInkState()
            readableInkFile = false
            DispatchQueue.main.async { self.onError?("The saved ink couldn’t be read. Its file has been kept.") }
        }
        canvas.drawing = state.drawing
        savedOffset = state.offset
        drawingNeedsSave = false
        restorePosition = state.offset
        documentHeightAtLoad = nil
        web.stopLoading()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !self.blockingRulesInstalled {
                    guard let rules = try await WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: "PaperOfflineReader", encodedContentRuleList: Self.offlineRules) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    try Task.checkCancellation()
                    self.web.configuration.userContentController.add(rules)
                    self.blockingRulesInstalled = true
                }
                try Task.checkCancellation()
                self.activeNavigation = self.web.loadFileURL(section.fileURL, allowingReadAccessTo: section.readAccessURL)
            } catch is CancellationError {
                return
            } catch {
                self.onError?("Paper couldn’t open this section in the offline reader.")
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        guard let offset = restorePosition, offset > 0 else {
            ready = true
            updateScrollGeometry()
            return
        }
        // WebKit can publish the final native content size after didFinish.
        loadTask = Task { [weak self] in
            guard let self else { return }
            let height = try? await web.callAsyncJavaScript(
                "return document.scrollingElement.scrollHeight;",
                arguments: [:], in: nil, contentWorld: .defaultClient
            ) as? NSNumber
            guard !Task.isCancelled, navigation === activeNavigation else { return }
            documentHeightAtLoad = height.map { CGFloat($0.doubleValue) }
            ready = true
            updateScrollGeometry()
        }
    }

    private func updateScrollGeometry() {
        guard ready, canvas.bounds.height > 0 else { return }
        let height = web.scrollView.contentSize.height
        let viewportHeight = canvas.bounds.height
        canvas.contentSize = CGSize(width: Self.layoutWidth, height: max(height, viewportHeight))
        if let offset = restorePosition {
            let target = min(max(0, offset), max(0, (documentHeightAtLoad ?? height) - viewportHeight))
            let limit = canvas.contentSize.height - viewportHeight
            guard limit + 1 >= target else { return }
            canvas.contentOffset = CGPoint(x: 0, y: min(target, limit))
            restorePosition = nil
            canvas.isDrawingEnabled = readableInkFile
            canvas.isUserInteractionEnabled = true
            publishState()
            showTools()
        }
        syncArticleOffset()
    }

    private func syncArticleOffset() {
        if web.scrollView.contentOffset != canvas.contentOffset {
            web.scrollView.contentOffset = canvas.contentOffset
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?("This reading section couldn’t be opened.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { onError?("This reading section couldn’t be opened.") }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        decisionHandler(action.navigationType == .other && url?.isFileURL == true ? .allow : .cancel)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard ready, restorePosition == nil else { return }
        syncArticleOffset()
        publishState()
        pendingPositionSave?.cancel()
        pendingPositionSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.persist()
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard ready, readableInkFile else { return }
        drawingNeedsSave = true
        publishState()
        persist()
    }

    func persist() {
        pendingPositionSave?.cancel()
        guard ready, readableInkFile, restorePosition == nil, let sectionID else { return }
        let offset = max(0, canvas.contentOffset.y)
        guard drawingNeedsSave || offset != savedOffset else { return }
        do {
            try inkStore.save(DirectInkState(drawing: canvas.drawing, offset: offset), section: sectionID)
            drawingNeedsSave = false
            savedOffset = offset
        } catch {
            onError?("Paper couldn’t save your ink or reading position.")
        }
    }

    private func publishState() {
        let viewport = canvas.bounds
        let drawing = canvas.drawing
        let visible = drawing.bounds.intersects(viewport) &&
            drawing.strokes.contains { $0.renderBounds.intersects(viewport) }
        onState?(visible)
    }

    func capture(chapter: Int) async throws -> AnalysisPage {
        let started = Date()
        log.info("direct_review_capture_start")
        defer { log.info("direct_review_capture_end elapsed=\(Date().timeIntervalSince(started))") }
        guard ready, restorePosition == nil else { throw CocoaError(.fileReadUnknown) }
        let section = sectionID
        canvas.stopScrollingAndZooming()
        canvas.isUserInteractionEnabled = false
        defer { if sectionID == section, ready { canvas.isUserInteractionEnabled = true } }
        let canvasViewport = canvas.bounds
        let drawing = canvas.drawing
        syncArticleOffset()
        let viewport = CGRect(origin: web.scrollView.contentOffset, size: web.bounds.size)
        let text = try await web.callAsyncJavaScript("""
            const candidates = document.body.querySelectorAll('p, li, h1, h2, h3, h4, figcaption, blockquote, pre, td');
            const visible = [...candidates].filter(el => {
                const rect = el.getBoundingClientRect();
                return rect.bottom >= 0 && rect.top <= innerHeight && rect.height > 0;
            });
            return visible.map(el => el.innerText).join('\\n') || document.body.innerText;
            """, arguments: [:], in: nil, contentWorld: .defaultClient) as? String ?? ""
        let configuration = WKSnapshotConfiguration()
        let snapshot = try await web.takeSnapshot(configuration: configuration)
        guard ready, sectionID == section, canvas.bounds == canvasViewport,
              web.scrollView.contentOffset == viewport.origin, web.bounds.size == viewport.size,
              viewport.width > 0, snapshot.size.width > 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.scale
        let scale = snapshot.size.width / viewport.width
        let inkImage = drawing.image(from: viewport, scale: scale * format.scale)
        let image = UIGraphicsImageRenderer(size: snapshot.size, format: format).image { _ in
            snapshot.draw(at: .zero)
            inkImage.draw(in: CGRect(origin: .zero, size: snapshot.size))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileWriteUnknown) }
        let region = chapter * 100_000 + Int(max(0, viewport.minY) / 600) + 1
        return AnalysisPage(number: region, jpeg: jpeg, sourceText: String(text.prefix(16_000)))
    }

    private static let offlineRules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """

    private static let layoutScript = """
        const viewport = document.createElementNS('http://www.w3.org/1999/xhtml', 'meta');
        viewport.name = 'viewport';
        viewport.content = 'width=820, initial-scale=1, maximum-scale=1, user-scalable=no';
        document.querySelectorAll('meta[name=viewport]').forEach(el => el.remove());
        document.head.append(viewport);
        const style = document.createElementNS('http://www.w3.org/1999/xhtml', 'style');
        style.textContent = `
            html { -webkit-text-size-adjust: none !important; background: white !important; }
            body { box-sizing:border-box !important; width:820px !important; max-width:none !important;
                padding:42px 104px 96px 76px !important; margin:0 !important; color:#252722 !important;
                background:white !important; font: 21px/1.58 Georgia, serif !important; }
            p, li, blockquote { line-height:1.58 !important; }
            img, svg, video, table { max-width:100% !important; height:auto; }
            pre { white-space:pre-wrap; overflow-wrap:anywhere; }
            a { color:#36564a; }
        `;
        document.head.append(style);
        """
}
