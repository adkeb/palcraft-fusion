package dev.rehan.passthrough.client;

import com.google.gson.*;
import dev.rehan.passthrough.client.visual.VanillaEntityCapture;
import java.io.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.Consumer;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.resources.Identifier;
import net.minecraft.world.entity.Entity;

/** Bounded capture invoked by the existing render thread and authenticated
 * HostLink connection. No service, new login, authority or entity mutation. */
public final class EntityCaptureExporter {
    private static final Gson JSON=new Gson();
    private static final String PRODUCER=UUID.randomUUID().toString();
    private static final Path ROOT=Path.of(System.getProperty("palcraft.bridgeDir","D:/PalworldServer-LAN/PalCraft-Dev/bridge"),"entity-capture-v1");
    private record Binding(String uuid,String session,String dim,long view,String mapping,int[] bounds,long guestEpoch,Consumer<JsonObject> send){}
    private record Texture(String sha,int bytes,byte[] png){}
    private static Binding binding;
    private static boolean initialized;
    private static long epoch,seq,nextFrame;
    private static final Map<String,JsonObject> captures=new LinkedHashMap<>();
    private static final Map<String,Long> capturedAt=new HashMap<>();
    private static final Map<String,Texture> textures=new HashMap<>();
    private static final Set<String> sentTextures=new HashSet<>();
    private static final int PER_FRAME=2,MAX_ENTITIES=64,MAX_VERTICES=60000,ASSET_CHUNK=48*1024,MAX_PNG=8*1024*1024,MAX_CACHE=8*1024*1024;
    private EntityCaptureExporter(){}
    public static void initialize(){
        if(initialized)return;initialized=true;
        ClientPlayConnectionEvents.DISCONNECT.register((handler,client)->unbind());
    }
    /** This call is inside HostLink's existing execute/lease fence. The current
     * world tuple is obtained from ClientBridge, not trusted from the request. */
    public static void bind(JsonObject request,Consumer<JsonObject> sender){
        JsonObject trusted=ClientBridge.trustedWorldView();Minecraft mc=Minecraft.getInstance();
        if(trusted==null||mc.player==null||!GuestSession.ready())throw new IllegalStateException("Authenticated entity view unavailable");
        JsonObject view=trusted.getAsJsonObject("world_view");
        if(view.get("waiting_ack").getAsBoolean()
          ||!request.get("mc_uuid").getAsString().equals(mc.player.getUUID().toString())
          ||!request.get("world_session").getAsString().equals(view.get("world_session").getAsString())
          ||!request.get("dim").getAsString().equals(view.get("dim").getAsString())
          ||request.get("view").getAsLong()!=view.get("view").getAsLong())throw new IllegalArgumentException("Entity capture view differs from accepted world");
        if(request.has("op")&&request.get("op").getAsString().equals("unbind")){unbind();return;}
        JsonArray array=request.getAsJsonArray("bounds");int[] bounds=new int[6];
        if(array.size()!=6)throw new IllegalArgumentException("Native view bounds required");
        for(int i=0;i<6;i++)bounds[i]=array.get(i).getAsInt();
        for(int i=0;i<3;i++)if(bounds[i]>=bounds[i+3])throw new IllegalArgumentException("Empty capture view");
        String mapping=request.get("mapping").getAsString();if(mapping.isBlank())throw new IllegalArgumentException("Committed mapping required");
        binding=new Binding(mc.player.getUUID().toString(),view.get("world_session").getAsString(),view.get("dim").getAsString(),view.get("view").getAsLong(),mapping,bounds,GuestSession.epoch(),sender);
        epoch++;seq=0;captures.clear();capturedAt.clear();sentTextures.clear();nextFrame=0;
    }
    public static void unbind(){binding=null;epoch++;captures.clear();capturedAt.clear();sentTextures.clear();nextFrame=0;}
    public static void invalidateResources(){epoch++;seq=0;captures.clear();textures.clear();sentTextures.clear();capturedAt.clear();nextFrame=0;}
    private static JsonObject envelope(String type,Binding b){
        JsonObject result=new JsonObject();result.addProperty("t",type);result.addProperty("schema",1);
        result.addProperty("source","minecraft:entity_renderer_capture_v1");result.addProperty("read_only",true);
        result.addProperty("mc_uuid",b.uuid);result.addProperty("world_session",b.session);result.addProperty("dim",b.dim);
        result.addProperty("view",b.view);result.addProperty("mapping",b.mapping);result.addProperty("producer",PRODUCER);
        result.addProperty("epoch",epoch);result.addProperty("seq",++seq);result.addProperty("created_ms",System.currentTimeMillis());return result;
    }
    private static boolean inside(Entity entity,int[] b){return entity.getX()>=b[0]&&entity.getY()>=b[1]&&entity.getZ()>=b[2]&&entity.getX()<b[3]&&entity.getY()<b[4]&&entity.getZ()<b[5];}
    private static boolean current(Binding b){
        if(b!=binding||b.guestEpoch!=GuestSession.epoch()||!GuestSession.ready())return false;
        JsonObject trusted=ClientBridge.trustedWorldView();if(trusted==null)return false;JsonObject v=trusted.getAsJsonObject("world_view");
        return !v.get("waiting_ack").getAsBoolean()&&v.get("world_session").getAsString().equals(b.session)&&v.get("dim").getAsString().equals(b.dim)&&v.get("view").getAsLong()==b.view;
    }
    private static Texture texture(Minecraft mc,String id)throws Exception {
        Texture old=textures.get(id);if(old!=null)return old;
        Identifier location=Identifier.parse(id);var resource=mc.getResourceManager().getResource(location);
        if(resource.isEmpty()){
            String reason=location.getPath().contains("atlas/")?"generated_atlas_cpu_export_missing":location.getPath().contains("skin")?"dynamic_skin_cpu_resource_missing":"resource_pack_png_missing";
            throw new IOException(reason+":"+id);
        }
        byte[] data;try(InputStream in=resource.get().open()){data=in.readNBytes(MAX_PNG+1);}
        if(data.length>MAX_PNG||data.length<8||data[0]!=(byte)0x89||data[1]!='P'||data[2]!='N'||data[3]!='G')throw new IOException("not_bounded_png:"+id);
        String sha=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
        Files.createDirectories(ROOT.resolve("textures"));Path tmp=ROOT.resolve("textures/"+sha+".tmp"),target=ROOT.resolve("textures/"+sha+".png");
        if(!Files.exists(target)){Files.write(tmp,data);Files.move(tmp,target,StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);}
        Texture result=new Texture(sha,data.length,data);textures.put(id,result);return result;
    }
    private static void sendTexture(Binding b,String id,Texture texture){
        if(sentTextures.contains(texture.sha))return;
        int chunks=(texture.bytes+ASSET_CHUNK-1)/ASSET_CHUNK;
        for(int index=0;index<chunks;index++){
            JsonObject message=envelope("entity_visual_asset",b);message.addProperty("resource",id);message.addProperty("sha256",texture.sha);
            message.addProperty("bytes",texture.bytes);message.addProperty("index",index);message.addProperty("chunks",chunks);
            message.addProperty("base64",Base64.getEncoder().encodeToString(Arrays.copyOfRange(texture.png,index*ASSET_CHUNK,Math.min(texture.bytes,(index+1)*ASSET_CHUNK))));
            b.send.accept(message);
        }
        sentTextures.add(texture.sha);
    }
    /** Actual LevelRenderer.render TAIL hook; all renderer/model work stays on
     * the existing client render thread. It is inert without a bound host view. */
    public static void frame(Minecraft mc,CameraRenderState camera){
        Binding b=binding;if(!initialized||b==null)return;
        if(!current(b)||mc.level==null||mc.player==null){unbind();return;}
        long now=System.currentTimeMillis();if(now<nextFrame)return;nextFrame=now+100;
        List<Entity> entities=new ArrayList<>();for(Entity entity:mc.level.entitiesForRendering())if(entity!=mc.player&&entity.isAlive()&&inside(entity,b.bounds))entities.add(entity);
        entities.sort(Comparator.comparingDouble(e->e.distanceToSqr(mc.player)));
        int scopedEntities=entities.size();
        if(entities.size()>MAX_ENTITIES)entities=entities.subList(0,MAX_ENTITIES);
        entities.sort(Comparator.comparingLong(e->capturedAt.getOrDefault(e.getUUID().toString(),0L)));
        Set<String> present=new HashSet<>();for(Entity entity:entities)present.add("mc:"+entity.getUUID());
        captures.keySet().removeIf(id->!present.contains(id));
        for(int index=0;index<Math.min(PER_FRAME,entities.size());index++){
            Entity entity=entities.get(index);String id="mc:"+entity.getUUID();JsonObject row=new JsonObject();row.addProperty("id",id);
            row.addProperty("dimension",b.dim);row.addProperty("captured_ms",now);
            try{
                JsonObject capture=JSON.toJsonTree(VanillaEntityCapture.entity(entity,camera.cameraEntityPartialTicks,camera,MAX_VERTICES)).getAsJsonObject();
                capture.addProperty("captured_ms",now);capture.addProperty("seq",PRODUCER+":"+epoch+":"+(++seq));
                JsonObject resolved=new JsonObject();JsonArray errors=new JsonArray();
                for(JsonElement element:capture.getAsJsonArray("batches")){
                    JsonObject batch=element.getAsJsonObject(),bindings=batch.getAsJsonObject("textures");
                    if(!bindings.has("Sampler0"))errors.add("renderer_batch_without_primary_texture:"+batch.get("render_type_name"));
                    for(var entry:bindings.entrySet())try{
                        String resource=entry.getValue().getAsString();Texture pixels=texture(mc,resource);sendTexture(b,resource,pixels);
                        JsonObject asset=new JsonObject();asset.addProperty("sha256",pixels.sha);asset.addProperty("bytes",pixels.bytes);resolved.add(resource,asset);
                    }catch(Exception exception){errors.add(exception.getMessage());}
                }
                row.add("frame",capture);row.add("textures",resolved);row.add("resource_errors",errors);
                row.addProperty("available",capture.get("vertices").getAsInt()>0&&errors.isEmpty());
                if(capture.get("vertices").getAsInt()==0)row.addProperty("error","renderer_submitted_no_supported_geometry");
            }catch(Exception exception){row.addProperty("available",false);row.addProperty("error",exception.toString());}
            captures.put(id,row);capturedAt.put(entity.getUUID().toString(),now);
        }
        if(!current(b))return;
        JsonObject message=envelope("entity_visual_cache",b);JsonArray rows=new JsonArray();for(JsonObject row:captures.values())rows.add(row);
        message.addProperty("complete",true);message.addProperty("available",true);message.add("rows",rows);message.addProperty("pending_entities",present.size()-captures.size());
        message.addProperty("scoped_entities",scopedEntities);message.addProperty("budget_skipped_entities",Math.max(0,scopedEntities-MAX_ENTITIES));
        byte[] data=message.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
        if(data.length>MAX_CACHE){
            // Explicit unavailable replacement, never a silently cropped success.
            message.add("rows",new JsonArray());message.addProperty("available",false);
            message.addProperty("error","entity_visual_cache_byte_budget_exceeded");message.addProperty("required_bytes",data.length);
            b.send.accept(message);return;
        }
        if(data.length<=ASSET_CHUNK){b.send.accept(message);return;}
        try{
            String digest=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
            int chunks=(data.length+ASSET_CHUNK-1)/ASSET_CHUNK;
            for(int index=0;index<chunks;index++){
                JsonObject packet=envelope("entity_visual_cache_chunk",b);packet.addProperty("sha256",digest);packet.addProperty("bytes",data.length);
                packet.addProperty("index",index);packet.addProperty("chunks",chunks);
                packet.addProperty("base64",Base64.getEncoder().encodeToString(Arrays.copyOfRange(data,index*ASSET_CHUNK,Math.min(data.length,(index+1)*ASSET_CHUNK))));
                b.send.accept(packet);
            }
        }catch(java.security.NoSuchAlgorithmException exception){throw new IllegalStateException(exception);}
    }
}
