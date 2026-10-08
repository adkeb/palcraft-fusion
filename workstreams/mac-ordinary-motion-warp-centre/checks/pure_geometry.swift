import Foundation
import CoreGraphics
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

let g=MacForegroundGroup(version:1,token:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",game_pid:10,game_identity:"synthetic",helper_pid:11,helper_identity:"synthetic",helper_bundle_id:"synthetic",helper_bundle:"synthetic",native_process_epoch:"2852:123456",own_root:"synthetic",game_exe:"synthetic",private_user_dir:"synthetic")
var input:[String:Any]=["mouse_compatibility_mode":"relative-host-warp-v1","mouse_owner_token":g.token,"mouse_native_epoch":g.native_process_epoch,"mouse_host_eligible":true,"build":true,"focus":true,"menu":false,"unix":1000.0,"generation":9,"viewport_width":1280,"viewport_height":720,"mouse_win_geometry_valid":true,"mouse_win_window_x":116.0,"mouse_win_window_y":88.0,"mouse_win_window_width":1280.0,"mouse_win_window_height":748.0,"mouse_win_client_origin_x":120.0,"mouse_win_client_origin_y":117.0]
func make(_ i:[String:Any],buttons:Bool=false,front:Int32=10)->MacHostMousePlan?{
 MacHostMousePlan.make(input:i,group:g,groupAlive:true,frontPID:front,focused:true,cameraActive:true,renderAge:0.1,now:1000.1,buttonsDown:buttons,bounds:CGRect(x:116,y:88,width:1280,height:748),title:28)
}
let p=make(input)!;precondition(p.point==CGPoint(x:760,y:477));precondition(!p.observed(CGPoint(x:756,y:476)))
precondition(p.observed(CGPoint(x:760,y:477)))
precondition(make(input,buttons:true)==nil&&make(input,front:11)==nil)
input["menu"]=true;precondition(make(input)==nil);input["menu"]=false
input["mouse_win_geometry_valid"]=false;precondition(make(input)==nil)
print("actual native origin/window geometry maps client center; no fixed28px inference or fake observation; UI guards: PASS (synthetic)")
