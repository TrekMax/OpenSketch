import Foundation
import OpenSketchCore
import Darwin

enum SketchFileInspector {
    static func inspect(_ url: URL) throws -> SketchMetadata {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 512 * 1024 * 1024 else { throw EditorError.invalid("Sketch 文件超过 512 MiB 或不是普通文件") }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-p", url.path, "meta.json"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); try? pipe.fileHandleForWriting.close()
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL); _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit(); try? pipe.fileHandleForReading.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(3)
        while true {
            guard Date() < deadline else { throw EditorError.invalid("Sketch 元数据读取超时") }
            let count = read(fd, &bytes, bytes.count)
            if count > 0 { guard data.count + count <= 1_048_576 else { throw EditorError.invalid("Sketch 元数据超过 1 MiB") }; data.append(contentsOf: bytes.prefix(count)) }
            else if count == 0 { break }
            else if errno == EAGAIN { Thread.sleep(forTimeInterval: 0.005) }
            else { throw EditorError.invalid("Sketch 元数据读取失败") }
        }
        while process.isRunning { guard Date() < deadline else { throw EditorError.invalid("Sketch 元数据读取超时") }; Thread.sleep(forTimeInterval: 0.005) }; process.waitUntilExit(); guard process.terminationStatus == 0 else { throw EditorError.invalid("无效 Sketch ZIP 或缺少 meta.json") }
        return try SketchMetadata.decode(data)
    }
}
