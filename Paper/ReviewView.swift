import SwiftUI
import PDFKit

struct ReviewView: View {
    @StateObject var model: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var task: Task<Void,Never>?
    @State private var showSettings = false
    @State private var allowRetry = false
    @State private var visiblePage = 1
    @State private var showHistory = false
    @State private var showAllPages = false
    @State private var retryID: UUID?
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > 800 {
                    HStack(alignment:.top,spacing:20) {
                        contextPanel.frame(width:max(0,geometry.size.width-min(430,geometry.size.width * 0.4)-60),height:max(0,geometry.size.height-40)).clipped()
                        draftPanel.frame(width:min(430,geometry.size.width * 0.4),height:max(0,geometry.size.height-40))
                    }.padding(20)
                } else {
                    ScrollView { VStack(spacing:20) { contextPanel.frame(width:max(0,geometry.size.width-32),height:geometry.size.height * 0.55).clipped(); draftPanel.frame(width:max(0,geometry.size.width-32),height:600) }.padding(16) }
                }
            }
            .navigationTitle("Review your markup").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button("Done") { model.save(); dismiss() }.disabled(model.busy) }
                ToolbarItem(placement:.topBarTrailing) { Button("AI settings",systemImage:"key") { showSettings = true }.disabled(model.busy) }
            }
            .sheet(isPresented:$showSettings) { AISettingsView(credentials:model.aiCredentials) }
            .task { await model.loadPages() }
            .onChange(of:model.items) { _,_ in model.save() }
            .interactiveDismissDisabled(model.busy)
            .confirmationDialog("Allow another send?",isPresented:$allowRetry,titleVisibility:.visible) {
                Button("I checked Reader — allow retry",role:.destructive) { if let id = retryID { model.allowRetry(id) } }
            } message: { Text("Only do this after checking that Reader has no matching highlight. Retrying an unconfirmed delivery can create a duplicate.") }
        }.preferredColorScheme(.light)
    }
    private var locationNoun: String { model.isDirectReading ? "regions" : "pages" }
    private func directRegionLabel(_ number: Int) -> String {
        guard let captures = model.directPages, captures.count > 1,
              let index = captures.firstIndex(where: { $0.number == number }) else { return "Marked region" }
        return "Marked region \(index + 1)"
    }
    private var contextPanel: some View {
        Group {
            if model.isDirectReading, let page = model.directPages?.first(where: { $0.number == model.jumpPage }),
               let image = UIImage(data: page.jpeg) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(directRegionLabel(page.number)).font(.headline)
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("Saved handwriting and text")
                        if !page.sourceText.isEmpty {
                            DisclosureGroup("Original passage text") {
                                Text(page.sourceText).font(.body).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } else if model.isDirectReading {
                ContentUnavailableView("No capture for this region", systemImage: "scribble",
                    description: Text("Open the document to see your original marks."))
            } else {
                pdfPanel
            }
        }
    }
    private var pdfPanel: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(model.document.title).font(.headline).lineLimit(1); Spacer(); Text("Page \(visiblePage) / \(model.pageCount)").font(.caption) }
            if let url = try? model.documentStore.workingPDFURL(for:model.document) {
                ReviewPDFView(url:url,page:model.jumpPage,jumpID:model.jumpID,visiblePage:$visiblePage)
                    .clipShape(RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("review-pdf")
            }
        }
    }
    private var draftPanel: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("What to keep").font(.system(size:25,design:.serif))
                Text("\(model.pendingItems.count) to review").font(.subheadline).foregroundStyle(.secondary)
                if model.items.isEmpty { Text("Choose the marked \(locationNoun) to prepare notes. Your ink is saved on this iPad.").foregroundStyle(.secondary) }
                ForEach(model.items.indices.filter { model.items[$0].state == .draft || model.items[$0].state == .sending },id:\.self) { index in
                    reviewCard(index)
                }
                let completed = model.items.indices.filter { model.items[$0].state == .sent || model.items[$0].state == .skipped }
                if !completed.isEmpty {
                    DisclosureGroup("Sent and skipped (\(completed.count))",isExpanded:$showHistory) {
                        ForEach(completed,id:\.self) { index in reviewCard(index) }
                    }
                }
                Divider().padding(.vertical,6)
                Text("Analyze \(locationNoun)").font(.headline)
                HStack {
                    Text("\(model.selectedPages.count) of 6 \(locationNoun) selected").font(.caption)
                    Spacer()
                    if !model.isDirectReading { Button(showAllPages ? "Marked pages" : "All pages") { showAllPages.toggle() }.font(.caption) }
                }
                if model.markedPages.isEmpty && !showAllPages {
                    Text(model.isDirectReading
                         ? "Open the document to capture a marked region."
                         : "No separate markup annotations detected. Choose All pages to include flattened marks or add context.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment:.top,spacing:10) {
                        ForEach(showAllPages ? model.analysisNumbers : model.markedPages,id:\.self) { number in
                            Button { model.togglePage(number) } label: {
                                VStack(spacing:5) {
                                    previewThumbnail(number)
                                        .frame(width:100,height:130).clipped()
                                        .overlay(RoundedRectangle(cornerRadius:6).stroke(model.selectedPages.contains(number) ? Color.accentColor : Color.gray.opacity(0.25),lineWidth:model.selectedPages.contains(number) ? 3 : 1))
                                    Label(model.isDirectReading ? directRegionLabel(number) : "Page \(number)",systemImage:model.selectedPages.contains(number) ? "checkmark.circle.fill" : "circle").font(.caption)
                                    Text(model.changedPages.contains(number) ? "New / changed" : "Reviewed / context").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).disabled(model.busy || (!model.selectedPages.contains(number) && model.selectedPages.count >= 6))
                                .accessibilityIdentifier("analysis-page-\(number)")
                        }
                    }.padding(4)
                }
                if !model.analysisNumbers.isEmpty {
                    Toggle("Reanalyze unchanged \(locationNoun)",isOn:$model.reanalyze).font(.caption).disabled(model.busy)
                    Text("Analysis uses the selected \(locationNoun). Confirm each quote and note separately before sending to Reader.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Analyze selected \(locationNoun)") { task=Task { await model.analyze() } }.buttonStyle(.borderedProminent).accessibilityIdentifier("analyze-markup").disabled(model.selectedPages.isEmpty)
                    Button("Add draft") { model.addDraft() }.accessibilityIdentifier("add-review-draft")
                }.disabled(model.busy)
                if let latest = model.usage.last { Text(latest.summary).font(.caption).foregroundStyle(.secondary) }
                if model.busy {
                    HStack { ProgressView(); TimelineView(.periodic(from:model.started,by:1)) { context in
                        Text("\(model.phase) · \(max(0,Int(context.date.timeIntervalSince(model.started))))s").font(.caption)
                    } }
                    if model.phase.contains("Preparing") || model.phase.contains("Claude") { Button("Cancel analysis") { task?.cancel() } }
                }
                if model.feedbackItemID == nil, let error=model.error { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("review-error") }
                if let message=model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("review-message") }
            }.padding(.bottom,20)
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("review-drafts")
            .onChange(of:model.selectedID) { _, id in if let id { withAnimation { proxy.scrollTo(id,anchor:.top) } } }
            .onAppear { if let id = model.selectedID { DispatchQueue.main.async { proxy.scrollTo(id,anchor:.top) } } }
        }
    }
    @ViewBuilder private func previewThumbnail(_ number: Int) -> some View {
        if let page = model.directPages?.first(where: { $0.number == number }),
           let image = UIImage(data: page.jpeg) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            ReviewPageThumbnail(url: try? model.documentStore.workingPDFURL(for: model.document), number: number)
        }
    }
    private func reviewCard(_ index: Int) -> some View {
        let item = model.items[index]
        return VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("\(item.locationLabel) · \(item.kind)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if (item.directInk == true) == model.isDirectReading {
                    Button(model.isDirectReading ? "View region" : "View page") { model.select(item.id) }.font(.caption)
                }
            }
            field("Passage to highlight",text:$model.items[index].quote,id:"review-quote",disabled:item.state != .draft)
                .onChange(of: item.quote) { _, _ in model.clearQuoteFeedback(item.id) }
            if model.feedbackItemID == item.id, let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption)
                    .foregroundStyle(.secondary).accessibilityIdentifier("review-error")
            }
            field("Your note · transcription",text:$model.items[index].note,id:"review-note",disabled:item.state != .draft)
            if !item.interpretation.isEmpty || item.kind == "diagram" || item.quote.isEmpty {
                field("Diagram / other marks · AI interpretation",text:$model.items[index].interpretation,id:"review-interpretation",disabled:item.state != .draft)
            }
            if let alternatives = item.alternatives, !alternatives.isEmpty {
                DisclosureGroup("Other transcriptions (\(alternatives.count))") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("New analysis is kept here so your reviewed words stay intact.").font(.caption).foregroundStyle(.secondary)
                        ForEach(alternatives.indices,id:\.self) { index in
                            VStack(alignment:.leading,spacing:6) {
                                if !alternatives[index].note.isEmpty { Text(alternatives[index].note).font(.subheadline) }
                                if !alternatives[index].interpretation.isEmpty { Text("AI interpretation: " + alternatives[index].interpretation).font(.caption).foregroundStyle(.secondary) }
                                if item.state == .draft {
                                    Button("Use this transcription") { model.useAlternative(item.id,index:index) }.font(.caption).disabled(model.busy)
                                } else { Text("Saved locally; the confirmed Reader note stays as sent.").font(.caption).foregroundStyle(.secondary) }
                            }.padding(10).background(Color(.tertiarySystemBackground),in:RoundedRectangle(cornerRadius:8))
                        }
                    }.padding(.top,8)
                }.font(.subheadline)
            }
            if item.quote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                Label("Your drawing stays on this iPad. To send a note to Reader, add an exact passage from the original.",systemImage:"pencil.and.outline").font(.caption).foregroundStyle(.secondary)
            }
            if item.state == .draft {
                HStack {
                    Button(item.canSend ? "Skip" : "Keep on iPad") { model.items[index].state = .skipped; model.save() }
                    Spacer()
                    Button("Confirm & send") { task=Task { await model.send(item.id) } }.buttonStyle(.borderedProminent)
                        .disabled(!item.canSend || model.document.readerID == nil).accessibilityIdentifier("send-review")
                }.disabled(model.busy)
                if model.document.readerID == nil { Text("Notes stay on this iPad. Sending requires the original Reader link.").font(.caption).foregroundStyle(.secondary) }
            } else if item.state == .sending {
                Button("Check delivery") { task=Task { await model.checkDelivery(item.id) } }.disabled(model.busy)
                Button("I checked Reader; allow retry…") { retryID=item.id; allowRetry=true }.font(.caption).disabled(model.busy)
            } else {
                Label(item.state == .sent ? "Sent to Reader" : "Kept on iPad",systemImage:"checkmark.circle")
                if item.state == .skipped { Button("Restore draft") { model.items[index].state = .draft; model.save() }.disabled(model.busy) }
            }
        }.padding(16).background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:14)).id(item.id)
            .overlay(RoundedRectangle(cornerRadius:14).stroke(model.selectedID == item.id ? Color.accentColor.opacity(0.5) : Color.clear))
    }
    private func field(_ label:String,text:Binding<String>,id:String,disabled:Bool) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(label).font(.subheadline); TextEditor(text:text).frame(minHeight:80,maxHeight:140).padding(6)
            .overlay(RoundedRectangle(cornerRadius:8).stroke(Color.gray.opacity(0.35))).accessibilityIdentifier(id).disabled(disabled || model.busy) }
    }
}

