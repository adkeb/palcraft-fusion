"""Produce guarded, independent owner proposals; never edit an owner's source."""
from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "material-pipeline/runtime-increment"
CLIENT = ROOT / "runtime-package/next9_2/payload/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts"
TARGET = "D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/"
records = []

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def replace_once(source, before, after):
    assert source.count(before) == 1, before[:120]
    return source.replace(before, after, 1)

def proposal(source, logical, target, transform, owner):
    raw = source.read_bytes()
    before = raw.decode()
    after = transform(before)
    assert before != after
    p = OUT / "proposals" / logical
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(after)
    patch = OUT / "patches" / (logical.replace("/", ".") + ".patch")
    patch.parent.mkdir(parents=True, exist_ok=True)
    patch.write_text("".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
        fromfile="a/" + logical, tofile="b/" + logical)))
    records.append(dict(logical=logical, base=str(source), base_sha256=digest(raw),
        proposal=str(p), proposal_sha256=digest(p.read_bytes()), patch=str(patch),
        patch_sha256=digest(patch.read_bytes()), target=target, owner=owner))

def pipeline(s):
    s = replace_once(s, " function api.attach_signs(options)", """ function api.remove_material_handler(entry)
  for i=#handlers,1,-1 do if handlers[i]==entry then table.remove(handlers,i);return true end end
  return false
 end
 function api.attach_signs(options)""")
    return replace_once(s, "actual_shader_verified=false}",
        "material_runtime=api.material_runtime and api.material_runtime.status(),actual_shader_verified=false}")

def companion(s):
    retry = """-- Material replies resume the existing logical block or dirty its existing
-- section. They never ingest a synthetic world row or replace a collider.
function M.retry_material_block(block)
 if M.chunk_consumer and M.chunk_consumer.retry_material_block
  and M.chunk_consumer.retry_material_block(block)==true then return true end
 if block.dim~=M.world.dimension then return true end
 local g=M.world:get(block.dim,block.x,block.y,block.z)
 local entry=M.block_render_entry(block.dim,{block.x,block.y,block.z})
 if not g or not entry or g.id~=block.id or g.state~=block.state or entry.visible==false or entry.model then return true end
 local ok,a,b=pcall(models.spawn,context(),O,g,block.x,block.y,block.z)
 if ok then entry.model=a;entry.model_component=a and b or nil;entry.model_status=a and'rendered'or b
 else entry.model_status='model_error: '..tostring(a)end
 if a and ok then M.changes=M.changes+1 end
 return true
end
"""
    s = replace_once(s, "local function apply(kind,x,y,z,geometry)", retry + "local function apply(kind,x,y,z,geometry)")
    s = replace_once(s, "(minecraft_renderer or entry.model or not visible)",
        "(minecraft_renderer or entry.model or not visible or(visual_pipeline and visual_pipeline.material_runtime))")
    s = replace_once(s, "     observe('on_row',row,accepted,reason,M)\n    end", """     observe('on_row',row,accepted,reason,M)
    elseif client and row.t=='material_tint'and visual_pipeline and visual_pipeline.material_runtime then
     -- This is the SAME authenticated native event journal and reader.
     local accepted,reason=visual_pipeline.accept_material_tint(row)
     M.material_reply_status={request_id=row.request_id,accepted=accepted,reason=reason}
    end""")
    return s

def metadata(s):
    return replace_once(s, "  tint_rgb=rgb,", """  tint_rgb=rgb,
  -- Pending colors cannot be merged across biome coordinates. After a reply,
  -- the existing tile rebuild merges by the actual RGB normally.
  authoritative_block=group.material_pending and group.authoritative_block or nil,
  material_pending=group.material_pending or nil,""")

def scheduler(s):
    return replace_once(s, "function Scheduler:retry()", """function Scheduler:invalidate_material(dim,at)
 local touched={};self:_touch(dim,at[1],at[2],at[3],touched)
 self:_publish(touched);return next(touched)~=nil
end
function Scheduler:retry()""")

def bridge(s):
    s = replace_once(s, " binding.status=function()return self:status()end", """ binding.status=function()return self:status()end
 binding.retry_material_block=function(block)
  local n=0;local at={block.x,block.y,block.z}
  for _,region in pairs(self.views.regions)do
   local b=region.window
   if not region.retiring and region.dim==block.dim and at[1]>=b[1]and at[1]<b[4]
    and at[2]>=b[2]and at[2]<b[5]and at[3]>=b[3]and at[3]<b[6]
    and region.scheduler:invalidate_material(block.dim,at)then n=n+1 end
  end
  return n>0
 end""")
    return s

