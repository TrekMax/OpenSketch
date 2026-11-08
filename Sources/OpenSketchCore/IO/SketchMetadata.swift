import Foundation

/// Metadata inspection only; this is not an editable Sketch importer.
public struct SketchMetadata: Codable, Equatable, Sendable {
    public var version: Int
    public var appVersion: String
    public var build: Int
    public var compatibilityVersion: Int
    public static func decode(_ data: Data) throws -> Self {
        try DocumentCodec.checkJSONEnvelope(data, maximumBytes: 1024 * 1024)
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version >= 0, result.build >= 0, result.compatibilityVersion >= 0,
              !result.appVersion.isEmpty, result.appVersion.utf8.count <= 256 else {
            throw DocumentCodecError.invalidContent("SketchMetadata")
        }
        return result
    }
}
