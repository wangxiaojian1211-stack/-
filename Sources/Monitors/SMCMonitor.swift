import Foundation

/// Monitors CPU temperature and fan speeds via SMC.
class SMCMonitor: ObservableObject {
    @Published var cpuTemperature: String = "---"
    @Published var fanSpeed: String = "---"
    @Published var cpuTempDouble: Double = 0
    @Published var fanSpeedDouble: Double = 0

    private var smc: SMCKit?
    private var timer: Timer?

    func start() {
        smc = SMCKit()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        smc = nil
    }

    private func update() {
        guard let smc = smc else {
            cpuTemperature = "N/A"
            fanSpeed = "N/A"
            return
        }

        // CPU Temperature
        if let temp = smc.cpuTemperature {
            cpuTempDouble = temp
            cpuTemperature = String(format: "%.0f°C", temp)
        } else {
            cpuTemperature = "N/A"
        }

        // Fan speed - show average or first fan
        let speeds = smc.fanSpeeds
        if !speeds.isEmpty {
            let avg = speeds.reduce(0, +) / Double(speeds.count)
            fanSpeedDouble = avg
            fanSpeed = String(format: "%.0f RPM", avg)
        } else {
            fanSpeed = "N/A"
        }
    }
}
