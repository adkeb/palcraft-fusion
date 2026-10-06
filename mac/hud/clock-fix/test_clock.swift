import Foundation
var checks=0
func check(_ v:Bool,_ why:String){precondition(v,why);checks+=1}
let local:UInt64=1_000_000_000_000_000
let remote:UInt64=1_791_226_000_000_000_000
var clock=HUDClock()
check(clock.observe(sent:local,received:local+20_000_000,remoteReceived:remote,remoteSent:remote),"valid bounded calibration")
let now=Double(local+20_000_000)/1e9
let captured=(remote-100_000_000)/1_000_000
let age=clock.ageUpperBound(captureMS:captured,now:now)!
check(abs(age-0.12)<0.000001,"source capture age plus10ms uncertainty, independent of two wall clocks")
check(clock.uncertainty == 0.01,"RTT uncertainty")
check(clock.ageUpperBound(captureMS:(remote-400_000_000)/1_000_000,now:now)!>0.25,"actual old frame remains stale")
var slow=HUDClock()
check(!slow.observe(sent:local,received:local+1_800_000_000,remoteReceived:remote,remoteSent:remote),"SSH1.8s cannot certify freshness")
check(slow.ageUpperBound(captureMS:captured,now:now)==nil,"uncalibrated never called fresh")
check(!clock.observe(sent:local,received:local+1,remoteReceived:remote+2,remoteSent:remote),"backward server clock rejected")
check(clock.ageUpperBound(captureMS:captured,now:now+31)==nil,"calibration expires")
let local2=local+11_000_000_000,remote2=remote+13_000_000_000
check(clock.observe(sent:local2,received:local2+20_000_000,remoteReceived:remote2,remoteSent:remote2),"resync afterremote wall step")
check(abs(clock.ageUpperBound(captureMS:(remote2-100_000_000)/1_000_000,now:Double(local2+20_000_000)/1e9)!-0.12)<0.000001,"new source epoch mapped to same monotonic")
print("{\"status\":\"passed\",\"clock_checks\":\(checks),\"old_250ms_frames_rejected\":true,\"cross_os_wall_dependency\":false}")
