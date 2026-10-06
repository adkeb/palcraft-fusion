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
enum HUDProtocolError: Error { case header, size, compression }
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
}
final class HUD: NSObject, NSApplicationDelegate {
    let panel = Overlay(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let pixels = CALayer()
    let network = DispatchQueue(label: "palcraft.hud", qos: .userInteractive)
    let lock = NSLock()
    private var stream = StreamState()
    private let parser = HUDParser()
    private var connection: NWConnection?
    private var generation: UInt64 = 0
    private var received = 0.0, retry = 0.25
    private var lastToken: (UInt32, UInt64)?
    private var watchdog: DispatchSourceTimer?
    private var timers: [Timer] = []
    private var shown: DecodedHUD?
    private var eligible = false, focused = false
    private var requireReceivedAfter = 0.0
    private var frames = 0, transitionDrops = 0, lastStatus = 0.0
    private let maxAge = 0.25
    private let titleHeight: CGFloat
    private let port: NWEndpoint.Port
    private let frameMapping: String
    private let targetPID: Int32?
    private let root: URL

    override init() {
        let env = ProcessInfo.processInfo.environment
        root = URL(fileURLWithPath: env["PALCRAFT_BRIDGE_DIR"] ??
            "/path/to/workspace/work/minecraft-fusion/mac/drive_d/PalworldServer-LAN/PalCraft-Dev/bridge")
        titleHeight = CGFloat(Double(env["PALCRAFT_TITLEBAR_HEIGHT"] ?? "") ?? 28)
        port = NWEndpoint.Port(rawValue: UInt16(env["PALCRAFT_HUD_PORT"] ?? "") ?? 25603)!
        frameMapping = env["PALCRAFT_FRAME_NAME"] ?? "Local\\MCPassthroughFrame"
        targetPID = env["PALCRAFT_WINDOW_PID"].flatMap(Int32.init)
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
        for (interval, action) in [(0.1, self.position), (1.0 / 60.0, self.display)] {
            let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
            timers.append(timer)
            RunLoop.main.add(timer, forMode: .common)
        }
        position()
        network.async { self.connect() }
        let timer = DispatchSource.makeTimerSource(queue: network)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.connection != nil && ProcessInfo.processInfo.systemUptime - self.received > 1.5 {
                self.disconnect(self.generation, "frame timeout")
            }
        }
        watchdog = timer
        timer.resume()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timers.forEach { $0.invalidate() }
        network.async { self.watchdog?.cancel(); self.connection?.cancel() }
        try? "\(Date().timeIntervalSince1970) 0".write(
            to: root.appendingPathComponent("platform-focus.txt"), atomically: true, encoding: .utf8)
    }
    private func connect() {
        generation &+= 1
        let token = generation
        parser.reset()
        lastToken = nil
        received = ProcessInfo.processInfo.systemUptime
        let c = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        connection = c
        state { $0.generation = token; $0.connected = false }
        c.stateUpdateHandler = { [weak self] status in
            guard let self = self, self.generation == token else { return }
            switch status {
            case .ready:
                self.retry = 0.25
                self.state { $0.connected = true; $0.error = "" }
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
    private func read(_ c: NWConnection, _ token: UInt64) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self = self, self.generation == token, self.connection === c else { return }
            do {
                if let data = data, !data.isEmpty {
                    self.received = ProcessInfo.processInfo.systemUptime
                    if let packet = try self.parser.feed(data) { try self.decode(packet) }
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
        let now = ProcessInfo.processInfo.systemUptime
        let wallAge = packet.captureMS == 0 ? 0 : Date().timeIntervalSince1970 - Double(packet.captureMS) / 1000
        let sourceAge = max(0, wallAge)
        if wallAge < -1 || sourceAge > maxAge || (lastToken?.0 == packet.producer && lastToken!.1 >= packet.frame) {
            state { $0.rejected += 1 }
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
            $0.decodeMS += (ProcessInfo.processInfo.systemUptime - now) * 1000
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
        let now = ProcessInfo.processInfo.systemUptime
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
    private func position() {
        let now = ProcessInfo.processInfo.systemUptime, unix = Date().timeIntervalSince1970
        let front = NSWorkspace.shared.frontmostApplication
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let win = windows.first {
            ($0[kCGWindowOwnerName as String] as? String) == "Palworld-Win64-Shipping.exe" &&
            ($0[kCGWindowOwnerPID as String] as? Int32) == front?.processIdentifier &&
            (self.targetPID == nil || self.targetPID == front?.processIdentifier) &&
            ($0[kCGWindowLayer as String] as? Int ?? 0) == 0
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
                "connected": s.connected, "connection_generation": s.generation, "reconnects": s.reconnects,
                "packets": s.packets, "decoded": s.decoded, "dropped_batch": s.skipped, "dropped_mailbox": s.coalesced,
                "dropped_transition": transitionDrops, "rejected": s.rejected,
                "decode_ms_mean": s.decodeMS / Double(max(1, s.decoded)), "queue_capacity": 1,
                "protocol": shown?.packet.version ?? 0, "source_frame": shown?.packet.frame ?? 0,
                "host_frame": shown?.packet.hostFrame ?? 0, "producer": shown?.packet.producer ?? 0, "error": s.error,
                "frame_mapping": frameMapping, "port": port.rawValue,
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
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let old = try Data(contentsOf: root.appendingPathComponent("v1.bin"))
let modern = try Data(contentsOf: root.appendingPathComponent("v2.bin"))
let expected = try Data(contentsOf: root.appendingPathComponent("rgba.bin"))
var checks = 0
func check(_ value: Bool, _ why: String) {
    precondition(value, why)
    checks += 1
}
let legacy = HUDParser()
let p1 = try legacy.feed(old)!
check(p1.version == 1 && p1.width == 4 && p1.height == 3 && p1.bottomUp && p1.build, "v1 metadata")
check(try HUDParser.rgba(p1) == expected, "v1 premultiplied RGBA")
for split in 0 ... modern.count {
    let parser = HUDParser()
    let first = try parser.feed(Data(modern.prefix(split)))
    let second = try parser.feed(Data(modern.dropFirst(split)))
    let p = second ?? first!
    check(p.version == 2 && p.producer == 123 && p.frame == 42 && p.hostFrame == 991, "v2 arbitrary boundary")
    check(p.captureMS == 1000 && p.publishMS == 1001 && p.flags == 31, "v2 time/flags")
    check(try HUDParser.rgba(p) == expected, "v2 exact pixels")
    check(parser.pendingBytes == 0 && parser.packets == 1, "bounded partial bytes")
}
let coalesced = HUDParser()
let newest = try coalesced.feed(old + modern + modern)!
check(newest.version == 2 && coalesced.packets == 3 && coalesced.superseded == 2, "one newest packet per receive batch")
func fails(_ packet: Data, _ why: String) {
    do { _ = try HUDParser().feed(packet); preconditionFailure(why) } catch { checks += 1 }
}
var wrongVersion = modern; wrongVersion[5] = 3
fails(wrongVersion, "wrong version")
var wrongHeader = modern; wrongHeader[7] = 63
fails(wrongHeader, "wrong header size")
var noAlpha = modern; noAlpha[23] = 1
fails(noAlpha, "non-premultiplied/world packet")
var oversized = old; oversized[0] = 127
fails(oversized, "oversized width")
var hugePayload = old; hugePayload[8] = 127
fails(hugePayload, "oversized compressed payload")
var reversedTime = modern; reversedTime[48] = 127
fails(reversedTime, "capture after publish")
fails(Data(repeating: 0, count: HUDParser.maxBytes + 1), "bounded receive buffer")
let corrupt = HUDPacket(width: 4, height: 3, flags: 31, producer: 1, frame: 1, hostFrame: 1,
    captureMS: 1, publishMS: 1, version: 2, compressed: Data([1,2,3]))
do { _ = try HUDParser.rgba(corrupt); preconditionFailure("corrupt zlib") } catch { checks += 1 }
let trailing = HUDPacket(width: 4, height: 3, flags: 31, producer: 1, frame: 1, hostFrame: 1,
    captureMS: 1, publishMS: 1, version: 2, compressed: newest.compressed + Data([0]))
do { _ = try HUDParser.rgba(trailing); preconditionFailure("trailing zlib bytes") } catch { checks += 1 }
let wrongSize = HUDPacket(width: 5, height: 3, flags: 31, producer: 1, frame: 1, hostFrame: 1,
    captureMS: 1, publishMS: 1, version: 2, compressed: newest.compressed)
do { _ = try HUDParser.rgba(wrongSize); preconditionFailure("short inflated RGBA") } catch { checks += 1 }
print("{\"status\":\"passed\",\"swift_checks\":\(checks),\"wire_versions\":[1,2],\"max_receive_bytes\":\(HUDParser.maxBytes)}")
