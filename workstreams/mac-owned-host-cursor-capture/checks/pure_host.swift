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
              w > 0, h > 0, let bounds = bounds, bounds.width > 0, bounds.height > title else { return nil }
        let x=w/2, y=h/2
        let point=CGPoint(x: bounds.minX + CGFloat(x)/CGFloat(w)*bounds.width,
                          y: bounds.minY + title + CGFloat(y)/CGFloat(h)*(bounds.height-title))
        return MacHostMousePlan(point: point, x: x, y: y, width: w, height: h, generation: gen)
    }
    func observed(_ cursor: CGPoint) -> Bool {
        cursor.x.isFinite && cursor.y.isFinite && abs(cursor.x-point.x) <= 0.5 && abs(cursor.y-point.y) <= 0.5
    }
}

let group=MacForegroundGroup(version:1,token:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",game_pid:10,game_identity:"synthetic-game",helper_pid:11,helper_identity:"synthetic-helper",helper_bundle_id:"synthetic.bundle",helper_bundle:"synthetic.app",native_process_epoch:"1234:998877",own_root:"synthetic-root",game_exe:"synthetic-exe",private_user_dir:"synthetic-userdir")
var input:[String:Any]=["mouse_compatibility_mode":"relative-host-warp-v1","mouse_owner_token":group.token,"mouse_native_epoch":group.native_process_epoch,"mouse_host_eligible":true,"build":true,"focus":true,"menu":false,"unix":1000.0,"generation":8,"viewport_width":1280,"viewport_height":720]
func make(_ value:[String:Any],front:Int32=10,focus:Bool=true,buttons:Bool=false,now:Double=1000.1)->MacHostMousePlan?{
 return MacHostMousePlan.make(input:value,group:group,groupAlive:true,frontPID:front,focused:focus,cameraActive:true,renderAge:0.1,now:now,buttonsDown:buttons,bounds:CGRect(x:100,y:100,width:1600,height:928),title:28)
}
let p=make(input)!;precondition(p.point==CGPoint(x:900,y:578)&&p.x==640&&p.y==360)
precondition(p.observed(CGPoint(x:900,y:578)) && !p.observed(CGPoint(x:1498,y:578)))
precondition(make(input,front:11)==nil&&make(input,focus:false)==nil&&make(input,buttons:true)==nil)
precondition(make(input,now:1001)==nil)
input["menu"]=true;precondition(make(input)==nil);input["menu"]=false
input["mouse_host_eligible"]=false;precondition(make(input)==nil);input["mouse_host_eligible"]=true
input["mouse_owner_token"]="foreign";precondition(make(input)==nil)
print("real production HUD eligibility, header/scale center mapping and observed position confirmation: PASS (no GUI/warp)")
