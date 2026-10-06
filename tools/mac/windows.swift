import Cocoa
let all=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
for w in all {let p=w[kCGWindowOwnerName as String] as? String ?? ""; if p.localizedCaseInsensitiveContains("wine") || p.localizedCaseInsensitiveContains("Palworld") || p.localizedCaseInsensitiveContains("CrossOver") { print(w) }}
