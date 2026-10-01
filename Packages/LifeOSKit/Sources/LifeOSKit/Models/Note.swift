import Foundation

/// `POST /api/v1/notes` for quick capture: a title and plain text, sent as a
/// one-paragraph TipTap document like the web editor stores it.
public struct NewNote: Encodable, Sendable {
    public var title: String?
    public var body: String

    public init(title: String?, body: String) {
        self.title = title
        self.body = body
    }

    private enum CodingKeys: String, CodingKey { case title, contentJson }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(TipTapDoc(text: body), forKey: .contentJson)
    }
}

/// The parts of a saved note quick capture needs.
public struct CreatedNote: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String?
}

struct TipTapDoc: Encodable {
    struct Node: Encodable {
        let type: String
        let text: String?
        let content: [Node]?
    }

    let type = "doc"
    let content: [Node]

    init(text: String) {
        let paragraphs = text.components(separatedBy: "\n")
        content = paragraphs.map { line in
            Node(type: "paragraph", text: nil, content: line.isEmpty ? nil : [Node(type: "text", text: line, content: nil)])
        }
    }
}
