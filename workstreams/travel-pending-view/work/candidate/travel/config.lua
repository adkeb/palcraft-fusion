-- Candidate BridgeLab regions. The centres are configuration, not a claim of live validation.
-- All distances are centimetres. Never changes UWorld, global weather, or the saved Pal map.
return {
 version=1, scale=100, y_origin=64, page_blocks=512,window_size=656,radius_blocks=64,below_blocks=16,above_blocks=32,
 prepare_timeout_ms=30000, replication_timeout_ms=15000, resend_ms=1000,
 position_tolerance_cm=50, server_settle_ms=100, kill_z_margin_cm=500,
 boundary_poll_ms=500,rebase_resend_ms=1000,
 world_bounds={-900000,-900000,-900000,900000,900000,900000},
 region_half_width_cm=32768,
 home_origin={X=-308099.9282280116,Y=187800.81696803804,Z=3421.3761104805685},
 -- Native Pal Overworld ground keeps the original transform across its valid envelope.
 native_overworld_window_size=32000,region_vertical_padding_cm=500,
 -- Only locations outside that envelope use the unvalidated auxiliary Overworld pool.
 dimensions={
  ['minecraft:overworld']={coordinate_scale=1,min_y=-64,max_y=320,
   center={X=-308099.9282280116,Y=187800.81696803804,Z=120000},profile='overworld'},
  ['minecraft:the_nether']={coordinate_scale=8,min_y=0,max_y=256,
   center={X=-108099.9282280116,Y=187800.81696803804,Z=120000},profile='nether'},
  ['minecraft:the_end']={coordinate_scale=1,min_y=0,max_y=256,
   center={X=91900.0717719884,Y=187800.81696803804,Z=120000},profile='end'},
 },
 slots={{0,0},{0,100000},{0,-100000},{0,200000}},
 environment_profiles={
  overworld={scope='local_camera',sky='minecraft:overworld',fog={0.75,0.85,1.0}},
  nether={scope='local_camera',sky='minecraft:the_nether',fog={0.2,0.03,0.03}},
  ['end']={scope='local_camera',sky='minecraft:the_end',fog={0.09,0.025,0.15}},
 },
 teleport_api='pal_utility',
 validation={centres='candidate_pending_lab_window',teleport='sdk_signature_verified_live_trip_pending'},
}
