import Cocoa
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID)as?[[String:Any]] ?? []
guard let w=windows.first(where:{($0[kCGWindowOwnerName as String]as?String)=="Palworld-Win64-Shipping.exe"}),let b=w[kCGWindowBounds as String]as?[String:CGFloat],let x=b["X"],let y=b["Y"],let pid=w[kCGWindowOwnerPID as String]as?Int32 else{fatalError("No PalCraft test window")}
NSRunningApplication(processIdentifier:pid)?.activate(options:[.activateAllWindows])
Thread.sleep(forTimeInterval:0.2)
if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
 let p=CGPoint(x:x+220,y:y+12)
 CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
 usleep(80000)
 CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
}
Thread.sleep(forTimeInterval:0.4)
print("Focused:",NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")
