import Foundation
import Testing
@testable import OpenSketchCore

private func temporaryPackage() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".opensketch")
}

@Test func saveReopenPreservesEditableValuesAndAtomicReplacement() throws {
    let path = VectorPath(commands: [.move(to: CGPoint(x: 1, y: 2)),
        .cubic(control1: CGPoint(x: 10, y: 20), control2: CGPoint(x: 30, y: 40), to: CGPoint(x: 50, y: 60)), .close])
    let text = DesignNode(kind: .text, text: "中文 🧑‍🎨\n可编辑", fontName: "PingFang SC", fontSize: 18, textAlignment: .center)
    let curve = DesignNode(kind: .path, path: path)
    let frame = DesignNode(kind: .frame, rotation: 23, clipsContent: true, children: [text, curve])
    var document = DesignDocument(pages: [DesignPage(nodes: [frame])])
    let url = temporaryPackage()
    defer { try? FileManager.default.removeItem(at: url) }
    try DocumentCodec.save(document, to: url)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("document.json").path))
    #expect(try DocumentCodec.load(from: url) == document)
    document.name = "第二次保存"
    try DocumentCodec.save(document, to: url)
    #expect(try DocumentCodec.load(from: url) == document)
    #expect(try DocumentCodec.decode(DocumentCodec.encode(document)) == document)
}

@Test func rejectsNewerDocumentWithoutReplacingCurrentFile() throws {
    let original = DesignDocument()
    let url = temporaryPackage()
    defer { try? FileManager.default.removeItem(at: url) }
    try DocumentCodec.save(original, to: url)
    var future = original
    future.version = 99
    #expect(throws: DocumentCodecError.unsupportedVersion(99)) { try DocumentCodec.save(future, to: url) }
    #expect(try DocumentCodec.load(from: url) == original)
    let futureJSON = try JSONEncoder().encode(future)
    #expect(throws: DocumentCodecError.unsupportedVersion(99)) { try DocumentCodec.decode(futureJSON) }
}

@Test func rejectsDuplicateIDsAndNonFiniteGeometryBeforeReplacingPackage() throws {
    let original = DesignDocument()
    let url = temporaryPackage()
    defer { try? FileManager.default.removeItem(at: url) }
    try DocumentCodec.save(original, to: url)
    let child = DesignNode(kind: .rectangle)
    var duplicate = original
    duplicate.pages[0].nodes = [child, DesignNode(kind: .group, children: [child])]
    #expect(throws: (any Error).self) { try DocumentCodec.save(duplicate, to: url) }
    #expect(throws: (any Error).self) { try DocumentCodec.decode(JSONEncoder().encode(duplicate)) }
    var invalid = original
    invalid.pages[0].nodes = [DesignNode(kind: .rectangle, frame: CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10))]
    #expect(throws: (any Error).self) { try DocumentCodec.save(invalid, to: url) }
    invalid.pages[0].nodes[0].frame = CGRect(x: 0, y: 0, width: -1, height: 2)
    #expect(throws: (any Error).self) { try DocumentCodec.save(invalid, to: url) }
    #expect(try DocumentCodec.load(from: url) == original)
}

@Test func rejectsMalformedContentAndOutOfRangeFields() throws {
    let valid = DesignDocument()
    #expect(try DocumentCodec.decode(DocumentCodec.encode(valid)) == valid)
    for literal in ["{}", "[]", "not JSON", "{\"version\":1}"] {
        #expect(throws: (any Error).self) { try DocumentCodec.decode(Data(literal.utf8)) }
    }
    var document = DesignDocument(pages: [])
    #expect(throws: (any Error).self) { try DocumentCodec.encode(document) }
    document = DesignDocument()
    document.pages[0].nodes = [DesignNode(kind: .rectangle, style: NodeStyle(fill: RGBAColor(red: 2, green: 0, blue: 0)))]
    #expect(throws: (any Error).self) { try DocumentCodec.encode(document) }
    document.pages[0].nodes[0].style = NodeStyle()
    document.pages[0].nodes[0].rotation = .nan
    #expect(throws: (any Error).self) { try DocumentCodec.encode(document) }
    document.pages[0].nodes[0].rotation = 0
    document.pages[0].nodes[0].path.commands = [.line(to: .zero)] // Must start a subpath with move.
    #expect(throws: (any Error).self) { try DocumentCodec.encode(document) }
}

