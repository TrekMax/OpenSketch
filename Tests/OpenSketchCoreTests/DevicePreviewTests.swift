import Foundation
import Testing
@testable import OpenSketchCore

struct DevicePreviewTests {
    @Test func localBackendConnectsAndSyncsSnapshots() async throws {
        let device = PreviewDevice(name: "Local Preview", size: CGSize(width: 390, height: 844))
        let backend = LocalDevicePreviewBackend(devices: [device])
        #expect(await backend.discover() == [device])
        do {
            _ = try await backend.sync(DevicePreviewSnapshot(documentID: UUID(), page: DesignPage()), to: device.id)
            Issue.record("An offline device accepted a snapshot")
        } catch PluginDeviceError.notConnected {
            // Expected until the local preview is connected.
        }
        _ = try await backend.connect(device.id)
        let snapshot = DevicePreviewSnapshot(documentID: UUID(), page: DesignPage(name: "Home"))
        let status = try await backend.sync(snapshot, to: device.id)
        #expect(status.state == .connected)
        #expect(await backend.snapshot(device.id) == snapshot)
    }
}
