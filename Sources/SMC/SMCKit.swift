import IOKit
import Foundation

// MARK: - SMC Data Structures

struct SMCKeyData {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    )
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var pad1: UInt8 = 0
    var pad2: UInt8 = 0
    var pad3: UInt8 = 0
}

// MARK: - SMC Result Codes

struct SMCResult {
    static let kSMCSuccess: UInt8 = 0
    static let kSMCError: UInt8 = 1
}

// MARK: - SMC Selectors

enum SMCSelector: UInt32 {
    case kSMCHandleYPCEvent  = 2
    case kSMCReadKey         = 5
    case kSMCWriteKey        = 6
    case kSMCGetKeyFromIndex = 8
    case kSMCGetKeyInfo      = 9
}

// MARK: - SMC Data Types

struct SMCDataType {
    static let types: [UInt32: String] = [
        fourCharCode("flag"): "flag",
        fourCharCode("ui8 "): "ui8",
        fourCharCode("ui16"): "ui16",
        fourCharCode("ui32"): "ui32",
        fourCharCode("fpe2"): "fpe2",
        fourCharCode("sp78"): "sp78",
        fourCharCode("flt "): "flt",
        fourCharCode("ch8*"): "ch8*",
    ]
}

func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    let data = string.utf8
    for (i, byte) in data.enumerated() where i < 4 {
        result |= UInt32(byte) << (24 - i * 8)
    }
    return result
}

// MARK: - SMC Kit

class SMCKit {
    private var conn: io_connect_t = 0
    private var isConnected = false

    init() {
        connect()
    }

    deinit {
        disconnect()
    }

    private func connect() {
        let masterPort: mach_port_t = kIOMainPortDefault
        let matchingDict = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(masterPort, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            print("SMC: IOServiceGetMatchingServices failed with \(result)")
            return
        }

        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        guard service != 0 else {
            print("SMC: No AppleSMC service found")
            return
        }

        var connect: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connect)
        IOObjectRelease(service)

        guard openResult == KERN_SUCCESS else {
            print("SMC: IOServiceOpen failed with \(openResult)")
            return
        }

        conn = connect
        isConnected = true
    }

    private func disconnect() {
        guard isConnected else { return }
        IOServiceClose(conn)
        isConnected = false
    }

    // MARK: - Read Key

    func readKey(_ key: String) -> (dataType: String, bytes: [UInt8])? {
        guard isConnected else { return nil }

        let keyCode = fourCharCode(key)

        // Get key info
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = UInt8(SMCSelector.kSMCGetKeyInfo.rawValue)

        guard callSMC(&input) == KERN_SUCCESS, input.result == SMCResult.kSMCSuccess else {
            return nil
        }

        let dataSize = Int(input.keyInfo.dataSize)
        let dataTypeCode = input.keyInfo.dataType
        let dataType = SMCDataType.types[dataTypeCode] ?? String(format: "%08x", dataTypeCode)

        // Read key value
        var readInput = SMCKeyData()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = UInt32(dataSize)
        readInput.data8 = UInt8(SMCSelector.kSMCReadKey.rawValue)

        guard callSMC(&readInput) == KERN_SUCCESS, readInput.result == SMCResult.kSMCSuccess else {
            return nil
        }

        let bytes = withUnsafeBytes(of: readInput.bytes) { Array($0.prefix(dataSize)) }
        return (dataType, bytes)
    }

    // MARK: - Read numeric value

    func readNumericValue(_ key: String) -> Double? {
        guard let (dataType, bytes) = readKey(key) else { return nil }
        guard !bytes.isEmpty else { return nil }

        switch dataType {
        case "ui8":
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let val = UInt32(bytes[0]) << 24 |
                UInt32(bytes[1]) << 16 |
                UInt32(bytes[2]) << 8 |
                UInt32(bytes[3])
            return Double(val)
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let intPart = Double((raw >> 8) & 0x7F)
            let fracPart = Double(raw & 0xFF) / 256.0
            let val = intPart + fracPart
            return (raw & 0x8000) != 0 ? -val : val
        case "flt":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) << 24 |
                UInt32(bytes[1]) << 16 |
                UInt32(bytes[2]) << 8 |
                UInt32(bytes[3])
            return Double(Float(bitPattern: raw))
        default:
            return nil
        }
    }

    // MARK: - Convenience accessors

    /// CPU die temperature in °C
    var cpuTemperature: Double? {
        let keys = [
            "TC0D", "TC0E", "TC0F", "TC0P", "TC0H",
            "TC1C", "TC1D", "TC1E", "TC1F", "TC1P",
            "TC2C", "TC2D", "TC2E", "TC2F",
            "TCXC", "TCXc", "TCGc", "TCSA", "Tp09"
        ]
        for key in keys {
            if let val = readNumericValue(key), val > 0, val < 130 {
                return val
            }
        }
        return nil
    }

    /// Fan speeds in RPM (returns array of fan speeds)
    var fanSpeeds: [Double] {
        var speeds: [Double] = []
        let count = max(fanCount, 8)
        for i in 0..<count {
            let key = String(format: "F%dAc", i)
            if let val = readNumericValue(key), val > 0, val < 20000 {
                speeds.append(val)
            }
        }
        return speeds
    }

    /// Number of fans
    var fanCount: Int {
        if let val = readNumericValue("FNum") {
            return Int(val)
        }
        return 0
    }

    // MARK: - Private SMC Call

    @discardableResult
    private func callSMC(_ inputData: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.size
        let outputSize = MemoryLayout<SMCKeyData>.size

        // Use local arrays to avoid overlapping access issues
        var inputBytes = [UInt8](repeating: 0, count: inputSize)
        var outputBytes = [UInt8](repeating: 0, count: outputSize)
        var outputSizeActual = outputSize

        // Copy input struct to byte array
        withUnsafeBytes(of: inputData) { src in
            inputBytes.withUnsafeMutableBytes { dst in
                dst.copyMemory(from: .init(src))
            }
        }

        let result = inputBytes.withUnsafeMutableBufferPointer { inputBuf in
            outputBytes.withUnsafeMutableBufferPointer { outputBuf in
                IOConnectCallStructMethod(
                    conn,
                    2,
                    inputBuf.baseAddress!,
                    inputSize,
                    outputBuf.baseAddress!,
                    &outputSizeActual
                )
            }
        }

        // Copy output back to inputData on success
        if result == KERN_SUCCESS {
            outputBytes.withUnsafeBytes { src in
                withUnsafeMutableBytes(of: &inputData) { dst in
                    dst.copyMemory(from: .init(src))
                }
            }
        }

        return result
    }
}