private struct ReviewPDFView: UIViewRepresentable {
    let url: URL; let page:Int; let jumpID:UUID
    @Binding var visiblePage:Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context:Context) -> PDFView {
        let view=PDFView(); view.document=PDFDocument(url:url); view.autoScales=true
        view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; view.backgroundColor = .secondarySystemBackground
        // Read-only context; editing continues through native Quick Look.
        context.coordinator.observe(view)
        return view
    }
    func updateUIView(_ view:PDFView,context:Context) {
        context.coordinator.parent=self
        if context.coordinator.lastJump != jumpID, let target=view.document?.page(at:max(0,page-1)) {
            context.coordinator.lastJump=jumpID; DispatchQueue.main.async { view.go(to:target) }
        }
    }
    static func dismantleUIView(_ view:PDFView,coordinator:Coordinator) { coordinator.token.map(NotificationCenter.default.removeObserver) }
    final class Coordinator {
        var parent:ReviewPDFView; var lastJump:UUID?; var token:NSObjectProtocol?
        init(_ parent:ReviewPDFView){ self.parent=parent }
        func observe(_ view:PDFView) {
            token=NotificationCenter.default.addObserver(forName:.PDFViewPageChanged,object:view,queue:.main) { [weak self,weak view] _ in
                guard let self,let view,let page=view.currentPage,let document=view.document else{return}
                self.parent.visiblePage=document.index(for:page)+1
            }
        }
    }
}

