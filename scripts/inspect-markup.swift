import Foundation
import PDFKit
import AppKit
import Vision
// Read-only experiment. Inputs stay untouched; crops/transcriptions are private output.
// Usage: swift scripts/inspect-markup.swift <Library directory> <output directory> [--ink-only]
guard CommandLine.arguments.count >= 3 else {
 fputs("Usage: inspect-markup.swift <Library> <output> [--ink-only]\n", stderr); exit(2)
}
let started = Date()
let inkOnly = CommandLine.arguments.contains("--ink-only")
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
var reports: [[String: Any]] = []
let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
for (di, folder) in folders.enumerated() {
 guard let pdf = PDFDocument(url: folder.appendingPathComponent("reading.pdf")) else { continue }
 for pi in 0..<pdf.pageCount {
  guard let page = pdf.page(at: pi) else { continue }
  for (ai, annotation) in page.annotations.enumerated() where annotation.type == "Stamp" {
   let rect = annotation.bounds.insetBy(dx: -24, dy: -24).intersection(page.bounds(for: .mediaBox))
   guard !rect.isEmpty else { continue }
   let scale: CGFloat = 2
   let ctx = CGContext(data: nil, width: Int(ceil(rect.width * scale)), height: Int(ceil(rect.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
   ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0,y: 0,width: ctx.width,height: ctx.height))
   ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -rect.minX, y: -rect.minY)
   if inkOnly { annotation.draw(with: .mediaBox, in: ctx) } else { page.draw(with: .mediaBox, to: ctx) }
   let img = ctx.makeImage()!
   let name = "document-\(di+1)-page-\(pi+1)-stamp-\(ai+1)"
   let bitmap = NSBitmapImageRep(cgImage: img)
   try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name+".png"))
   print("ocr_start document=\(di+1) page=\(pi+1) elapsed=\(Date().timeIntervalSince(started))"); fflush(stdout)
   let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
   try VNImageRequestHandler(cgImage: img).perform([req])
   let candidates = (req.results ?? []).compactMap { item -> [String: Any]? in
    guard let text = item.topCandidates(1).first else { return nil }
    return ["text": text.string, "confidence": text.confidence]
   }
   reports.append(["crop": name+".png", "page": pi+1,"ocr":candidates,"nearbyPDFText": page.selection(for: rect)?.string ?? ""])
   print("\(name): OCR lines=\(candidates.count)")
  }
 }
}
try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("ocr-private.json"))
print("Rendered \(reports.count) stamp crops; private OCR saved locally. elapsed=\(Date().timeIntervalSince(started))")
