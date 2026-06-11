import Darwin
import Foundation

struct AppleSiliconSensorReading {
    let name: String
    let temperature: Double
}

/// Reads Apple Silicon thermal sensors through IOKit's HID event system.
///
/// M-series Macs do not expose the same AppleSMC temperature keys used by Intel
/// Macs. Their CPU die readings are available as PMU/HID temperature services
/// such as "PMU tdie...".
final class AppleSiliconSensors {
    private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeRawPointer, Int32, UInt64, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatValueFn = @convention(c) (CFTypeRef, UInt32) -> Double

    private static let temperatureEventType: Int32 = 15
    private static let temperatureLevelField: UInt32 = UInt32(temperatureEventType) << 16

    private let handle: UnsafeMutableRawPointer?
    private let clientCreate: ClientCreateFn?
    private let copyServices: CopyServicesFn?
    private let copyProperty: CopyPropertyFn?
    private let copyEvent: CopyEventFn?
    private let getFloatValue: GetFloatValueFn?

    init() {
        handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        clientCreate = Self.loadSymbol(handle, "IOHIDEventSystemClientCreate", as: ClientCreateFn.self)
        copyServices = Self.loadSymbol(handle, "IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self)
        copyProperty = Self.loadSymbol(handle, "IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self)
        copyEvent = Self.loadSymbol(handle, "IOHIDServiceClientCopyEvent", as: CopyEventFn.self)
        getFloatValue = Self.loadSymbol(handle, "IOHIDEventGetFloatValue", as: GetFloatValueFn.self)
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    var cpuTemperature: Double? {
        let readings = temperatureReadings
        guard !readings.isEmpty else { return nil }

        let cpuDie = readings.filter { $0.name.lowercased().hasPrefix("pmu tdie") }
        if let value = cpuDie.map(\.temperature).max() {
            return value
        }

        let cpuNamed = readings.filter {
            let name = $0.name.lowercased()
            return name.contains("cpu") ||
                name.contains("tdie") ||
                name.contains("p-core") ||
                name.contains("e-core") ||
                name.hasPrefix("pacc mtr temp sensor") ||
                name.hasPrefix("eacc mtr temp sensor")
        }
        if let value = cpuNamed.map(\.temperature).max() {
            return value
        }

        return readings.map(\.temperature).max()
    }

    var temperatureReadings: [AppleSiliconSensorReading] {
        guard Self.isAppleSilicon else { return [] }
        guard let clientCreate,
              let copyServices,
              let copyProperty,
              let copyEvent,
              let getFloatValue,
              let client = clientCreate(kCFAllocatorDefault)?.takeRetainedValue(),
              let services = copyServices(client)?.takeRetainedValue() else {
            return []
        }

        let count = CFArrayGetCount(services)
        guard count > 0 else { return [] }

        var readings: [AppleSiliconSensorReading] = []

        for index in 0..<count {
            guard let service = CFArrayGetValueAtIndex(services, index),
                  let product = copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
                  CFGetTypeID(product) == CFStringGetTypeID(),
                  let name = product as? String,
                  let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
                continue
            }

            let temperature = getFloatValue(event, Self.temperatureLevelField)
            guard temperature >= -20, temperature <= 130 else { continue }
            readings.append(AppleSiliconSensorReading(name: name, temperature: temperature))
        }

        return readings
    }

    private static func loadSymbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let handle,
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }
}