struct AISettingsView: View {
    let credentials:ReaderCredentials
    @Environment(\.dismiss) private var dismiss
    @AppStorage("analysis-model") private var analysisModel = AnthropicMarkupAPI.model
    @State private var key=""
    @State private var connected=false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            Form {
                Section("Analysis quality and cost") {
                    Picker("Model",selection:$analysisModel) {
                        Text("Sonnet · established quality").tag("claude-sonnet-5-5")
                        Text("Haiku · lower cost, evaluate carefully").tag("claude-haiku-5-5")
                    }
                    Text("Sonnet stays the default. Try Haiku on representative handwriting and diagrams and check every transcription. Unchanged pages are not analyzed again unless requested.").font(.caption)
                    Text("Per million tokens: Sonnet $2 input / $10 output; Haiku $0.10 / $0.50 for prompts under 100k tokens. Actual usage appears after analysis; provider billing applies.").font(.caption)
                }
                Section("Anthropic") {
                    Text(connected ? "API key saved in this iPad’s Keychain" : "Add your Anthropic API key")
                    SecureField("Anthropic API key",text:$key).accessibilityIdentifier("anthropic-key").textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") { do { try credentials.save(key);key="";connected=true;dismiss() }catch{ self.error="The API key couldn’t be saved. Try again." } }.accessibilityIdentifier("save-anthropic-key").disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    Text("Analysis sends the selected images and nearby text to Anthropic using your account. Usage is billed by Anthropic. Your key stays in Keychain.").font(.caption)
                }
                if let error{Text(error)}
            }.navigationTitle("AI settings").toolbar{Button("Done"){dismiss()}}
                .task { connected=(try? credentials.read()) != nil }
        }
    }
}

private struct ReviewPageThumbnail: View {
    let url: URL?
    let number: Int
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit() }
            else { Rectangle().fill(Color(.secondarySystemBackground)).overlay(ProgressView()) }
        }.task(id:number) {
            guard let url else { return }
            image = await Task.detached(priority:.utility) {
                PDFDocument(url:url)?.page(at:number-1)?.thumbnail(of:CGSize(width:160,height:210),for:.mediaBox)
            }.value
        }
    }
}
