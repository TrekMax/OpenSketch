import Foundation

public enum DocumentCodecError: Error, Equatable {
    case unsupportedFormat, unsupportedVersion(Int), invalidContent(String), limitExceeded(String)
}

public enum DocumentCodec {
    public static let maximumDataBytes = 16 * 1024 * 1024
    public static let maximumNodeCount = 50_000
    public static let maximumDepth = 64
    public static let maximumPathCommands = 200_000
    public static let maximumPageCount = 128
    public static let maximumStringBytes = 1024 * 1024
    public static func encode(_ document: DesignDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumDataBytes else { throw DocumentCodecError.limitExceeded("dataBytes") }
        return data
    }

    public static func decode(_ data: Data) throws -> DesignDocument {
        try checkJSONEnvelope(data, maximumBytes: maximumDataBytes)
        let document = try JSONDecoder().decode(DesignDocument.self, from: data)
        try validate(document)
        return document
    }

    /// Validates and encodes before touching the destination. FileWrapper's atomic
    /// write creates a sibling temporary package and replaces the old package.
    public static func save(_ document: DesignDocument, to url: URL) throws {
        let data = try encode(document)
        guard url.isFileURL else { throw DocumentCodecError.invalidContent("fileURL") }
        let package = FileWrapper(directoryWithFileWrappers: ["document.json": FileWrapper(regularFileWithContents: data)])
        try package.write(to: url, options: .atomic, originalContentsURL: nil)
    }

