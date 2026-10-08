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
              input["mouse_win_window_x"] as? Double != nil, input["mouse_win_window_y"] as? Double != nil,
              let ww=input["mouse_win_window_width"] as? Double, let wh=input["mouse_win_window_height"] as? Double,
              let ox=input["mouse_win_client_origin_x"] as? Double, let oy=input["mouse_win_client_origin_y"] as? Double,
              ww > 0, wh > 0 else { return nil }
        let x=w/2, y=h/2
        // CrossOver client screen coordinates share the CG screen space; CGWindow bounds exclude Win borders.
        let point=CGPoint(x: CGFloat((ox+Double(x)).rounded()),
                          y: CGFloat((oy+Double(y)).rounded()))
        return MacHostMousePlan(point: point, x: x, y: y, width: w, height: h, generation: gen)
    }
    func initialCapture(input: [String: Any], previousScope: Int?) -> Bool {
        guard input["mouse_wm_point_established"] as? Bool == false,
              input["mouse_wm_generation"] as? Int == generation,
              let scope=input["mouse_wm_scope_serial"] as? Int, scope > 0 else { return false }
        return previousScope != scope
    }
    // A worker cursor query or arm acknowledgement is not consumption by the owned window hook.
    func consumed(input: [String: Any], cursor: CGPoint, afterSequence: Int = 0) -> Bool {
        guard !observed(cursor), input["mouse_wm_consumed"] as? Bool == true,
              input["mouse_wm_generation"] as? Int == generation,
              let seq=input["mouse_wm_sequence"] as? Int, seq > afterSequence,
              input["mouse_win_cursor_observed"] as? Bool == true,
              let wx=input["mouse_win_cursor_x"] as? Int, let wy=input["mouse_win_cursor_y"] as? Int,
              input["mouse_wm_client_x"] as? Int == wx, input["mouse_wm_client_y"] as? Int == wy,
              let ox=input["mouse_win_client_origin_x"] as? Double, let oy=input["mouse_win_client_origin_y"] as? Double else { return false }
        return abs(cursor.x-CGFloat(ox+Double(wx))) <= 0.5 && abs(cursor.y-CGFloat(oy+Double(wy))) <= 0.5
    }
    func observed(_ cursor: CGPoint) -> Bool {
        cursor.x.isFinite && cursor.y.isFinite && abs(cursor.x-point.x) <= 0.5 && abs(cursor.y-point.y) <= 0.5
    }
}

let plan=MacHostMousePlan(point:CGPoint(x:756,y:476),x:640,y:360,width:1280,height:720,generation:9)
var input:[String:Any]=["mouse_wm_point_established":false,"mouse_wm_generation":9,"mouse_wm_scope_serial":1]
precondition(plan.initialCapture(input:input,previousScope:nil))
precondition(!plan.initialCapture(input:input,previousScope:1))
input["mouse_wm_point_established"]=true;precondition(!plan.initialCapture(input:input,previousScope:nil))
input["mouse_wm_point_established"]=false;input["mouse_wm_generation"]=8;precondition(!plan.initialCapture(input:input,previousScope:nil))
print("actual initialCapture allows one current-scope pointless setup only; established/reused/foreign generation refuse initial path: PASS (synthetic)")
