// SPDX-License-Identifier: MIT
import Foundation

enum BluetoothProtocol {
    static let serviceUUID = "8B7F9B20-6F06-4E8C-BC17-41F136C1A100"
    static let controlUUID = "8B7F9B20-6F06-4E8C-BC17-41F136C1A101"
    static let profiles = ["stock": 0, "responsive": 1, "fast": 2]

    static func command(_ args: [String]) throws -> Data? {
        func invalid() -> NSError {
            NSError(domain: "KeychronBluetooth", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: usage])
        }
        guard let first = args.first else { throw invalid() }
        switch first {
        case "status" where args.count == 1:
            return nil
        case "debounce" where args.count == 3:
            guard let press = UInt8(args[1]), let release = UInt8(args[2]),
                  press <= 50, (1...50).contains(release) else { throw invalid() }
            return Data([1, 1, press, release])
        case "profile" where args.count == 2:
            guard let profile = profiles[args[1]] else { throw invalid() }
            return Data([1, 2, UInt8(profile)])
        case "custom" where args.count == 5:
            guard let minMS = Double(args[1]), let maxMS = Double(args[2]),
                  let latency = UInt16(args[3]), let timeoutMS = Double(args[4]),
                  minMS.isFinite, maxMS.isFinite, timeoutMS.isFinite,
                  minMS >= 7.5, maxMS <= 50, minMS <= maxMS,
                  latency <= 30, (2000...6000).contains(timeoutMS),
                  (minMS / 1.25).rounded() == minMS / 1.25,
                  (maxMS / 1.25).rounded() == maxMS / 1.25,
                  (timeoutMS / 10).rounded() == timeoutMS / 10,
                  timeoutMS > maxMS * Double(latency + 1) * 2 else { throw invalid() }
            var bytes: [UInt8] = [1, 3]
            for value in [UInt16(minMS / 1.25), UInt16(maxMS / 1.25), latency,
                          UInt16(timeoutMS / 10)] {
                bytes += [UInt8(value & 255), UInt8(value >> 8)]
            }
            return Data(bytes)
        default:
            throw invalid()
        }
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        let b = Array(data)
        guard b.count == 24, b[0] == 1, b[4] <= 3 else {
            throw NSError(domain: "KeychronBluetooth", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported Bluetooth settings response"])
        }
        func u16(_ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }
        let names = ["stock", "responsive", "fast", "custom"]
        return [
            "protocol": 1, "profile": names[Int(b[4])],
            "debounce_press_ms": Int(b[2]), "debounce_release_ms": Int(b[3]),
            "encrypted": b[5] & 1 != 0, "active_bonded_host": b[5] & 2 != 0,
            "timing_save_pending": b[5] & 4 != 0,
            "negotiated_timing_matches_request": b[5] & 8 != 0,
            "requested": ["min_interval_ms": Double(u16(6)) * 1.25,
                          "max_interval_ms": Double(u16(8)) * 1.25,
                          "peripheral_latency": u16(10), "timeout_ms": u16(12) * 10],
            "negotiated": ["interval_ms": Double(u16(14)) * 1.25,
                           "peripheral_latency": u16(16), "timeout_ms": u16(18) * 10],
            "parameter_submission_result": Int(Int16(bitPattern: UInt16(u16(20)))),
            "timing_save_result": Int(Int16(bitPattern: UInt16(u16(22)))),
        ]
    }

    static let usage = """
    Usage: keychron-bluetooth [--device MACOS-PERIPHERAL-UUID] status
           keychron-bluetooth [--device UUID] debounce PRESS_MS RELEASE_MS
           keychron-bluetooth [--device UUID] profile stock|responsive|fast
           keychron-bluetooth [--device UUID] custom MIN_MS MAX_MS LATENCY TIMEOUT_MS
    Custom intervals: 7.5–50 ms in 1.25 ms steps; timeout: 2000–6000 ms in 10 ms steps.
    The host chooses the negotiated connection timing. These are requests, not polling-rate guarantees.
    """
}
