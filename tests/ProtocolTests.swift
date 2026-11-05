// SPDX-License-Identifier: MIT
import Foundation

@main
enum ProtocolTests {
    static func main() throws {
        func check(_ condition: Bool) { assert(condition) }
        check(try BluetoothProtocol.command(["status"]) == nil)
        check(try BluetoothProtocol.command(["debounce", "0", "10"]) == Data([1, 1, 0, 10]))
        check(try BluetoothProtocol.command(["profile", "responsive"]) == Data([1, 2, 1]))
        check(try BluetoothProtocol.command(["custom", "7.5", "15", "0", "4000"]) ==
            Data([1, 3, 6, 0, 12, 0, 0, 0, 0x90, 1]))
        for invalid in [["debounce", "0", "0"], ["debounce", "51", "10"],
                        ["profile", "custom"], ["custom", "1", "15", "0", "4000"],
                        ["custom", "50", "50", "30", "2000"],
                        ["custom", "nan", "15", "0", "4000"]] {
            do { _ = try BluetoothProtocol.command(invalid); fatalError("Accepted invalid command") }
            catch { }
        }
        var status = [UInt8](repeating: 0, count: 24)
        status[0] = 1; status[1] = 3; status[3] = 10; status[4] = 1; status[5] = 11
        status[6] = 9; status[8] = 12; status[12] = 0x90; status[13] = 1
        status[14] = 12; status[18] = 0x90; status[19] = 1
        let decoded = try BluetoothProtocol.decode(Data(status))
        assert(decoded["debounce_release_ms"] as? Int == 10)
        assert(decoded["negotiated_timing_matches_request"] as? Bool == true)
        assert((decoded["negotiated"] as? [String: Any])?["interval_ms"] as? Double == 15)
        status[20] = 0xfb; status[21] = 0xff
        check(try BluetoothProtocol.decode(Data(status))["parameter_submission_result"] as? Int == -5)
        for length in [0, 1, 20, 23, 25] {
            do {
                _ = try BluetoothProtocol.decode(Data(repeating: 0, count: length))
                fatalError("Accepted invalid response")
            } catch { }
        }
        print("macOS Bluetooth protocol checks passed.")
    }
}