def factory(s):
    s = replace_once(s, " local function thread()", """ local material_config=F.read(bridge_root..'material-runtime-v1.json')
 local material_options=o.material_options
 if material_config and material_config.enabled==true then
  assert(material_config.version==1,'Material runtime config version required')
  material_options=copy(material_config);material_options.json=J;material_options.bridge_root=bridge_root
 end
 if material_options then
  material_options=copy(material_options);material_options.json=J;material_options.bridge_root=bridge_root
  material_options.send_query=commands.send
 end
 local function thread()""")
    s = replace_once(s, " if options.chunk_enabled or options.fluid_enabled or options.sign_enabled then", 
        " if options.chunk_enabled or options.fluid_enabled or options.sign_enabled or material_options then")
    s = replace_once(s, "   if not v then self.reason=why;return end\n   local prepared,binding", """   if not v then self.reason=why;return end
   if material_options then
    local pipeline=c.visual_pipeline
    if not pipeline or not pipeline.add_material_handler or not pipeline.remove_material_handler then
     self.reason='material_pipeline_entry_pending';return
    end
    if not self.material_wiring then
     self.material_wiring=dofile(scripts..'material_live_wiring.lua').attach{models=assert(c.models),pipeline=pipeline,
      companion=c,material_options=material_options}
    end
    -- This is the actual current MC tuple, including hidden prepare while it
    -- waits for ACK. The existing WorldView transaction owns visible commit.
    pipeline.bind_material_scope{mc_uuid=v.player,world_session=v.world_session,dim=v.dim,view=v.view}
   end
   local prepared,binding""")
    s = replace_once(s, "    chunks=self.chunks and self.chunks.status(),in_game_verified=false}",
        "    chunks=self.chunks and self.chunks.status(),material_runtime=self.material_wiring and self.material_wiring.status(),in_game_verified=false}")
    return replace_once(s, "   self.stopped=true;self.started=false;early_rows={};", 
        "   if self.material_wiring then self.material_wiring.stop();self.material_wiring=nil end\n   self.stopped=true;self.started=false;early_rows={};")

def java(s):
    s = replace_once(s, "        if(lifecycle.get(\"waiting_ack\").getAsBoolean()||\n", """        // Read-only hidden prepare can sample before view ACK. The real client
        // level must already be in the current trusted dimension.
        if(!dim.equals(mc.level.dimension().identifier().toString())||
""")
    return s

OUT.mkdir(parents=True, exist_ok=True)
proposal(CLIENT / "native_visual_pipeline.lua", "client/native_visual_pipeline.lua", TARGET + "native_visual_pipeline.lua", pipeline, "native_renderer")
proposal(CLIENT / "palcraft-collisions.lua", "client/palcraft-collisions.lua", TARGET + "palcraft-collisions.lua", companion, "native_renderer")
proposal(CLIENT / "chunk_geometry.lua", "client/chunk_geometry.lua", TARGET + "chunk_geometry.lua", metadata, "chunk_scaling")
proposal(CLIENT / "chunk_scheduler.lua", "client/chunk_scheduler.lua", TARGET + "chunk_scheduler.lua", scheduler, "chunk_scaling")
proposal(CLIENT / "companion_chunk_bridge.lua", "client/companion_chunk_bridge.lua", TARGET + "companion_chunk_bridge.lua", bridge, "chunk_scaling")
proposal(ROOT / "client-factory/cold-reconnect/client_options.lua", "runtime/client_options.lua", TARGET + "runtime/client_options.lua", factory, "runtime_factory")
logical = "mc/MaterialTintFeature.java"
proposal(ROOT / "palcraft/mc/src/client/java/dev/rehan/passthrough/client/material/MaterialTintFeature.java", logical,
    "next MC candidate DLI classes/resources (integration owner build; not mods duplicate JAR)", java, "integration_build")
(OUT / "owner-patches.json").write_text(json.dumps(dict(version=1, owner_sources_modified=False, patches=records), indent=2) + "\n")
print(json.dumps(dict(status="independent_proposals_ready", patches=len(records), owner_sources_modified=False)))
