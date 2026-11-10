import Foundation

/// A deterministic local preview backend. It models the lifecycle an external
/// device plugin will use, while keeping the first backend offline.
public actor LocalDevicePreviewBackend {
    private var statuses: [UUID: DevicePreviewStatus] = [:]
    private var snapshots: [UUID: DevicePreviewSnapshot] = [:]

    public init(devices: [PreviewDevice] = []) {
        for device in devices { statuses[device.id] = DevicePreviewStatus(device: device) }
    }

    public func discover() -> [PreviewDevice] { statuses.values.map(\.device).sorted { $0.name < $1.name } }

    public func connect(_ id: UUID) throws -> DevicePreviewStatus {
        try Task.checkCancellation()
        guard var status = statuses[id] else { throw PluginDeviceError.deviceNotFound }
        status.state = .connected; status.device.isConnected = true; status.message = nil; statuses[id] = status
        return status
    }

    public func disconnect(_ id: UUID) {
        guard var status = statuses[id] else { return }
        status.state = .disconnected; status.device.isConnected = false; statuses[id] = status
    }

    public func sync(_ snapshot: DevicePreviewSnapshot, to id: UUID) throws -> DevicePreviewStatus {
        try Task.checkCancellation()
        guard var status = statuses[id] else { throw PluginDeviceError.deviceNotFound }
        guard status.device.isConnected else { throw PluginDeviceError.notConnected }
        status.state = .syncing; statuses[id] = status
        snapshots[id] = snapshot
        status.state = .connected; status.lastRevision = snapshot.revision; statuses[id] = status
        return status
    }

    public func status(_ id: UUID) -> DevicePreviewStatus? { statuses[id] }
    public func snapshot(_ id: UUID) -> DevicePreviewSnapshot? { snapshots[id] }
}

public enum PluginDeviceError: Error, Equatable, Sendable { case deviceNotFound, notConnected }
