// SPDX-License-Identifier: MIT
import Foundation
import CoreBluetooth
import Darwin

final class BluetoothController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var control: CBCharacteristic?
    private var hasWritten = false
    private var finished = false
    private let payload: Data?
    private let identifier: UUID?
    private let expectedName = "Keychron K1 Ultra 8K"

    init(payload: Data?, identifier: UUID?) {
        self.payload = payload
        self.identifier = identifier
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.fail("Timed out. The keyboard must be in Bluetooth mode, paired to this Mac, " +
                       "and running the custom Bluetooth-controls firmware.")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state == .unauthorized {
                fail("Bluetooth permission is required for this local utility.")
            } else if central.state == .poweredOff || central.state == .unsupported {
                fail("Bluetooth is unavailable or switched off.")
            }
            return
        }
        if let id = identifier,
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
            return
        }
        let connected = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1812")])
            .filter { matches($0) }
        if connected.count > 1 {
            fail("Multiple matching keyboards are connected. Select one with --device UUID.")
        } else if let keyboard = connected.first {
            connect(keyboard)
        } else {
            central.scanForPeripherals(withServices: [CBUUID(string: "1812")])
        }
    }

    private func matches(_ peripheral: CBPeripheral) -> Bool {
        if let id = identifier { return peripheral.identifier == id }
        return peripheral.name == expectedName
    }

    private func connect(_ keyboard: CBPeripheral) {
        guard peripheral == nil else { return }
        central.stopScan()
        peripheral = keyboard
        keyboard.delegate = self
        central.connect(keyboard)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if matches(peripheral) { connect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: BluetoothProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        fail(error?.localizedDescription ?? "Bluetooth connection failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if !finished { fail(error?.localizedDescription ?? "Keyboard disconnected") }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail(error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == CBUUID(string: BluetoothProtocol.serviceUUID)
        }) else {
            fail("The Bluetooth-controls service is absent. Stock firmware does not support it.")
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: BluetoothProtocol.controlUUID)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error { fail(error.localizedDescription); return }
        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == CBUUID(string: BluetoothProtocol.controlUUID)
        }) else { fail("Bluetooth control characteristic is missing"); return }
        control = characteristic
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { fail(error.localizedDescription); return }
        do {
            guard let bytes = characteristic.value else { fail("Empty response"); return }
            var status = try BluetoothProtocol.decode(bytes)
            guard status["encrypted"] as? Bool == true,
                  status["active_bonded_host"] as? Bool == true else {
                fail("The keyboard has not authorized this paired host")
                return
            }
            if let payload, !hasWritten {
                hasWritten = true
                peripheral.writeValue(payload, for: characteristic, type: .withResponse)
                return
            }
            if let payload, hasWritten {
                let command = Array(payload)
                let response = Array(bytes)
                let matches: Bool
                switch command[1] {
                case 1:
                    matches = response[2] == command[2] && response[3] == command[3]
                case 2:
                    matches = response[4] == command[2]
                case 3:
                    matches = response[4] == 3 &&
                        Array(response[6..<14]) == Array(command[2..<10])
                default:
                    matches = false
                }
                guard matches else { fail("Setting write did not match the device readback"); return }
                if command[1] != 1 && status["timing_save_pending"] as? Bool == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self, !self.finished else { return }
                        peripheral.readValue(for: characteristic)
                    }
                    return
                }
                if command[1] != 1 && status["timing_save_result"] as? Int != 0 {
                    fail("Timing setting applied in memory but could not be saved")
                    return
                }
            }
            status["device_uuid"] = peripheral.identifier.uuidString
            status["device_name"] = peripheral.name ?? expectedName
            let result = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
            finished = true
            central.cancelPeripheralConnection(peripheral)
            print(String(decoding: result, as: UTF8.self))
            exit(0)
        } catch { fail(error.localizedDescription) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error { fail(error.localizedDescription); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.finished else { return }
            peripheral.readValue(for: characteristic)
        }
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

@main
enum Main {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        var device: UUID?
        if args.first == "--device" {
            guard args.count >= 3, let id = UUID(uuidString: args[1]) else {
                fputs(BluetoothProtocol.usage + "\n", stderr); exit(2)
            }
            device = id
            args.removeFirst(2)
        }
        if args.isEmpty || args == ["--help"] {
            print(BluetoothProtocol.usage)
            return
        }
        do {
            let controller = BluetoothController(payload: try BluetoothProtocol.command(args), identifier: device)
            withExtendedLifetime(controller) { RunLoop.main.run() }
        } catch {
            fputs(error.localizedDescription + "\n", stderr)
            exit(2)
        }
    }
}
