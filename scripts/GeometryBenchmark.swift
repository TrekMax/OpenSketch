import Foundation
import CoreGraphics

/// Standalone Release geometry probe; compiled together with the unmodified core.
@main
struct GeometryBenchmark {
    static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw NSError(domain: "GeometryBenchmark", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Environment command failed: \(executable)"])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Expected compiler target")
        let environment: [String: Any] = [
            "macOS": try command("/usr/bin/sw_vers", []),
            "architecture": try command("/usr/bin/uname", ["-m"]),
            "machine": try command("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]),
            "memoryBytes": try command("/usr/sbin/sysctl", ["-n", "hw.memsize"]),
            "xcode": try command("/usr/bin/xcodebuild", ["-version"]),
            "swift": try command("/usr/bin/xcrun", ["swiftc", "--version"])
        ]
        let warmupBatches = 3
        let measuredBatches = 20
        var rows: [[String: Any]] = []
        for count in [1_000, 10_000] {
            let nodes = (0..<count).map { index in
                DesignNode(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                           kind: .rectangle,
                           frame: CGRect(x: (index % 100) * 30, y: (index / 100) * 24, width: 20, height: 16),
                           rotation: index % 3 == 1 ? 15 : 0)
            }
            let page = DesignPage(nodes: nodes)
            let queries: [(CGPoint, UUID?)] = (0..<100).map { index in
                if index % 4 == 0 { return (CGPoint(x: -1_000, y: -1_000), nil) }
                let node = nodes[(index * 97) % count]
                return (CGPoint(x: node.frame.midX, y: node.frame.midY), node.id)
            }
            var times: [Double] = []
            var verifiedHits = 0
            for pass in 0..<(warmupBatches + measuredBatches) {
                let start = DispatchTime.now().uptimeNanoseconds
                for (point, expected) in queries {
                    let actual = SceneGeometry.hitTest(point, in: page)
                    precondition(actual == expected, "Incorrect hit ID at \(point)")
                    if actual != nil { verifiedHits += 1 }
                }
                let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if pass >= warmupBatches { times.append(milliseconds) }
            }
            precondition(verifiedHits == (warmupBatches + measuredBatches) * 75)
            let sorted = times.sorted()
            rows.append([
                "nodes": count, "queriesPerBatch": 100, "hitsPerBatch": 75, "missesPerBatch": 25,
                "warmupBatches": warmupBatches, "measuredBatches": measuredBatches,
                "medianBatchMilliseconds": (sorted[9] + sorted[10]) / 2,
                "p95BatchMilliseconds": sorted[18], "verifiedHitsIncludingWarmup": verifiedHits,
                "measuredBatchMilliseconds": times
            ])
        }
        let result: [String: Any] = [
            "environment": environment, "compilerTarget": CommandLine.arguments[1],
            "optimization": "-swift-version 6 -O -whole-module-optimization",
            "clock": "DispatchTime.uptimeNanoseconds (monotonic)",
            "workload": "Flat 100-column grid of 20x16 rectangles, spacing 30x24; index%3==1 rotates 15 degrees; query i%4==0 misses at (-1000,-1000), otherwise hits center of node (i*97)%count",
            "timingScope": "100 sequential SceneGeometry.hitTest calls per batch, including expected ID assertions and hit counting; excludes scene construction, environment collection, JSON encoding, rendering and UI",
            "percentiles": "median is mean of sorted samples 10 and 11; p95 is nearest rank ceil(0.95*20), sample 19",
            "results": rows
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
