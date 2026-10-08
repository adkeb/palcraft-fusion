import Foundation
import CoreGraphics
@_silgen_name("uncompress2") private func unzip(_ dest: UnsafeMutablePointer<UInt8>, _ destLen: UnsafeMutablePointer<UInt>, _ src: UnsafePointer<UInt8>, _ srcLen: UnsafeMutablePointer<UInt>) -> Int32

// Kept in this file so the existing one-file swiftc build remains compatible.
struct HUDPacket {
    let width: Int, height: Int, flags: UInt32, producer: UInt32
    let frame: UInt64, hostFrame: UInt64, captureMS: UInt64, publishMS: UInt64
    let version: Int, compressed: Data
    var bottomUp: Bool { flags & 1 != 0 }
    var build: Bool { flags & 8 != 0 }
}
struct MacForegroundGroup: Decodable {
    let version: Int, token: String, game_pid: Int32, game_identity: String
    let helper_pid: Int32, helper_identity: String, helper_bundle_id: String, helper_bundle: String
    let native_process_epoch: String, own_root: String, game_exe: String, private_user_dir: String
    func accepts(ownerPID: Int32, frontPID: Int32?, frontBundleID: String?) -> Bool {
        guard version == 1, game_pid > 0, helper_pid > 0, game_pid != helper_pid,
              !game_identity.isEmpty, !helper_identity.isEmpty, !native_process_epoch.isEmpty,
              ownerPID == game_pid else { return false }
        return frontPID == game_pid || (frontPID == helper_pid && frontBundleID == helper_bundle_id)
    }
}
enum HUDProtocolError: Error { case header, size, compression }
// Pure eligibility/coordinate mapping, also exercised without NSApp or CGWarp.
struct MacHostMousePlan {
    let point: CGPoint, x: Int, y: Int, width: Int, height: Int, generation: Int
    static func make(input: [String: Any], group: MacForegroundGroup?, groupAlive: Bool,
                     frontPID: Int32?, focused: Bool, cameraActive: Bool, renderAge: Double,
                     now: Double, buttonsDown: Bool, bounds: CGRect?, title: CGFloat) -> MacHostMousePlan? {
        guard focused, groupAlive, let group = group, frontPID == group.game_pid,
              input["mouse_compatibility_mode"] as? String == "relative-host-warp-v1",
              input["mouse_owner_token"] as? String == group.token,
              input["mouse_native_epoch"] as? String == group.native_process_epoch,
              input["mouse_host_eligible"] as? Bool == true,
              input["build"] as? Bool == true, input["focus"] as? Bool == true,
              input["menu"] as? Bool == false, !buttonsDown, cameraActive,
              renderAge >= -1, renderAge < 2.5,
              let stamp = input["unix"] as? Double, now-stamp >= -0.25, now-stamp <= 0.25,
              let gen = input["generation"] as? Int, gen >= 0,
              let w = input["viewport_width"] as? Int, let h = input["viewport_height"] as? Int,
              w > 0, h > 0, let bounds = bounds, bounds.width > 0, bounds.height > 0,
              input["mouse_win_geometry_valid"] as? Bool == true,
              let wx=input["mouse_win_window_x"] as? Double, let wy=input["mouse_win_window_y"] as? Double,
              let ww=input["mouse_win_window_width"] as? Double, let wh=input["mouse_win_window_height"] as? Double,
              let ox=input["mouse_win_client_origin_x"] as? Double, let oy=input["mouse_win_client_origin_y"] as? Double,
              ww > 0, wh > 0 else { return nil }
        let x=w/2, y=h/2
        let point=CGPoint(x: bounds.minX + CGFloat((ox+Double(x)-wx)/ww)*bounds.width,
                          y: bounds.minY + CGFloat((oy+Double(y)-wy)/wh)*bounds.height)
        return MacHostMousePlan(point: point, x: x, y: y, width: w, height: h, generation: gen)
    }
    func observed(_ cursor: CGPoint) -> Bool {
        cursor.x.isFinite && cursor.y.isFinite && abs(cursor.x-point.x) <= 0.5 && abs(cursor.y-point.y) <= 0.5
    }
}
private func hudMonotonic() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
struct HUDClock {
    private(set) var offset = 0.0 // remote epoch seconds minus local monotonic seconds
    private(set) var uncertainty = Double.infinity
    private(set) var calibratedAt = 0.0
    var ready: Bool { uncertainty.isFinite }
    mutating func observe(sent: UInt64, received: UInt64, remoteReceived: UInt64, remoteSent: UInt64) -> Bool {
        guard received >= sent, remoteSent >= remoteReceived else { return false }
        let localSpan = Double(received - sent) / 1e9
        let remoteSpan = Double(remoteSent - remoteReceived) / 1e9
        let rtt = localSpan - remoteSpan
        guard rtt >= 0 && rtt <= 0.2 else { return false }
        let midpoint = (Double(sent) + Double(received)) / 2e9
        let remoteMidpoint = (Double(remoteReceived) + Double(remoteSent)) / 2e9
        // Best sample while acquiring a clock; refresh after ten seconds to
        // follow drift or a Windows time resynchronization.
        if ready && midpoint - calibratedAt < 10 && rtt / 2 > uncertainty { return true }
        offset = remoteMidpoint - midpoint
        uncertainty = rtt / 2
        calibratedAt = midpoint
        return true
    }
    func ageUpperBound(captureMS: UInt64, now: Double) -> Double? {
        guard ready && now - calibratedAt <= 30 else { return nil }
        return now + offset - Double(captureMS) / 1000 + uncertainty
    }
}
final class HUDParser {
    static let maxWidth = 3840, maxHeight = 2160
    static let maxBytes = maxWidth * maxHeight * 4 + 65536 + 64
    private var buffer = Data()
    private(set) var packets = 0, superseded = 0
    var pendingBytes: Int { buffer.count }
    func reset() { buffer.removeAll(keepingCapacity: false) }
    private func be(_ offset: Int, _ length: Int) -> UInt64 {
        var n: UInt64 = 0
        for i in offset ..< offset + length { n = n << 8 | UInt64(buffer[i]) }
        return n
    }
    // Parse a whole receive batch, but decompress only its newest complete frame.
    func feed(_ data: Data) throws -> HUDPacket? {
        guard buffer.count + data.count <= Self.maxBytes else { throw HUDProtocolError.size }
        buffer.append(data)
        var offset = 0
        var newest: HUDPacket?
        while buffer.count - offset >= 12 {
            let v2 = be(offset, 4) == 0x50485544 // PHUD
            let header = v2 ? 64 : 12
            if buffer.count - offset < header { break }
            if v2 && (be(offset + 4, 2) != 2 || be(offset + 6, 2) != 64) { throw HUDProtocolError.header }
            let dimensions = offset + (v2 ? 8 : 0)
            let w = Int(be(dimensions, 4)), h = Int(be(dimensions + 4, 4)), n = Int(be(dimensions + 8, 4))
            guard w > 0 && w <= Self.maxWidth && h > 0 && h <= Self.maxHeight &&
                  n > 0 && n <= w * h * 4 + 65536 else { throw HUDProtocolError.size }
            let flags = v2 ? UInt32(be(offset + 20, 4)) : 15
            guard !v2 || (flags & 6 == 6 && be(offset + 28, 4) == 0) else { throw HUDProtocolError.header }
            let capture = v2 ? be(offset + 48, 8) : 0
            let publish = v2 ? be(offset + 56, 8) : 0
            guard !v2 || (capture > 0 && publish >= capture) else { throw HUDProtocolError.header }
            if buffer.count - offset < header + n { break }
            if newest != nil { superseded += 1 }
            newest = HUDPacket(width: w, height: h, flags: flags,
                               producer: v2 ? UInt32(be(offset + 24, 4)) : 0,
                               frame: v2 ? be(offset + 32, 8) : UInt64(packets + 1),
                               hostFrame: v2 ? be(offset + 40, 8) : 0,
                               captureMS: capture, publishMS: publish, version: v2 ? 2 : 1,
                               compressed: Data(buffer[offset + header ..< offset + header + n]))
            packets += 1
            offset += header + n
        }
        if offset > 0 { buffer.removeSubrange(0 ..< offset) }
        return newest
    }
    static func rgba(_ packet: HUDPacket) throws -> Data {
        var raw = Data(count: packet.width * packet.height * 4)
        var size = UInt(raw.count), compressedSize = UInt(packet.compressed.count)
        let result = raw.withUnsafeMutableBytes { dst in
            packet.compressed.withUnsafeBytes { src in
                unzip(dst.bindMemory(to: UInt8.self).baseAddress!, &size,
                      src.bindMemory(to: UInt8.self).baseAddress!, &compressedSize)
            }
        }
        guard result == 0 && size == raw.count && compressedSize == packet.compressed.count else {
            throw HUDProtocolError.compression
        }
        return raw
    }
}

