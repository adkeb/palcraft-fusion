package dev.rehan.passthrough.client;

import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.WorldBridge;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.Optional;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.fabric.api.networking.v1.ServerPlayConnectionEvents;
import net.minecraft.client.CloudStatus;
import net.minecraft.client.InactivityFpsLimit;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Options;
import org.lwjgl.sdl.SDLVideo;
import net.minecraft.client.gui.screens.DeathScreen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.client.tutorial.TutorialSteps;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.HolderSet;
import net.minecraft.core.registries.Registries;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.LevelSettings;
import net.minecraft.world.level.WorldDataConfiguration;
import net.minecraft.world.level.biome.Biomes;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.levelgen.FlatLevelSource;
import net.minecraft.world.level.levelgen.WorldDimensions;
import net.minecraft.world.level.levelgen.WorldOptions;
import net.minecraft.world.level.levelgen.flat.FlatLayerInfo;
import net.minecraft.world.level.levelgen.flat.FlatLevelGeneratorSettings;
import net.minecraft.world.level.levelgen.presets.WorldPresets;

public class PassthroughClient implements ClientModInitializer {
	/** The world the host plays in: an empty (void) survival world, so only what the player builds is Minecraft. */
	private static final String WORLD = System.getProperty("palcraft.world", "palcraft-test");
	/** Run on the server once the player has joined. */
	private static final List<String> SETUP = List.of(
		"gamerule send_command_feedback false",
		"gamerule log_admin_commands false",
		"gamerule show_advancement_messages false",
		"gamerule player_movement_check false"
	);
	/** Retains the original demonstration world only when explicitly requested. */
	private static final List<String> LEGACY_STATIC_SETUP = List.of(
		"gamerule advance_time false",
		"gamerule advance_weather false",
		"gamerule spawn_mobs false",
		"gamerule spawn_monsters false",
		"gamerule spawn_patrols false",
		"gamerule spawn_phantoms false",
		"gamerule spawn_wandering_traders false",
		"gamerule keep_inventory true",
		"difficulty normal",
		"time set noon",
		"weather clear"
	);
	private static boolean configured;
	private static boolean worldRequested;
	/** Server ticks until the setup commands run (the player isn't in the player list yet when JOIN fires). */
	private static int setupIn = -1;
	private static int respawnIn;
	private static boolean hidden;
    private static int reconnectTicks;
    private static long powerPollAt;
    private static String powerSeen;

	@Override
	public void onInitializeClient() {
        Passthrough.hostMovesPlayer = true;
		HostLink.launch();
        ClientBridge.initialize();
        EntityCaptureExporter.initialize();
        dev.rehan.passthrough.client.signtext.SignTextExporter.initialize();
		ClientTickEvents.END_CLIENT_TICK.register(PassthroughClient::tick);
		ServerPlayConnectionEvents.JOIN.register((handler, sender, server) -> {
			ServerPlayer player = handler.player;
			// never left gliding from a previous session: with no host yet it would glide down into the void
			player.stopFallFlying();
			setupIn = 10;
		});
		ServerTickEvents.END_SERVER_TICK.register(server -> {
			if (setupIn > 0 && --setupIn == 0) {
				SETUP.forEach(WorldBridge::command);
				if(Boolean.getBoolean("palcraft.legacyStaticWorld"))LEGACY_STATIC_SETUP.forEach(WorldBridge::command);
			}
		});
	}

	private static void tick(final Minecraft minecraft) {
        ClientInput.releaseIfDetached();
        PlayFeedback.tick(minecraft);
        ClientBridge.tick(minecraft);
        ClientPalLife.suppressDeathScreen(minecraft);
		if (Boolean.getBoolean("palcraft.hidden") && !hidden) {
			SDLVideo.SDL_HideWindow(minecraft.getWindow().handle());
			hidden = true;
		}
		// a death (the void) would leave the death screen over the host's picture: respawn straight away
		if (minecraft.player != null && !ClientPalLife.mirrorsCurrentPlayer() && minecraft.gui.screen() instanceof DeathScreen && --respawnIn <= 0) {
			respawnIn = 40;
			minecraft.player.respawn();
		}

		if (!configured) {
			configured = true;
			configure(minecraft.options);
		}
        applyOwnedPerformance(minecraft.options);

        // A shared-world restart leaves Palworld running; reconnect this guest automatically.
        String sharedAddress=System.getProperty("palcraft.server","");
        if(!sharedAddress.isBlank()&&minecraft.level==null&&minecraft.gui.screen() instanceof net.minecraft.client.gui.screens.DisconnectedScreen){
            if(++reconnectTicks>=100){reconnectTicks=0;connectShared(minecraft,sharedAddress);}
        }else reconnectTicks=0;
		if (!worldRequested && minecraft.level == null && minecraft.gui.screen() instanceof TitleScreen && !Boolean.getBoolean("passthrough.noAutoWorld")) {
			worldRequested = true;
            String shared=System.getProperty("palcraft.server","");
            if(!shared.isBlank())connectShared(minecraft,shared);
            else openWorld(minecraft);
		}
	}

