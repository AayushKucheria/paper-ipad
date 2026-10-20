import SwiftUI
import PDFKit

private enum CoverImages { static let cache: NSCache<NSString,UIImage> = { let cache=NSCache<NSString,UIImage>();cache.totalCostLimit=32 * 1024 * 1024;return cache }() }

struct DocumentCover: View {
    let local: StoredDocument?
    let store: DocumentStore
    let remote: URL?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit() }
            else if let remote, remote.scheme == "https" {
                AsyncImage(url:remote) { phase in
                    if let image=phase.image { image.resizable().scaledToFit() } else { placeholder }
                }
            } else { placeholder }
        }.frame(width:72,height:96).background(Color(uiColor:.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius:4))
            .overlay(RoundedRectangle(cornerRadius:4).stroke(Color.gray.opacity(0.2)))
            .accessibilityHidden(true)
            .task(id:local?.id) {
                guard let local else {return}
                let source=store.pdfURL(for:local)
                if let cached=CoverImages.cache.object(forKey:source.path as NSString) { image=cached;return }
                image=await Task.detached(priority:.utility) {
                    guard let pdf=PDFDocument(url:source),let page=pdf.page(at:0) else{return nil as UIImage?}
                    return page.thumbnail(of:CGSize(width:144,height:192),for:.mediaBox)
                }.value
                if let image { CoverImages.cache.setObject(image,forKey:source.path as NSString,cost:Int(image.size.width * image.size.height * 4)) }
            }
    }
    private var placeholder:some View { Image(systemName:"doc.richtext").font(.title2).foregroundStyle(.secondary) }
}

struct RemovedDownloadsView: View {
    let store:DocumentStore
    let onChange:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var documents:[StoredDocument]=[]
    @State private var deleting:StoredDocument?
    @State private var error:String?
    var body:some View {
        NavigationStack {
            List {
                Section { Text("Removed PDFs and markup can be restored. They use storage until permanently deleted.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(documents) { doc in
                    HStack {
                        Text(doc.title);Spacer()
                        Button("Restore") { act { try store.restoreDownload(doc) } }.buttonStyle(.bordered).accessibilityIdentifier("restore-\(doc.id)")
                        Button("Delete permanently",role:.destructive) { deleting=doc }.buttonStyle(.borderless)
                    }
                }
                if documents.isEmpty { Text("No recently removed PDFs") }
                if let error { Text(error) }
            }.navigationTitle("Recently Removed").toolbar{Button("Done"){dismiss()}}
                .task{load()}
                .confirmationDialog("Delete PDF and all its markup permanently?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible) {
                    Button("Delete PDF and markup",role:.destructive) { if let doc=deleting{act{try store.permanentlyDelete(doc)}};deleting=nil }
                } message:{Text("This frees storage on this iPad. It also removes local review drafts. Your Reader document and any highlights already sent there are kept.")}
        }.preferredColorScheme(.light)
    }
    private func act(_ work:() throws->Void){do{try work();load();onChange()}catch{self.error="This PDF couldn’t be moved. Its files remain on this iPad."}}
    private func load(){do{documents=try store.removedDocuments()}catch{self.error="Removed PDFs couldn’t be loaded."}}
}