#if !HUD_PROTOCOL_TEST
import Cocoa
import Network
import QuartzCore

final class Overlay: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private struct DecodedHUD {
    let image: CGImage, packet: HUDPacket, received: TimeInterval, sourceAge: TimeInterval
}
private struct StreamState {
    var latest: DecodedHUD?
    var connected = false
    var generation: UInt64 = 0
    var decoded = 0, coalesced = 0, rejected = 0, reconnects = 0
    var decodeMS = 0.0
    var packets = 0, skipped = 0
    var error = ""
    var rejectReason = "", sourceAgeMS = -1.0, clockUncertaintyMS = -1.0, clockOffset = 0.0
    var clockSamples = 0, clockFailures = 0
    var acceptedFrame: UInt64 = 0, acceptedHostFrame: UInt64 = 0, acceptedProducer: UInt32 = 0
    var acceptedAgeMS = -1.0, acceptedAt = 0.0
    var receivedAt = 0.0
}
final class HUD: NSObject, NSApplicationDelegate {
    let panel = Overlay(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let pixels = CALayer()
    let network = DispatchQueue(label: "palcraft.hud", qos: .userInteractive)
    let lock = NSLock()
    private var stream = StreamState()
    private let parser = HUDParser()
    private var connection: NWConnection?
    private var calibrationConnection: NWConnection?
    private var calibrationStarted = 0.0
    private var clock = HUDClock()
    private var generation: UInt64 = 0
    private var received = 0.0, retry = 0.25
    private var lastToken: (UInt32, UInt64)?
    private var watchdog: DispatchSourceTimer?
    private var timers: [Timer] = []
    private var displayTimer: Timer?
    private var displayFPS = 60.0
    private var powerSeen: String?
    private var pendingMouseWarp: (request: Double, plan: MacHostMousePlan, token: String, epoch: String)?
    private let powerEnvironment: [String: String]
    private var shown: DecodedHUD?
    private var eligible = false, focused = false
    private var requireReceivedAfter = 0.0
    private var frames = 0, transitionDrops = 0, lastStatus = 0.0
    private let maxAge = 0.25
    private let titleHeight: CGFloat
    private let port: NWEndpoint.Port
    private let frameMapping: String
    private let targetPID: Int32?
    private let foregroundGroup: MacForegroundGroup?
    private let groupRequired: Bool
    private var groupAlive = false, groupCheckedAt = -Double.infinity
    private let root: URL

    override init() {
        let env = ProcessInfo.processInfo.environment
        powerEnvironment = env
        if let fps = env["PALCRAFT_HUD_FPS"].flatMap(Double.init), (1...120).contains(fps) { displayFPS = fps }
        root = URL(fileURLWithPath: env["PALCRAFT_BRIDGE_DIR"] ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PalCraft/bridge").path)
        titleHeight = CGFloat(Double(env["PALCRAFT_TITLEBAR_HEIGHT"] ?? "") ?? 28)
        port = NWEndpoint.Port(rawValue: UInt16(env["PALCRAFT_HUD_PORT"] ?? "") ?? 25603)!
        frameMapping = env["PALCRAFT_FRAME_NAME"] ?? "Local\\MCPassthroughFrame"
        targetPID = env["PALCRAFT_WINDOW_PID"].flatMap(Int32.init)
        groupRequired = env["PALCRAFT_MAC_FOREGROUND_GROUP_REQUIRED"] == "1"
        foregroundGroup = env["PALCRAFT_MAC_FOREGROUND_GROUP"].flatMap { value in
            value.data(using: .utf8).flatMap { try? JSONDecoder().decode(MacForegroundGroup.self, from: $0) }
        }
        super.init()
    }
    private func state<T>(_ body: (inout StreamState) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&stream)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.addSublayer(pixels)
        panel.contentView = view
        pixels.contentsGravity = .resize
        pixels.magnificationFilter = .nearest
        pixels.minificationFilter = .linear
        for (interval, action) in [(0.1, self.position)] {
            let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
            timers.append(timer)
            RunLoop.main.add(timer, forMode: .common)
        }
        scheduleDisplay()
        position()
        network.async { self.connect() }
        let timer = DispatchSource.makeTimerSource(queue: network)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = hudMonotonic()
            if self.calibrationConnection != nil && now - self.calibrationStarted > 1 {
                self.finishCalibration(false)
            }
            if self.connection != nil && self.calibrationConnection == nil &&
               now - self.received < 1.5 && (!self.clock.ready || now - self.clock.calibratedAt >= 10) {
                self.calibrate(self.generation)
            }
        }
        watchdog = timer
        timer.resume()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timers.forEach { $0.invalidate() }
        displayTimer?.invalidate()
        network.async { self.watchdog?.cancel(); self.connection?.cancel() }
        try? "\(Date().timeIntervalSince1970) 0".write(
            to: root.appendingPathComponent("platform-focus.txt"), atomically: true, encoding: .utf8)
    }
    private func connect() {
        generation &+= 1
        let token = generation
        parser.reset()
        lastToken = nil
        received = hudMonotonic()
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3
        let c = NWConnection(host: "127.0.0.1", port: port, using: NWParameters(tls: nil, tcp: tcp))
        connection = c
        state { $0.generation = token; $0.connected = false; $0.receivedAt = received }
        c.stateUpdateHandler = { [weak self] status in
            guard let self = self, self.generation == token else { return }
            switch status {
            case .ready:
                self.retry = 0.25
                self.state { $0.connected = true; $0.error = "" }
                self.calibrate(token)
                // An old relay sends v1 immediately and ignores the request.
                c.send(content: Data("HUD2\n".utf8), completion: .contentProcessed { _ in })
                self.read(c, token)
            case .failed(let error): self.disconnect(token, error.localizedDescription)
            case .cancelled: self.disconnect(token, "cancelled")
            default: break
            }
        }
        c.start(queue: network)
    }
    private func disconnect(_ token: UInt64, _ reason: String) {
        guard token == generation, let c = connection else { return }
        connection = nil
        calibrationConnection?.cancel()
        calibrationConnection = nil
        c.stateUpdateHandler = nil
        c.cancel()
        parser.reset()
        state { $0.connected = false; $0.latest = nil; $0.error = reason; $0.reconnects += 1 }
        let delay = retry
        retry = min(retry * 2, 3)
        network.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.generation == token, self.connection == nil else { return }
            self.connect()
        }
    }
    private func finishCalibration(_ success: Bool) {
        calibrationConnection?.stateUpdateHandler = nil
        calibrationConnection?.cancel()
        calibrationConnection = nil
        if !success { state { $0.clockFailures += 1 } }
    }
    private func calibrate(_ token: UInt64) {
        guard calibrationConnection == nil, token == generation else { return }
        let c = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        calibrationConnection = c
        calibrationStarted = hudMonotonic()
        c.stateUpdateHandler = { [weak self] status in
            guard let self = self, self.generation == token, self.calibrationConnection === c else { return }
            switch status {
            case .ready:
                let sent = DispatchTime.now().uptimeNanoseconds
                var hello = Data("TIME\n".utf8)
                for shift in stride(from: 56, through: 0, by: -8) { hello.append(UInt8(truncatingIfNeeded: sent >> shift)) }
                c.send(content: hello, completion: .contentProcessed { [weak self] error in
                    guard let self = self, self.calibrationConnection === c else { return }
                    if error != nil { self.finishCalibration(false) }
                    else { self.readClock(c, token, sent, Data()) }
                })
            case .failed, .cancelled: self.finishCalibration(false)
            default: break
            }
        }
        c.start(queue: network)
    }
    private func readClock(_ c: NWConnection, _ token: UInt64, _ sent: UInt64, _ previous: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 32 - previous.count) { [weak self] data, _, done, error in
            guard let self = self, self.generation == token, self.calibrationConnection === c else { return }
            var bytes = previous
            if let data = data { bytes.append(data) }
            if bytes.count == 32 {
                func be(_ offset: Int, _ length: Int) -> UInt64 {
                    var n: UInt64 = 0
                    for i in offset ..< offset + length { n = n << 8 | UInt64(bytes[i]) }
                    return n
                }
                let valid = be(0,4) == 0x48434c4b && be(4,2) == 1 && be(6,2) == 32 &&
                            be(8,8) == sent && self.clock.observe(sent: sent,
                                received: DispatchTime.now().uptimeNanoseconds,
                                remoteReceived: be(16,8), remoteSent: be(24,8))
                if valid {
                    self.state {
                        $0.clockSamples += 1
                        $0.clockUncertaintyMS = self.clock.uncertainty * 1000
                        $0.clockOffset = self.clock.offset
                    }
                }
                self.finishCalibration(valid)
            } else if done || error != nil { self.finishCalibration(false) }
            else { self.readClock(c, token, sent, bytes) }
        }
    }
    private func read(_ c: NWConnection, _ token: UInt64) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self = self, self.generation == token, self.connection === c else { return }
            do {
                if let data = data, !data.isEmpty {
                    self.received = hudMonotonic()
                    self.state { $0.receivedAt = self.received }
                    if let packet = try self.parser.feed(data) {
                        if packet.captureMS != 0 && (!self.clock.ready || hudMonotonic() - self.clock.calibratedAt >= 10) {
                            self.calibrate(token)
                        }
                        try self.decode(packet)
                    }
                    self.state { $0.packets = self.parser.packets; $0.skipped = self.parser.superseded }
                }
                if done || error != nil { self.disconnect(token, error?.localizedDescription ?? "EOF") }
                else { self.read(c, token) }
            } catch {
                self.state { $0.rejected += 1 }
                self.disconnect(token, "invalid HUD packet: \(error)")
            }
        }
    }
    private func decode(_ packet: HUDPacket) throws {
        let now = hudMonotonic()
        guard let age = packet.captureMS == 0 ? 0 : clock.ageUpperBound(captureMS: packet.captureMS, now: now) else {
            state { $0.rejected += 1; $0.rejectReason = "clock_uncalibrated" }
            return
        }
        let sourceAge = max(0, age)
        let duplicate = lastToken?.0 == packet.producer && lastToken!.1 >= packet.frame
        if age < -0.05 || sourceAge > maxAge || duplicate {
            state {
                $0.rejected += 1
                $0.sourceAgeMS = age * 1000
                $0.rejectReason = duplicate ? "duplicate_frame" : age < -0.05 ? "source_clock_changed" : "source_frame_expired"
            }
            return
        }
        lastToken = (packet.producer, packet.frame)
        let raw = try HUDParser.rgba(packet)
        guard let provider = CGDataProvider(data: raw as CFData),
              let image = CGImage(width: packet.width, height: packet.height, bitsPerComponent: 8,
                  bitsPerPixel: 32, bytesPerRow: packet.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw HUDProtocolError.size
        }
        let decoded = DecodedHUD(image: image, packet: packet, received: now, sourceAge: sourceAge)
        state {
            if $0.latest != nil { $0.coalesced += 1 }
            $0.latest = decoded
            $0.decoded += 1
            $0.decodeMS += (hudMonotonic() - now) * 1000
            $0.sourceAgeMS = sourceAge * 1000
            $0.rejectReason = ""
            $0.acceptedFrame = packet.frame
            $0.acceptedHostFrame = packet.hostFrame
            $0.acceptedProducer = packet.producer
            $0.acceptedAgeMS = sourceAge * 1000
            $0.acceptedAt = now
        }
    }
    private func clear() {
        if shown != nil || panel.isVisible {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pixels.contents = nil
            CATransaction.commit()
            shown = nil
            panel.orderOut(nil)
        }
    }
    private func display() {
        let now = hudMonotonic()
        let incoming = state { s -> (DecodedHUD?, Bool) in
            let latest = s.latest
            s.latest = nil
            return (latest, s.connected)
        }
        guard eligible && incoming.1 else { clear(); return }
        if let frame = incoming.0 {
            if frame.received < requireReceivedAfter || !frame.packet.build {
                transitionDrops += 1
                clear()
                return
            }
            if now - frame.received + frame.sourceAge <= maxAge {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                pixels.transform = CATransform3DMakeScale(1, frame.packet.bottomUp ? -1 : 1, 1)
                pixels.contents = frame.image
                CATransaction.commit()
                shown = frame
                frames += 1
            }
        }
        guard let frame = shown, now - frame.received + frame.sourceAge <= maxAge else { clear(); return }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    private func json(_ name: String) -> [String: Any]? {
        guard let bytes = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }
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
    private func position() {
        applyOwnedPerformance()
        let now = hudMonotonic(), unix = Date().timeIntervalSince1970
        let front = NSWorkspace.shared.frontmostApplication
        if groupRequired && now - groupCheckedAt >= 1 {
            groupCheckedAt = now; groupAlive = false
            if let group = foregroundGroup {
                func sameBirth(_ pid: Int32, _ expected: String) -> Bool {
                    let process = Process(); let pipe = Pipe()
                    process.executableURL = URL(fileURLWithPath: "/bin/ps")
                    process.arguments = ["-p", String(pid), "-o", "lstart="]
                    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                    do {
                        try process.run()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                        return process.terminationStatus == 0 &&
                            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == expected
                    } catch { return false }
                }
                groupAlive = sameBirth(group.game_pid, group.game_identity) && sameBirth(group.helper_pid, group.helper_identity)
            }
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let win = windows.first {
            guard ($0[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let owner = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return false }
            if self.groupRequired {
                guard self.groupAlive, let group = self.foregroundGroup,
                      root.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == group.own_root else { return false }
                return group.accepts(ownerPID: owner, frontPID: front?.processIdentifier, frontBundleID: front?.bundleIdentifier) &&
                    (front?.processIdentifier != group.helper_pid || front?.bundleURL?.path == group.helper_bundle)
            }
            return ($0[kCGWindowOwnerName as String] as? String) == "Palworld-Win64-Shipping.exe" &&
                owner == front?.processIdentifier && (self.targetPID == nil || self.targetPID == front?.processIdentifier)
        }
        focused = win != nil
        // This 100ms epoch + boolean protocol belongs to the input focus gate.
        try? "\(unix) \(focused ? 1 : 0)".write(
            to: root.appendingPathComponent("platform-focus.txt"), atomically: true, encoding: .utf8)
        let render = json("render-status.json"), input = json("input-state.json")
        let renderAge = unix - (render?["updated_unix"] as? Double ?? 0)
        let inputAge = unix - (input?["unix"] as? Double ?? 0)
        let next = focused && render?["camera_active"] as? Bool == true &&
                   input?["build"] as? Bool == true && renderAge >= -1 && renderAge < 2.5 &&
                   inputAge >= -1 && inputAge < 2.5
        if let input = input {
            let bounds = (win?[kCGWindowBounds as String] as? [String: CGFloat]).flatMap { value -> CGRect? in
                guard let x=value["X"], let y=value["Y"], let w=value["Width"], let h=value["Height"] else { return nil }
                return CGRect(x:x,y:y,width:w,height:h)
            }
            let buttons = [CGMouseButton.left, .right, .center].contains {
                CGEventSource.buttonState(.combinedSessionState, button: $0)
            }
            let mousePlan=MacHostMousePlan.make(input: input, group: foregroundGroup, groupAlive: groupAlive,
                    frontPID: front?.processIdentifier, focused: focused, cameraActive: render?["camera_active"] as? Bool == true,
                    renderAge: renderAge, now: unix, buttonsDown: buttons, bounds: bounds, title: titleHeight)
            if let plan=mousePlan, let group=foregroundGroup, let cursor=CGEvent(source:nil)?.location {
                func publish(_ phase: String, _ request: Double, _ observed: Double, _ point: CGPoint) {
                    let result:[String:Any] = ["schema":2,"owner_token":group.token,"process_epoch":group.native_process_epoch,
                        "generation":plan.generation,"viewport_width":plan.width,"viewport_height":plan.height,
                        "client_target_x":plan.x,"client_target_y":plan.y,"global_x":point.x,"global_y":point.y,
                        "observed_unix":observed,"request_unix":request,"phase":phase]
                    if let data=try? JSONSerialization.data(withJSONObject:result, options:.sortedKeys) {
                        try? data.write(to:root.appendingPathComponent("mac-mouse-host.json"), options:.atomic)
                    }
                }
                if let pending=pendingMouseWarp {
                    if unix-pending.request > 0.75 || pending.token != group.token || pending.epoch != group.native_process_epoch ||
                       pending.plan.generation != plan.generation || pending.plan.point != plan.point { pendingMouseWarp=nil }
                    else if let armed=input["mouse_host_armed_request"] as? Double, abs(armed-pending.request)<0.00001 {
                        if CGWarpMouseCursorPosition(plan.point) == .success,
                           let actual=CGEvent(source:nil)?.location, plan.observed(actual) {
                            publish("observed",pending.request,Date().timeIntervalSince1970,actual)
                        }
                        pendingMouseWarp=nil
                    }
                } else if !plan.observed(cursor) {
                    pendingMouseWarp=(unix,plan,group.token,group.native_process_epoch)
                    publish("request",unix,0,cursor)
                }
            } else { pendingMouseWarp=nil }
        }
        if next != eligible {
            eligible = next
            requireReceivedAfter = now
            clear()
        }
        if next, let bounds = win?[kCGWindowBounds as String] as? [String: CGFloat],
           let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
           w > 0, h > titleHeight, let screen = NSScreen.screens.first {
            let rect = NSRect(x: x, y: screen.frame.maxY - y - h, width: w, height: h - titleHeight)
            if panel.frame != rect {
                panel.setFrame(rect, display: true)
                requireReceivedAfter = now
                clear()
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pixels.frame = NSRect(origin: .zero, size: rect.size)
            CATransaction.commit()
        }
        if now - lastStatus >= 1 {
            lastStatus = now
            let s = state { $0 }
            let frameAge = shown.map { now - $0.received + $0.sourceAge } ?? -1
            let status: [String: Any] = [
                "frames": frames, "visible": panel.isVisible, "focused": focused, "frame_age": frameAge, "unix": unix,
                "display_fps": displayFPS,
                "connected": s.connected, "connection_generation": s.generation, "reconnects": s.reconnects,
                "packets": s.packets, "decoded": s.decoded, "dropped_batch": s.skipped, "dropped_mailbox": s.coalesced,
                "dropped_transition": transitionDrops, "rejected": s.rejected,
                "decode_ms_mean": s.decodeMS / Double(max(1, s.decoded)), "queue_capacity": 1,
                "protocol": shown?.packet.version ?? 0, "source_frame": shown?.packet.frame ?? 0,
                "host_frame": shown?.packet.hostFrame ?? 0, "producer": shown?.packet.producer ?? 0, "error": s.error,
                "frame_mapping": frameMapping, "port": port.rawValue,
                "clock_samples": s.clockSamples, "clock_failures": s.clockFailures,
                "clock_uncertainty_ms": s.clockUncertaintyMS, "clock_offset_epoch_monotonic": s.clockOffset,
                "source_age_upper_ms": s.sourceAgeMS, "reject_reason": s.rejectReason,
                "last_accepted_source_frame": s.acceptedFrame, "last_accepted_host_frame": s.acceptedHostFrame,
                "last_accepted_producer": s.acceptedProducer, "last_accepted_age_upper_ms": s.acceptedAgeMS,
                "last_accepted_elapsed_ms": s.acceptedAt > 0 ? (now - s.acceptedAt) * 1000 : -1,
                "stream_idle_ms": s.receivedAt > 0 ? (now - s.receivedAt) * 1000 : -1,
            ]
            if let bytes = try? JSONSerialization.data(withJSONObject: status) {
                try? bytes.write(to: root.appendingPathComponent("mac-hud-status.json"), options: .atomic)
            }
        }
    }
}
let app = NSApplication.shared, delegate = HUD()
app.delegate = delegate
app.run()
#endif
