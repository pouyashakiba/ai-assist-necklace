import Foundation
@preconcurrency import CoreBluetooth
import Combine

struct PendantDiscovery: Identifiable {
    let peripheral: CBPeripheral
    let rssi: Int
    var id: UUID { peripheral.identifier }
    var name: String { peripheral.name ?? "Little Companion" }
}

@MainActor final class PendantLink: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "6E8F0001-3F2A-4D7B-9C10-4A434F4D5041")
    static let controlID = CBUUID(string: "6E8F0002-3F2A-4D7B-9C10-4A434F4D5041")
    static let eventID = CBUUID(string: "6E8F0003-3F2A-4D7B-9C10-4A434F4D5041")
    static let audioInID = CBUUID(string: "6E8F0004-3F2A-4D7B-9C10-4A434F4D5041")
    static let audioOutID = CBUUID(string: "6E8F0005-3F2A-4D7B-9C10-4A434F4D5041")
    @Published private(set) var devices: [PendantDiscovery] = []
    @Published private(set) var connected = false
    @Published private(set) var scanning = false
    @Published private(set) var hardwareAudio = false
    @Published var status = "Not connected"
    var onWake: (() -> Void)?
    var onText: ((String, String) -> Bool)?
    var onPCM: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onPlaybackFinished: (() -> Void)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var control: CBCharacteristic?
    private var audioInput: CBCharacteristic?
    private var notifications = Set<CBUUID>()
    private var eventBuffer = Data()
    private var assembler = PCMAssembler()
    private var pendingWrite: CheckedContinuation<Void, Error>?
    private var writeID = UUID()
    private var awaitingReady: CheckedContinuation<Void, Error>?
    private var readyID = UUID()
    private var scanningTimeout: Task<Void, Never>?
    private var controlBusy = false
    private var seenRequests = UserDefaults.standard.stringArray(forKey: "pendant.acceptedRequests") ?? []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "LittleCompanion.Pendant"])
    }

    func scan() {
        guard central.state == .poweredOn else { status = "Enable Bluetooth and allow access in Settings."; return }
        devices.removeAll(); scanning = true; status = "Looking for your pendant…"
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanningTimeout?.cancel()
        scanningTimeout = Task { [weak self] in try? await Task.sleep(for: .seconds(12)); guard !Task.isCancelled else { return }; self?.stopScan() }
    }
    func stopScan() { central.stopScan(); scanning = false; scanningTimeout?.cancel(); if peripheral == nil { status = devices.isEmpty ? "No pendant found. Check power and firmware." : "Choose your pendant." } }
    func connect(_ discovery: PendantDiscovery) {
        stopScan(); peripheral = discovery.peripheral; peripheral?.delegate = self; status = "Connecting…"; central.connect(discovery.peripheral)
    }
    func disconnect() { if let peripheral { central.cancelPeripheralConnection(peripheral) }; reset("Not connected") }
    private func reset(_ message: String) {
        connected = false; hardwareAudio = false; control = nil; audioInput = nil; notifications.removeAll(); eventBuffer.removeAll()
        pendingWrite?.resume(throwing: CompanionError.disconnected); pendingWrite = nil
        awaitingReady?.resume(throwing: CompanionError.disconnected); awaitingReady = nil
        status = message
    }

    func setFace(_ mood: FaceMood) { Task { try? await command(["op": "face", "value": mood.rawValue]) } }
    func requestCapture() async throws {
        guard hardwareAudio else { throw CompanionError.unavailable("The pendant has no enabled I2S microphone. Use the iPhone microphone for now.") }
        try await command(["op": "capture", "ms": 3000])
    }
    func enableHardware(_ enabled: Bool) async throws { try await command(["op": "hardware", "enabled": enabled]) }
    func stopPlayback() { Task { try? await command(["op": "stop"]) } }
    func sendReply(_ text: String, requestID: String, mood: FaceMood) async throws { try await command(["op": "reply", "id": requestID, "text": String(text.prefix(1800)), "face": mood.rawValue]) }

    func command(_ payload: [String: Any]) async throws {
        while controlBusy { try await Task.sleep(for: .milliseconds(10)); try Task.checkCancellation() }
        guard connected, let control, let peripheral else { throw CompanionError.disconnected }
        controlBusy = true; defer { controlBusy = false }
        var bytes = try JSONSerialization.data(withJSONObject: payload); bytes.append(10)
        guard bytes.count <= 4096 else { throw CompanionError.unavailable("Pendant command is too long.") }
        let capacity = max(1, min(180, peripheral.maximumWriteValueLength(for: .withResponse)))
        for offset in stride(from: 0, to: bytes.count, by: capacity) { try await write(bytes.subdata(in: offset..<min(offset+capacity, bytes.count)), to: control) }
    }
    private func write(_ data: Data, to characteristic: CBCharacteristic) async throws {
        guard let peripheral, peripheral.state == .connected else { throw CompanionError.disconnected }
        while pendingWrite != nil { try await Task.sleep(for: .milliseconds(10)); try Task.checkCancellation() }
        guard peripheral.state == .connected else { throw CompanionError.disconnected }
        let id = UUID(); writeID = id
        try await withCheckedThrowingContinuation { continuation in
            pendingWrite = continuation
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.writeID == id, self.pendingWrite != nil else { return }
                self.disconnect(); self.onError?("Bluetooth transfer timed out. Reconnect the pendant.")
            }
        }
    }

    func play(pcm: Data) async throws {
        guard hardwareAudio, let peripheral, let audioInput, pcm.count > 0, pcm.count <= 2_000_000, pcm.count % 2 == 0 else { throw CompanionError.unavailable("Pendant audio isn't ready, or this reply is too long. Choose the iPhone speaker.") }
        let id = UUID(); readyID = id
        try await withCheckedThrowingContinuation { continuation in
            awaitingReady = continuation
            Task { [weak self] in
                guard let self else { return }
                do { try await self.command(["op": "audio_start", "bytes": pcm.count]) }
                catch { self.awaitingReady?.resume(throwing: error); self.awaitingReady = nil }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.readyID == id, let pending = self.awaitingReady else { return }
                self.awaitingReady = nil; pending.resume(throwing: CompanionError.unavailable("The pendant didn't prepare its audio buffer."))
            }
        }
        let capacity = min(180, peripheral.maximumWriteValueLength(for: .withResponse)) - 2
        guard capacity > 0 else { throw CompanionError.disconnected }
        var sequence: UInt16 = 0
        for offset in stride(from: 0, to: pcm.count, by: capacity) {
            try Task.checkCancellation()
            var packet = Data([UInt8(sequence & 255), UInt8(sequence >> 8)])
            packet.append(pcm.subdata(in: offset..<min(offset + capacity, pcm.count)))
            try await write(packet, to: audioInput); sequence &+= 1
        }
        try await command(["op": "audio_commit"])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { reset("Bluetooth is unavailable or permission was denied.") }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !devices.contains(where: { $0.id == peripheral.identifier }) else { return }
        devices.append(PendantDiscovery(peripheral: peripheral, rssi: RSSI.intValue))
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.peripheral = peripheral; peripheral.delegate = self; status = "Preparing secure Bluetooth link…"; peripheral.discoverServices([Self.service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { self.peripheral = nil; reset("Connection failed. Try again.") }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { self.peripheral = nil; reset("Pendant disconnected"); onError?("Pendant disconnected. iPhone conversation is still available.") }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let device = restored.first {
            peripheral = device; device.delegate = self
            if device.state == .connected { device.discoverServices([Self.service]) }
            else { central.connect(device) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { status = "Companion service not found. Update pendant firmware."; return }
        peripheral.discoverCharacteristics([Self.controlID, Self.eventID, Self.audioInID, Self.audioOutID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { status = "Couldn't discover pendant controls."; return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.controlID: control = characteristic
            case Self.audioInID: audioInput = characteristic
            case Self.eventID, Self.audioOutID: peripheral.setNotifyValue(true, for: characteristic)
            default: break
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else { status = "Bluetooth notifications failed. Pair and reconnect."; return }
        notifications.insert(characteristic.uuid)
        if notifications.contains(Self.eventID), notifications.contains(Self.audioOutID), control != nil, !connected {
            connected = true; status = "Connected"; Task { try? await command(["op": "status"]) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, let continuation = pendingWrite else { return }
        pendingWrite = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == Self.audioOutID {
            do { try assembler.append(data) } catch { onError?(error.localizedDescription) }
            return
        }
        guard characteristic.uuid == Self.eventID else { return }
        eventBuffer.append(data)
        if eventBuffer.count > 8192 { eventBuffer.removeAll(); onError?("Invalid Bluetooth event frame."); return }
        while let end = eventBuffer.firstIndex(of: 10) {
            let line = eventBuffer.prefix(upTo: end); eventBuffer.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = value["type"] as? String else { continue }
            switch type {
            case "status": hardwareAudio = value["hardware_audio"] as? Bool ?? false; status = "Connected · LCD off"
            case "wake": onWake?()
            case "text":
                guard let text = value["text"] as? String, let id = value["id"] as? String, !text.isEmpty else { continue }
                if seenRequests.contains(id) { Task { try? await command(["op": "text_ack", "id": id]) }; continue }
                if onText?(text, id) == true {
                    seenRequests.append(id); seenRequests = Array(seenRequests.suffix(64)); UserDefaults.standard.set(seenRequests, forKey: "pendant.acceptedRequests")
                    Task { try? await command(["op": "text_ack", "id": id]) }
                }
            case "audio_ready": let pending = awaitingReady; awaitingReady = nil; pending?.resume()
            case "audio_begin": do { try assembler.begin(bytes: value["bytes"] as? Int ?? 0) } catch { onError?(error.localizedDescription) }
            case "audio_end": do { onPCM?(try assembler.finish()) } catch { onError?(error.localizedDescription) }
            case "playback_end": onPlaybackFinished?()
            case "error":
                let message = value["message"] as? String ?? "Pendant operation failed."
                awaitingReady?.resume(throwing: CompanionError.unavailable(message)); awaitingReady = nil; onError?(message)
            default: break
            }
        }
    }
}