    private static void connectShared(Minecraft mc,String address){
        net.minecraft.client.gui.screens.ConnectScreen.startConnecting(mc.gui.screen(),mc,net.minecraft.client.multiplayer.resolver.ServerAddress.parseString(address),new net.minecraft.client.multiplayer.ServerData("PalCraft shared world",address,net.minecraft.client.multiplayer.ServerData.Type.LAN),false,null);
    }

    /** Runs in this existing guest's client tick; it cannot launch or select another guest. */
    private static void applyOwnedPerformance(Options options) {
        String directory = System.getenv("PALCRAFT_PERFORMANCE_DIR");
        if (directory == null || !"mc_guest".equals(System.getenv("PALCRAFT_PERFORMANCE_ROLE"))) return;
        long now = System.nanoTime();
        if (now < powerPollAt) return;
        powerPollAt = now + 250_000_000L;
        JsonObject request = null;
        Path dir = Path.of(directory);
        try {
            String token = System.getenv("PALCRAFT_PERFORMANCE_TOKEN");
            String rootID = System.getenv("PALCRAFT_PERFORMANCE_ROOT_ID");
            if (System.currentTimeMillis() - Files.getLastModifiedTime(dir.getParent().resolve(token + ".heartbeat")).toMillis() > 12_000) return;
            request = JsonParser.parseString(Files.readString(dir.resolve("request.json"))).getAsJsonObject();
            if (!"palcraft-owned-live-performance-v1".equals(request.get("kind").getAsString()) ||
                !token.equals(request.get("token").getAsString()) || !rootID.equals(request.get("root_id").getAsString()) ||
                request.get("expires_unix").getAsDouble() * 1000 <= System.currentTimeMillis()) return;
            String id = request.get("request_id").getAsString();
            if (!id.matches("[a-f0-9]{32}") || id.equals(powerSeen)) return;
            powerSeen = id;
            JsonObject target = request.getAsJsonObject("targets");
            int fps = target.get("mc_fps").getAsInt();
            if (fps < 1 || fps > 60 || fps != target.get("mc_fps").getAsDouble()) throw new IllegalArgumentException("MC FPS must be 1..60");
            Integer distance = target.has("mc_render_distance") ? target.get("mc_render_distance").getAsInt() : null;
            if (distance != null && (distance < 2 || distance > 32 || distance != target.get("mc_render_distance").getAsDouble())) throw new IllegalArgumentException("MC render distance must be 2..32");
            if (target.has("mc_muted") && !target.get("mc_muted").getAsJsonPrimitive().isBoolean()) throw new IllegalArgumentException("MC mute must be boolean");
            options.framerateLimit().set(fps);
            if (distance != null) options.renderDistance().set(distance);
            if (target.has("mc_muted")) options.getSoundSourceOptionInstance(net.minecraft.sounds.SoundSource.MASTER).set(target.get("mc_muted").getAsBoolean() ? 0.0 : 1.0);
            JsonObject actual = new JsonObject();
            actual.addProperty("mc_fps", options.framerateLimit().get());
            actual.addProperty("mc_render_distance", options.renderDistance().get());
            double volume = options.getSoundSourceOptionInstance(net.minecraft.sounds.SoundSource.MASTER).get();
            actual.addProperty("mc_master_volume", volume);
            actual.addProperty("mc_muted", volume == 0);
            boolean applied = options.framerateLimit().get() == fps && (distance == null || options.renderDistance().get().equals(distance)) &&
                (!target.has("mc_muted") || (volume == 0) == target.get("mc_muted").getAsBoolean());
            publishPower(dir, request, applied, actual, applied ? null : "Actual options rejected the requested value");
        } catch (Exception error) {
            if (request != null && powerSeen != null && request.has("request_id") && powerSeen.equals(request.get("request_id").getAsString())) {
                try { publishPower(dir, request, false, new JsonObject(), error.toString()); } catch (Exception ignored) { }
            }
        }
    }

