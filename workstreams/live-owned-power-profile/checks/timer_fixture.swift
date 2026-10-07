import Foundation
final class TimerFixture {
private var displayTimer: Timer?
private var displayFPS = 60.0
private var powerSeen: String?
private let powerEnvironment = ProcessInfo.processInfo.environment
private func display() { }
    private func scheduleDisplay() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / displayFPS, repeats: true) { [weak self] _ in self?.display() }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func applyOwnedPerformance() {
        let env = powerEnvironment
        guard env["PALCRAFT_PERFORMANCE_ROLE"] == "hud",
              let path = env["PALCRAFT_PERFORMANCE_DIR"], let token = env["PALCRAFT_PERFORMANCE_TOKEN"],
              let rootID = env["PALCRAFT_PERFORMANCE_ROOT_ID"] else { return }
        let dir = URL(fileURLWithPath: path)
        let heartbeat = dir.deletingLastPathComponent().appendingPathComponent(token + ".heartbeat")
        guard let stamp = (try? heartbeat.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(stamp) <= 12,
              let bytes = try? Data(contentsOf: dir.appendingPathComponent("request.json")),
              let request = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              request["kind"] as? String == "palcraft-owned-live-performance-v1",
              request["root_id"] as? String == rootID, request["token"] as? String == token,
              let id = request["request_id"] as? String, id != powerSeen,
              let expires = request["expires_unix"] as? Double, expires > Date().timeIntervalSince1970,
              let targets = request["targets"] as? [String: Any], let fps = targets["hud_fps"] as? Int,
              (1...120).contains(fps) else { return }
        displayFPS = Double(fps)
        scheduleDisplay()
        var result = request.filter { ["schema", "kind", "root_id", "token", "request_id"].contains($0.key) }
        result["role"] = "hud"; result["pid"] = ProcessInfo.processInfo.processIdentifier
        result["ok"] = displayTimer?.isValid == true
        result["actual"] = ["hud_fps": 1.0 / (displayTimer?.timeInterval ?? .infinity)]
        if let output = try? JSONSerialization.data(withJSONObject: result) {
            do { try output.write(to: dir.appendingPathComponent("hud.json"), options: .atomic); powerSeen = id }
            catch { }
        }
    }

func check() {
 scheduleDisplay(); let previous = displayTimer!
 applyOwnedPerformance()
 precondition(!previous.isValid && displayTimer!.isValid)
 precondition(abs(displayTimer!.timeInterval - 1.0/30.0) < 0.000001)
 let current = displayTimer!; applyOwnedPerformance(); precondition(displayTimer === current)
 displayTimer?.invalidate()
 print("Actual extracted Foundation timer apply/readback: PASS (no NSApp/UI)")
}
}
TimerFixture().check()
