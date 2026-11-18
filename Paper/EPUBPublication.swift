import Foundation

struct DirectReadingSection: Identifiable, Equatable {
    let id: String
    let title: String
    let fileURL: URL
    let readAccessURL: URL
    let baseURL: URL?
}

struct EPUBPublication: Codable {
    /// Headings often carry markup whitespace ("Act\n\t\t\tI"); show them as one readable line.
    static func displayTitle(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace })
        return words.isEmpty ? raw : words.joined(separator: " ")
    }

    struct Chapter: Codable {
        let path: String
        let title: String
    }

    let title: String?
    let author: String?
    let chapters: [Chapter]

    static func open(in directory: URL) throws -> Self {
        let container = try readXML(directory.appendingPathComponent("META-INF/container.xml"))
        guard let packagePath = container.rootFile, EPUBArchive.safeComponents(packagePath) != nil else { throw EPUBError.invalidPublication }
        let package = try readXML(directory.appendingPathComponent(packagePath))
        let parent = Array(packagePath.split(separator: "/").dropLast()).map(String.init)
        var chapters: [Chapter] = []
        var included: Set<String> = []
        for id in package.spine {
            guard let item = package.manifest[id],
                  ["application/xhtml+xml", "text/html"].contains(item.mediaType),
                  let path = resolve(item.href, from: parent),
                  included.insert(path).inserted else { continue }
            let url = directory.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { throw EPUBError.invalidPublication }
            let chapter = try? readXML(url)
            let title = chapter?.firstHeading ?? chapter?.title
            chapters.append(Chapter(path: path, title: title ?? "Section \(chapters.count + 1)"))
        }
        guard !chapters.isEmpty else { throw EPUBError.invalidPublication }
        return Self(title: package.title, author: package.author, chapters: chapters)
    }

    private static func resolve(_ href: String, from parent: [String]) -> String? {
        guard let url = URLComponents(string: href), url.scheme == nil, url.host == nil,
              !url.path.hasPrefix("/"), !url.path.contains("\\"), !url.path.contains(":") else { return nil }
        var components = parent
        for component in url.path.split(separator: "/").map(String.init) {
            if component == ".." {
                guard !components.isEmpty else { return nil }
                components.removeLast()
            } else if component != "." {
                components.append(component)
            }
        }
        let path = components.joined(separator: "/")
        return EPUBArchive.safeComponents(path) == nil ? nil : path
    }

    private static func readXML(_ url: URL) throws -> EPUBXML {
        guard let parser = XMLParser(contentsOf: url) else { throw EPUBError.invalidPublication }
        let result = EPUBXML()
        parser.delegate = result
        parser.shouldProcessNamespaces = true
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse() else { throw EPUBError.invalidPublication }
        return result
    }
}

private final class EPUBXML: NSObject, XMLParserDelegate {
    var rootFile: String?
    var title: String?
    var author: String?
    var firstHeading: String?
    var manifest: [String: (href: String, mediaType: String)] = [:]
    var spine: [String] = []
    private var elements: [String] = []
    private var captured: (element: String, depth: Int, value: String)?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let parent = elements.last
        elements.append(elementName)
        switch (parent, elementName) {
        case ("rootfiles", "rootfile"):
            rootFile = rootFile ?? attributes["full-path"]
        case ("manifest", "item"):
            if let id = attributes["id"], let href = attributes["href"], let type = attributes["media-type"] {
                manifest[id] = (href, type)
            }
        case ("spine", "itemref"):
            if attributes["linear"] != "no", let id = attributes["idref"] { spine.append(id) }
        default:
            if captured == nil, (elementName == "title" || elementName == "creator" || elementName == "h1" || elementName == "h2") {
                captured = (elementName, elements.count, "")
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        captured?.value.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if let captured, captured.depth == elements.count {
            let value = captured.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                switch captured.element {
                case "title": title = title ?? value
                case "creator": author = author ?? value
                default: firstHeading = firstHeading ?? value
                }
            }
            self.captured = nil
        }
        _ = elements.popLast()
    }
}
