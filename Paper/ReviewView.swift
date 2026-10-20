import SwiftUI
import PDFKit

struct ReviewView: View {
    @StateObject var model: ReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var task: Task<Void,Never>?
    @State private var showSettings = false
    @State private var allowRetry = false
    @State private var visiblePage = 1
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width > 800 {
                    HStack(alignment:.top,spacing:20) {
                        pdfPanel.frame(width:max(0,geometry.size.width-min(430,geometry.size.width * 0.4)-60),height:max(0,geometry.size.height-40)).clipped()
                        draftPanel.frame(width:min(430,geometry.size.width * 0.4),height:max(0,geometry.size.height-40))
                    }.padding(20)
                } else {
                    ScrollView { VStack(spacing:20) { pdfPanel.frame(width:max(0,geometry.size.width-32),height:geometry.size.height * 0.55).clipped(); draftPanel.frame(width:max(0,geometry.size.width-32),height:600) }.padding(16) }
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
                Button("I checked Reader — allow retry",role:.destructive) { if let id = model.selectedID { model.allowRetry(id) } }
            } message: { Text("Only do this after checking that Reader has no matching highlight. Retrying an unconfirmed delivery can create a duplicate.") }
        }.preferredColorScheme(.light)
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
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("What to keep").font(.system(size:25,design:.serif))
                if !model.items.isEmpty {
                    Picker("Review item",selection:$model.selectedID) {
                        ForEach(Array(model.items.enumerated()),id:\.element.id) { index,item in
                            Text("\(index+1) · Pages \(item.pageLabel) · \(item.state.rawValue)").tag(Optional(item.id))
                        }
                    }.onChange(of:model.selectedID) { _,_ in model.showPages() }
                }
                if let index = model.items.firstIndex(where:{$0.id == model.selectedID}) {
                    Text("Pages \(model.items[index].pageLabel) · \(model.items[index].kind)").font(.caption).foregroundStyle(.secondary)
                    Button("Show marked pages") { model.showPages() }
                    field("Passage to highlight",text:$model.items[index].quote,id:"review-quote",disabled:model.items[index].state != .draft)
                    field("Your note · AI transcription",text:$model.items[index].note,id:"review-note",disabled:model.items[index].state != .draft)
                    field("Diagram / other marks · AI interpretation",text:$model.items[index].interpretation,id:"review-interpretation",disabled:model.items[index].state != .draft)
                    Text("Check the words against your PDF. Interpretation is a suggestion you can edit or remove.").font(.caption).foregroundStyle(.secondary)
                    if model.items[index].quote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                        Text("Add an exact source passage to send a note to Reader. A drawing without a passage stays saved here with its interpretation.").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.items[index].state == .draft {
                        HStack {
                            Button("Skip") { model.items[index].state = .skipped; model.save() }
                            Button("Confirm and send to Reader") { let id=model.items[index].id; task=Task { await model.send(id) } }
                                .buttonStyle(.borderedProminent).disabled(!model.items[index].canSend || model.document.readerID == nil)
                                .accessibilityIdentifier("send-review")
                        }.disabled(model.busy)
                        if model.document.readerID == nil { Text("Imported PDF: drafts stay here. Sending needs the original Reader document link.").font(.caption).foregroundStyle(.secondary) }
                    } else if model.items[index].state == .sending {
                        Button("Check delivery") { let id=model.items[index].id; task=Task { await model.checkDelivery(id) } }.disabled(model.busy)
                        Button("I checked Reader; allow retry…") { allowRetry = true }.font(.caption).disabled(model.busy)
                    } else {
                        Label(model.items[index].state == .sent ? "Sent to Reader" : "Skipped",systemImage:"checkmark.circle")
                        if model.items[index].state == .skipped { Button("Restore draft") { model.items[index].state = .draft; model.save() }.disabled(model.busy) }
                    }
                } else { Text("Analyze marked pages or add a draft to begin. Your PDF stays available on the left.").foregroundStyle(.secondary) }
                Divider().padding(.vertical,6)
                Text("Analyze pages").font(.headline)
                HStack { Stepper("From \(model.firstPage)",value:$model.firstPage,in:1...model.pageCount); Stepper("To \(model.lastPage)",value:$model.lastPage,in:1...model.pageCount) }.font(.caption).disabled(model.busy)
                Text("Sends only these page images and their printed text to Anthropic. Up to 6 pages per analysis. Original ink stays in your PDF.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Analyze with Claude") { task=Task { await model.analyze() } }.buttonStyle(.bordered).accessibilityIdentifier("analyze-markup")
                    Button("Add draft") { model.addDraft() }.accessibilityIdentifier("add-review-draft")
                }.disabled(model.busy)
                if model.busy {
                    HStack { ProgressView(); TimelineView(.periodic(from:model.started,by:1)) { context in
                        Text("\(model.phase) · \(max(0,Int(context.date.timeIntervalSince(model.started))))s").font(.caption)
                    } }
                    if model.phase.contains("Preparing") || model.phase.contains("Claude") { Button("Cancel analysis") { task?.cancel() } }
                }
                if let error=model.error { Text(error).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("review-error") }
                if let message=model.message { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("review-message") }
            }.padding(.bottom,20)
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("review-drafts")
    }
    private func field(_ label:String,text:Binding<String>,id:String,disabled:Bool) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(label).font(.subheadline); TextEditor(text:text).frame(minHeight:90).padding(6)
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
    @State private var key=""
    @State private var connected=false
    @State private var error:String?
    var body:some View {
        NavigationStack {
            Form {
                Section("Anthropic") {
                    Text(connected ? "API key saved in this iPad’s Keychain" : "Add your Anthropic API key")
                    SecureField("Anthropic API key",text:$key).accessibilityIdentifier("anthropic-key").textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") { do { try credentials.save(key);key="";connected=true;dismiss() }catch{ self.error="The API key couldn’t be saved. Try again." } }.accessibilityIdentifier("save-anthropic-key").disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    Text("Analysis sends the selected PDF pages to Anthropic using your account. Usage is billed by Anthropic. Your key stays in Keychain.").font(.caption)
                }
                if let error{Text(error)}
            }.navigationTitle("AI settings").toolbar{Button("Done"){dismiss()}}
                .task { connected=(try? credentials.read()) != nil }
        }
    }
}
