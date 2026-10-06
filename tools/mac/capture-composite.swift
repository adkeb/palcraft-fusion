import Cocoa
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID)as?[[String:Any]] ?? []
guard let w=windows.first(where:{($0[kCGWindowOwnerName as String]as?String)=="Palworld-Win64-Shipping.exe"}),let b=w[kCGWindowBounds as String]as?[String:CGFloat],let x=b["X"],let y=b["Y"],let width=b["Width"],let height=b["Height"] else {fatalError("no game")}
let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");p.arguments=["-x","-R\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))","/path/to/workspace/work/minecraft-fusion/mac/composite.png"];try p.run();p.waitUntilExit();print("Captured game composite")
