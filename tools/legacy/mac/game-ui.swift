import Cocoa
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
guard let w=windows.first(where:{($0[kCGWindowOwnerName as String] as? String)=="Palworld-Win64-Shipping.exe"}),let pid=w[kCGWindowOwnerPID as String] as? Int32,let id=w[kCGWindowNumber as String] as? UInt32 else{fatalError("No Palworld test window")}
print("pid=\(pid) window=\(id) name=\(w[kCGWindowName as String] ?? "")")
if CommandLine.arguments.count>1 {
 for arg in CommandLine.arguments.dropFirst() {let key=CGKeyCode(arg)!
 NSRunningApplication(processIdentifier:pid)?.activate(options:[.activateAllWindows])
 usleep(200000)
 CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true)?.post(tap:.cghidEventTap)
 usleep(100000)
 CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:false)?.post(tap:.cghidEventTap)
 usleep(150000)
 }
}
let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");p.arguments=["-x","-l",String(id),"/path/to/workspace/work/minecraft-fusion/mac/window.png"];try p.run();p.waitUntilExit()