    private static void publishPower(Path dir, JsonObject request, boolean ok, JsonObject actual, String error) throws java.io.IOException {
        JsonObject result = new JsonObject();
        for (String key : List.of("schema", "kind", "root_id", "token", "request_id")) result.add(key, request.get(key));
        result.addProperty("role", "mc_guest"); result.addProperty("pid", ProcessHandle.current().pid());
        result.addProperty("ok", ok); result.add("actual", actual);
        if (error != null) result.addProperty("error", error);
        Path pending = dir.resolve("mc_guest.tmp"), target = dir.resolve("mc_guest.json");
        Files.writeString(pending, result.toString());
        try { Files.move(pending, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }
        catch (java.nio.file.AtomicMoveNotSupportedException unavailable) { Files.move(pending, target, StandardCopyOption.REPLACE_EXISTING); }
    }

	/** Settings for sitting behind another game: keep running unfocused, and no sky/cloud/bobbing effects in the picture. */
	private static void configure(final Options options) {
		options.pauseOnLostFocus = false;
		options.onboardAccessibility = false;
		options.tutorialStep = TutorialSteps.NONE;
		options.cloudStatus().set(CloudStatus.OFF);
		options.bobView().set(false);
		options.vignette().set(false);
		options.improvedTransparency().set(false);
		options.inactivityFpsLimit().set(InactivityFpsLimit.MINIMIZED);
		options.fovEffectScale().set(0.0);
		options.damageTiltStrength().set(0.0);
		options.menuBackgroundBlurriness().set(0);
		options.enableVsync().set(false);
		// the host shows ~60-120 fps: rendering faster only competes with it for the GPU
		options.framerateLimit().set(Integer.getInteger("palcraft.maxFps", 15));
		options.renderDistance().set(Math.clamp(Integer.getInteger("palcraft.renderDistance",4),2,32));
		options.simulationDistance().set(Math.clamp(Integer.getInteger("palcraft.simulationDistance",5),5,32));
		options.getSoundSourceOptionInstance(net.minecraft.sounds.SoundSource.MASTER).set(0.0);
		options.getSoundSourceOptionInstance(net.minecraft.sounds.SoundSource.MUSIC).set(0.0);
		options.save();
	}

	private static void openWorld(final Minecraft minecraft) {
		if (minecraft.getLevelSource().levelExists(WORLD)) {
			Passthrough.LOG.info("opening world {}", WORLD);
			minecraft.createWorldOpenFlows().openWorld(WORLD, () -> minecraft.gui.setScreen(new TitleScreen()));
		} else {
			Passthrough.LOG.info("creating world {}", WORLD);
			LevelSettings settings = new LevelSettings("PalCraft", GameType.SURVIVAL, LevelSettings.DifficultySettings.DEFAULT, true, WorldDataConfiguration.DEFAULT);
			minecraft.createWorldOpenFlows().createFreshLevel(WORLD, settings, new WorldOptions(0L, false, false), PassthroughClient::voidWorld, minecraft.gui.screen());
		}
	}

	/** A flat world with a single layer of air: nothing but what gets built (the host's ground arrives as barriers). */
	private static WorldDimensions voidWorld(final HolderLookup.Provider registries) {
		FlatLevelGeneratorSettings flat = new FlatLevelGeneratorSettings(
			Optional.of(HolderSet.direct()), registries.lookupOrThrow(Registries.BIOME).getOrThrow(Biomes.PLAINS), List.of()
		);
		flat.getLayersInfo().add(new FlatLayerInfo(1, Blocks.AIR));
		flat.updateLayers();
		return WorldPresets.createNormalWorldDimensions(registries).replaceOverworldGenerator(registries, new FlatLevelSource(flat));
	}
}