    public static func load(from url: URL) throws -> DesignDocument {
        guard url.isFileURL else { throw DocumentCodecError.invalidContent("fileURL") }
        let packageInfo = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard packageInfo.isDirectory == true, packageInfo.isSymbolicLink != true else {
            throw DocumentCodecError.invalidContent("packageDirectory")
        }
        let jsonURL = url.appendingPathComponent("document.json", isDirectory: false)
        let info = try jsonURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else {
            throw DocumentCodecError.invalidContent("documentJSONFile")
        }
        guard let size = info.fileSize, size <= maximumDataBytes else {
            throw DocumentCodecError.limitExceeded("dataBytes")
        }
        // Bounded streaming also enforces the limit if the file grows after stat.
        let handle = try FileHandle(forReadingFrom: jsonURL)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count + chunk.count <= maximumDataBytes else {
                throw DocumentCodecError.limitExceeded("dataBytes")
            }
            data.append(chunk)
        }
        return try decode(data)
    }

    /// Prevents pathological decoder recursion before recursive Codable decoding.
    /// Quotes and escaped quotes are tracked so braces in user text do not count.
    static func checkJSONEnvelope(_ data: Data, maximumBytes: Int) throws {
        guard data.count <= maximumBytes else { throw DocumentCodecError.limitExceeded("dataBytes") }
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else {
                switch byte {
                case 34: quoted = true
                case 91, 123:
                    depth += 1
                    guard depth <= maximumDepth * 3 + 16 else {
                        throw DocumentCodecError.limitExceeded("JSONNesting")
                    }
                case 93, 125: depth -= 1
                default: break
                }
            }
        }
        // JSONDecoder remains responsible for grammar and matching delimiters.
    }

    private static func validate(_ document: DesignDocument) throws {
        guard document.format == DesignDocument.formatIdentifier else { throw DocumentCodecError.unsupportedFormat }
        guard document.version == DesignDocument.currentVersion else {
            throw DocumentCodecError.unsupportedVersion(document.version)
        }
        guard !document.pages.isEmpty else { throw DocumentCodecError.invalidContent("emptyPages") }
        guard document.pages.count <= maximumPageCount else { throw DocumentCodecError.limitExceeded("pageCount") }
        var ids = Set<UUID>()
        var nodeCount = 0
        var commandCount = 0

        func unique(_ id: UUID) throws {
            guard ids.insert(id).inserted else { throw DocumentCodecError.invalidContent("duplicateID") }
        }
        func string(_ text: String) throws {
            guard text.utf8.count <= maximumStringBytes else { throw DocumentCodecError.limitExceeded("stringBytes") }
        }
        func number(_ value: Double, in range: ClosedRange<Double>, field: String) throws {
            guard value.isFinite, range.contains(value) else { throw DocumentCodecError.invalidContent(field) }
        }
        func point(_ point: CGPoint) throws {
            try number(point.x, in: -1e9...1e9, field: "point")
            try number(point.y, in: -1e9...1e9, field: "point")
        }
        func color(_ color: RGBAColor?) throws {
            guard let color else { return }
            for value in [color.red, color.green, color.blue, color.alpha] {
                try number(value, in: 0...1, field: "color")
            }
        }
        func gradient(_ gradient: LinearGradient?) throws {
            guard let gradient else { return }
            try point(gradient.start); try point(gradient.end)
            guard !gradient.stops.isEmpty, gradient.stops.count <= 64 else {
                throw DocumentCodecError.invalidContent("gradientStops")
            }
            var previous = -Double.infinity
            for stop in gradient.stops {
                try number(stop.position, in: 0...1, field: "gradientPosition")
                guard stop.position >= previous else {
                    throw DocumentCodecError.invalidContent("gradientOrder")
                }
                previous = stop.position
                try color(stop.color)
            }
        }
        func path(_ path: VectorPath) throws {
            commandCount += path.commands.count
            guard commandCount <= maximumPathCommands else { throw DocumentCodecError.limitExceeded("pathCommands") }
            var hasSubpath = false
            for command in path.commands {
                switch command {
                case .move(let destination):
                    try point(destination)
                    hasSubpath = true
                case .line(let destination):
                    guard hasSubpath else { throw DocumentCodecError.invalidContent("pathSequence") }
                    try point(destination)
                case .cubic(let first, let second, let destination):
                    guard hasSubpath else { throw DocumentCodecError.invalidContent("pathSequence") }
                    try point(first); try point(second); try point(destination)
                case .close:
                    guard hasSubpath else { throw DocumentCodecError.invalidContent("pathSequence") }
                    hasSubpath = false
                }
            }
        }
        func validateNodes(_ nodes: [DesignNode], depth: Int) throws {
            guard depth <= maximumDepth else { throw DocumentCodecError.limitExceeded("nodeDepth") }
            for node in nodes {
                nodeCount += 1
                guard nodeCount <= maximumNodeCount else { throw DocumentCodecError.limitExceeded("nodeCount") }
                try unique(node.id)
                try string(node.name); try string(node.text); try string(node.fontName)
                try point(node.frame.origin)
                try number(node.frame.size.width, in: 0...1e7, field: "nodeSize")
                try number(node.frame.size.height, in: 0...1e7, field: "nodeSize")
                try number(node.rotation, in: -1e9...1e9, field: "rotation")
                try number(node.fontSize, in: 0.1...1e5, field: "fontSize")
                try color(node.style.fill); try color(node.style.stroke)
                try gradient(node.style.linearGradient)
                try number(node.style.strokeWidth, in: 0...1e5, field: "strokeWidth")
                try number(node.style.cornerRadius, in: 0...1e7, field: "cornerRadius")
                try number(node.style.opacity, in: 0...1, field: "opacity")
                try path(node.path)
                guard node.children.isEmpty || node.kind == .frame || node.kind == .group else {
                    throw DocumentCodecError.invalidContent("leafChildren")
                }
                if !node.children.isEmpty { try validateNodes(node.children, depth: depth + 1) }
            }
        }
        try unique(document.id)
        try string(document.name)
        for page in document.pages {
            try unique(page.id)
            try string(page.name)
            try number(page.size.width, in: 0.1...1e7, field: "pageSize")
            try number(page.size.height, in: 0.1...1e7, field: "pageSize")
            try validateNodes(page.nodes, depth: 1)
        }
    }
}
