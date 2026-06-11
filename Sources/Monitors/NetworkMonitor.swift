import Foundation
import Darwin

/// Monitors network speed by tracking interface byte counters over time.
class NetworkMonitor: ObservableObject {
    @Published var downloadSpeed: String = "---"
    @Published var uploadSpeed: String = "---"
    @Published var downloadBytesPerSec: Double = 0
    @Published var uploadBytesPerSec: Double = 0

    private var previousCounters: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousTimestamp: Date = Date()
    private var timer: Timer?

    /// Active network interfaces to track (en0 = Wi-Fi, en1 = Ethernet/Thunderbolt)
    private let trackedInterfaces = ["en0", "en1", "en2", "en3", "en4"]

    func start() {
        previousCounters = getNetworkCounters()
        previousTimestamp = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        update()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        let now = Date()
        let currentCounters = getNetworkCounters()

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var previousReceived: UInt64 = 0
        var previousSent: UInt64 = 0

        for ifName in trackedInterfaces {
            if let cur = currentCounters[ifName] {
                totalReceived += cur.received
                totalSent += cur.sent
            }
            if let prev = previousCounters[ifName] {
                previousReceived += prev.received
                previousSent += prev.sent
            }
        }

        let elapsed = now.timeIntervalSince(previousTimestamp)
        if elapsed > 0 && totalReceived >= previousReceived && totalSent >= previousSent {
            let dl = Double(totalReceived - previousReceived) / elapsed
            let ul = Double(totalSent - previousSent) / elapsed
            downloadBytesPerSec = dl
            uploadBytesPerSec = ul
            downloadSpeed = formatSpeed(bytesPerSec: dl)
            uploadSpeed = formatSpeed(bytesPerSec: ul)
        }

        previousCounters = currentCounters
        previousTimestamp = now
    }

    private func getNetworkCounters() -> [String: (received: UInt64, sent: UInt64)] {
        var counters: [String: (received: UInt64, sent: UInt64)] = [:]

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return counters }
        defer { freeifaddrs(first) }

        var ptr = first
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            if trackedInterfaces.contains(name),
               let dataPtr = ptr.pointee.ifa_data {
                // Read ifi_ibytes (offset 40) and ifi_obytes (offset 44) as UInt32
                let ibytes = dataPtr.load(fromByteOffset: 40, as: UInt32.self)
                let obytes = dataPtr.load(fromByteOffset: 44, as: UInt32.self)
                counters[name] = (received: UInt64(ibytes), sent: UInt64(obytes))
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return counters
    }

    private func formatSpeed(bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
}