@Test func rejectsOversizedDataTreesAndText() throws {
    let valid = DesignDocument()
    #expect(try DocumentCodec.decode(DocumentCodec.encode(valid)) == valid)
    #expect(throws: (any Error).self) { try DocumentCodec.decode(Data(repeating: 32, count: DocumentCodec.maximumDataBytes + 1)) }
    var node = DesignNode(kind: .group)
    for _ in 0..<DocumentCodec.maximumDepth { node = DesignNode(kind: .group, children: [node]) }
    var document = DesignDocument(pages: [DesignPage(nodes: [node])])
    #expect(throws: (any Error).self) { try DocumentCodec.encode(document) }
    document.pages[0].nodes = [DesignNode(kind: .text, text: String(repeating: "a", count: DocumentCodec.maximumStringBytes + 1))]
    #expect(throws: (any Error).self) { try DocumentCodec.encode(document) }
    let deeplyNested = String(repeating: "[", count: 300) + "0" + String(repeating: "]", count: 300)
    #expect(throws: (any Error).self) { try DocumentCodec.decode(Data(deeplyNested.utf8)) }
}

@Test func sketch196MetadataKeepsFourIndependentFields() throws {
    let literal = #"{"version":196,"appVersion":"2025.2.2","build":20803,"compatibilityVersion":99,"pagesAndArtboards":{}}"#
    let metadata = try SketchMetadata.decode(Data(literal.utf8))
    #expect(metadata.version == 196)
    #expect(metadata.appVersion == "2025.2.2")
    #expect(metadata.build == 20803)
    #expect(metadata.compatibilityVersion == 99)
    #expect(throws: (any Error).self) { try SketchMetadata.decode(Data(#"{"version":196}"#.utf8)) }
}

@Test func explicitPageNodeAndPathCountLimitsAreEnforced() throws {
    let pages = (0...DocumentCodec.maximumPageCount).map { _ in DesignPage() }
    #expect(throws: DocumentCodecError.limitExceeded("pageCount")) {
        try DocumentCodec.encode(DesignDocument(pages: pages))
    }
    let nodes = (0...DocumentCodec.maximumNodeCount).map { _ in DesignNode(kind: .rectangle) }
    #expect(throws: DocumentCodecError.limitExceeded("nodeCount")) {
        try DocumentCodec.encode(DesignDocument(pages: [DesignPage(nodes: nodes)]))
    }
    let path = VectorPath(commands: Array(repeating: .move(to: .zero), count: DocumentCodec.maximumPathCommands + 1))
    #expect(throws: DocumentCodecError.limitExceeded("pathCommands")) {
        try DocumentCodec.encode(DesignDocument(pages: [DesignPage(nodes: [DesignNode(kind: .path, path: path)])]))
    }
}

@Test func depthLimitIsCheckedOnDecodeAndStringsDoNotCountAsJSONNesting() throws {
    var node = DesignNode(kind: .group)
    for _ in 0..<DocumentCodec.maximumDepth { node = DesignNode(kind: .group, children: [node]) }
    let deep = DesignDocument(pages: [DesignPage(nodes: [node])])
    #expect(throws: DocumentCodecError.limitExceeded("nodeDepth")) {
        try DocumentCodec.decode(JSONEncoder().encode(deep))
    }
    let brackets = String(repeating: "[{\\\"", count: 500)
    let valid = DesignDocument(name: brackets)
    #expect(try DocumentCodec.decode(DocumentCodec.encode(valid)) == valid)
}

@Test func packageLoadRejectsOversizedAndSymbolicJSONFiles() throws {
    let original = DesignDocument()
    let url = temporaryPackage()
    let external = temporaryPackage()
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: external)
    }
    try DocumentCodec.save(original, to: url)
    let jsonURL = url.appendingPathComponent("document.json")
    let handle = try FileHandle(forWritingTo: jsonURL)
    try handle.truncate(atOffset: UInt64(DocumentCodec.maximumDataBytes + 1))
    try handle.close()
    #expect(throws: DocumentCodecError.limitExceeded("dataBytes")) { try DocumentCodec.load(from: url) }
    try DocumentCodec.save(original, to: external)
    try FileManager.default.removeItem(at: jsonURL)
    try FileManager.default.createSymbolicLink(at: jsonURL, withDestinationURL: external.appendingPathComponent("document.json"))
    #expect(throws: DocumentCodecError.invalidContent("documentJSONFile")) { try DocumentCodec.load(from: url) }
    #expect(try DocumentCodec.load(from: external) == original)
}
