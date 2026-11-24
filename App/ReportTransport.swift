import Foundation
import IOKit.hid

@MainActor
protocol ReportTransport: AnyObject {
    var received: (([UInt8]) -> Void)? { get set }
    func write(_ bytes: [UInt8]) -> Bool
    func close()
}

@MainActor
final class BluetoothTransport: ReportTransport {
    private let device: IOHIDDevice
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var received: (([UInt8]) -> Void)?

    // Caller has opened the device and scheduled its manager on the main run loop.
    init(_ device: IOHIDDevice) {
        self.device = device
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, reportID, bytes, length in
            guard result == kIOReturnSuccess, let context, reportID == 0x11 else { return }
            let transport = Unmanaged<BluetoothTransport>.fromOpaque(context).takeUnretainedValue()
            let report = Array(UnsafeBufferPointer(start: bytes, count: length))
            MainActor.assumeIsolated { transport.received?(report) }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func write(_ bytes: [UInt8]) -> Bool {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, bytes, bytes.count) == kIOReturnSuccess
    }

    func close() {
        received = nil
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, 0)
        buffer.deallocate()
    }
}
