from pathlib import Path
base=Path('work/minecraft-fusion/palcraft');client=base/'mc/src/client/java/dev/rehan/passthrough/client'
p=base/'client/main.lua';s=p.read_text().replace('PalCraftRender-v7.dll','PalCraftRender-v8.dll');s=s.replace('local f=assert(io.open(ROOT..\'camera.tmp\',\'wb\'))',"local grounded=pc.Pawn.CharacterMovement:IsMovingOnGround()\n local flags=enabled and(1+(grounded and 2 or 0))or 0\n local f=assert(io.open(ROOT..'camera.tmp','wb'))");s=s.replace("'PALCRFT1',1,enabled and 1 or 0,os.time()","'PALCRFT1',2,flags,os.time()");s=s.replace('vertical_fov=fov,enabled=enabled','vertical_fov=fov,enabled=enabled,grounded=grounded');p.write_text(s)
p=base/'render/palcraft.cpp';s=p.read_text().replace('version,enabled','version,flags').replace('c.version==1&&c.enabled','c.version==2&&(c.flags&1)');s=s.replace('\\\"h\\\":%.5f}', '\\\"h\\\":%.5f,\\\"g\\\":%s}');s=s.replace('c.px,c.py,c.pz,c.yaw);ws.send(b);','c.px,c.py,c.pz,c.yaw,(c.flags&2)?"true":"false");ws.send(b);');p.write_text(s)
p=client/'HostState.java';s=p.read_text().replace('boolean drive, float lookYaw, float lookPitch, boolean gun','boolean drive, float lookYaw, float lookPitch, boolean gun, boolean groundKnown, boolean grounded');s=s.replace('m.has("gun") && m.get("gun").getAsBoolean()','m.has("gun") && m.get("gun").getAsBoolean(),\n\t\t\tm.has("g"), m.has("g") && m.get("g").getAsBoolean()');p.write_text(s)
p=client/'PlayerSync.java';s=p.read_text();s=s.replace('\t\tplayer.setPos(x, y, z);','\t\tplayer.setPos(x, y, z);\n\t\tapplyGround(player);');s=s.replace('\t/**\n\t * Every client tick,', '''	/** Preserve host contact after Minecraft movement, before its movement packet and the next input tick. */
	public static void applyGround(final LocalPlayer player) {
		HostState.Pose p = HostState.live();
		if (p != null && !p.drive() && p.groundKnown()) player.setOnGround(p.grounded());
	}

	/**
	 * Every client tick,''');s=s.replace('interpolates and walks): in first person the player\'s eyes are at the host camera, in third person\n\t * their feet are at the host player\'s.','interpolates and walks): the player stands at the host feet in either camera mode.');p.write_text(s)
p=client/'mixin/LocalPlayerMixin.java';s=p.read_text().replace('\n}\n','''
	@Inject(method = "sendPosition", at = @At("HEAD"))
	private void palcraft$hostGround(final CallbackInfo ci) {
		PlayerSync.applyGround((LocalPlayer) (Object) this);
	}
}
''');p.write_text(s)
p=client/'ClientInput.java';s=p.read_text().replace('final class ClientInput {','''final class ClientInput {
    private static final java.util.Set<KeyMapping> held = new java.util.HashSet<>();

    static void releaseIfDetached() {
        if (HostState.live() != null) return;
        for (KeyMapping key : held) key.setDown(false);
        held.clear();
    }
''');s=s.replace('key.setDown(down);','key.setDown(down);\n                    if (down) held.add(key); else held.remove(key);');p.write_text(s)
p=client/'PassthroughClient.java';s=p.read_text().replace('an empty (void) creative world','an empty (void) survival world');s=s.replace('private static final String WORLD = "palcraft-test";','private static final String WORLD = System.getProperty("palcraft.world", "palcraft-test");');s=s.replace('private static void tick(final Minecraft minecraft) {','private static void tick(final Minecraft minecraft) {\n        ClientInput.releaseIfDetached();');s=s.replace('options.framerateLimit().set(60);','options.framerateLimit().set(Integer.getInteger("palcraft.maxFps", 60));');p.write_text(s)
p=client/'FrameExporter.java';s=p.read_text();s=s.replace('public static void captureWorld(final RenderTarget target) {','public static void captureWorld(final RenderTarget target) {\n        if (Boolean.getBoolean("palcraft.noFrameExport")) return;');s=s.replace('public static void captureOverlay(final RenderTarget target) {','public static void captureOverlay(final RenderTarget target) {\n        if (Boolean.getBoolean("palcraft.noFrameExport")) return;');p.write_text(s)
p=client/'HostLink.java';s=p.read_text().replace('report.addProperty("host_active",Passthrough.active);','''report.addProperty("host_active",Passthrough.active);
                    var pose=HostState.live();
                    if(pose!=null && pose.groundKnown()) report.addProperty("host_grounded",pose.grounded());''');p.write_text(s)
p=base/'mc/build.gradle';s=p.read_text();needle='\n\t}\n}\n\ndependencies';s=s.replace(needle,'''
        backgroundCheck {
            client()
            runDir "run-background-check"
            programArgs "--width", "640", "--height", "360", "--username", "PalCraftCheck", "--uuid", "00000000-0000-4000-8000-000000000029"
            vmArgs "--enable-native-access=ALL-UNNAMED", "-Xmx1G", "-Dpalcraft.hidden=true", "-Dpalcraft.maxFps=10", "-Dpalcraft.noFrameExport=true", "-Dpalcraft.world=background-check", "-Dpassthrough.port=25600"
        }
	}
}

dependencies''');p.write_text(s)
# Light matching sampled live image detail strongly enough to look like transparent wood. Use much blurrier ambient light.
p=base/'render/MCPassthrough.fx';s=p.read_text().replace('> = 0.8;','> = 0.25;').replace('ui_label = "Light colour"; > = 0.55;','ui_label = "Light colour"; > = 0.15;').replace('ui_label = "Light blur (mip)"; > = 3.2;','ui_label = "Light blur (mip)"; > = 6.0;');p.write_text(s)
print('Updated ground protocol v2, native input, background-check profile, and ambient-light defaults.')
