import Foundation

/// Monitors disk usage.
class DiskMonitor: ObservableObject {
    @Published var diskUsage: String = "---"
    @Published var usedPercentage: Double = 0

    private var timer: Timer?

    func start() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        guard let usage = getDiskUsage() else {
            diskUsage = "N/A"
            return
        }
        usedPercentage = usage.usedPercent
        diskUsage = String(format: "%.0f%%", usage.usedPercent)
    }

    private func getDiskUsage() -> (usedPercent: Double, used: Int64, total: Int64)? {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            if let total = values.volumeTotalCapacity,
               let available = values.volumeAvailableCapacityForImportantUsage {
                let used = Int64(total) - Int64(available)
                let percent = Double(used) / Double(total) * 100.0
                return (usedPercent: percent, used: used, total: Int64(total))
            }
        } catch {
            print("DiskMonitor: failed to get volume info: \(error)")
        }
        return nil
    }
}
