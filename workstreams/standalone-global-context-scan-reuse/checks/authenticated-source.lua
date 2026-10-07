local function authenticated_player(mc_uuid,proof)
  local table,why=authenticated_sessions();if not table then return nil,why end
  for _,r in ipairs(table.sessions or{})do
   if r.mc_uuid==mc_uuid and not r.legacy and P.uuid(r.pal_uid)and (r.expires_at or 0)>now()then
    if not proof or proof.mc_uuid~=r.mc_uuid or proof.pal_uid~=r.pal_uid or proof.world_id~=table.world_id
      or proof.server_session_id~=session or proof.session_id~=r.session_id or proof.generation~=r.generation then return nil,'source_connection_generation_mismatch'end
    for _,pc in ipairs(player_controllers())do
     if live(pc)and pc:HasAuthority()and guid(pc:GetPlayerUId())==r.pal_uid and live(pc.Pawn)then return pc.Pawn,r end
    end
   end
  end
  return nil,'unbound_or_offline_source_player'
 end
 return authenticated_player
