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
