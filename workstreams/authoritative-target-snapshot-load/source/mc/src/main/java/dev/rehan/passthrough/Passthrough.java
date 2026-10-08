package dev.rehan.passthrough;

import java.util.function.Consumer;
import java.util.List;
import dev.rehan.passthrough.session.BridgeSessions;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerEntityEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerLifecycleEvents;
import net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents;
import net.fabricmc.fabric.api.entity.event.v1.ServerPlayerEvents;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Passthrough implements ModInitializer {
	public static final String ID = "passthrough";
	public static final Logger LOG = LoggerFactory.getLogger(ID);
	/** True while a host game is driving the camera. The integrated server shares this JVM, so both sides read it. */
	public static volatile boolean active;
	/** The guest avatar follows host physics, including while waiting for the host to reconnect. */
	public static volatile boolean hostMovesPlayer;
	/** Where events for the host go (JSON lines); the client's HostLink sets it. */
	public static volatile Consumer<String> events = message -> {};
	private record ServerFeature(String name, Runnable initialize, Consumer<net.minecraft.server.MinecraftServer> start,
		Consumer<net.minecraft.server.MinecraftServer> tick, Consumer<net.minecraft.server.MinecraftServer> stop) {}

	@Override
	public void onInitialize() {
		List<ServerFeature> features = List.of(
			new ServerFeature("network", BridgeNetwork::initialize, server -> {}, BridgeNetwork::tick, BridgeNetwork::detach),
			new ServerFeature("world", () -> {}, WorldBridge::attach, WorldBridge::tick, server -> WorldBridge.detach()),
			new ServerFeature("exchange", () -> ServerPlayerEvents.COPY_FROM.register((oldPlayer,newPlayer,alive) -> ResourceExchange.inheritPendingReceipts(oldPlayer,newPlayer)),
				server -> {}, server -> {if(BridgeNetwork.exchangeEnabled())ResourceExchange.tick(server);}, server -> {}),
			// Legacy entity/dimension ticks remain inside WorldBridge until their owners migrate them.
			new ServerFeature("entities", () -> {
				PalEntityBridge.bindPlayerUidResolver(uuid -> { var identity=BridgeSessions.identity(uuid); return identity==null?null:identity.palUid(); });
				PalEntityBridge.bindPlayerSessionResolver(player -> { var handle=BridgeSessions.handle(player); if(handle==null)return null;var context=handle.json();context.addProperty("mc_epoch",BridgeSessions.mcEpoch());return context; });
				ServerEntityEvents.ENTITY_LOAD.register(MobWar::onEntityLoad);
			}, PalEntityBridge::attach, server -> {}, MobWar::detach),
			new ServerFeature("dimensions", () -> {}, server -> {}, server -> {}, Nether::detach),
			new ServerFeature("travel", () -> BridgeTravelGate.bindRebaseTransition(WorldCompatibility::beginRebaseTransition),
				BridgeTravelGate::attach, BridgeTravelGate::tick, BridgeTravelGate::detach)
		);
		features.forEach(feature -> { feature.initialize().run(); LOG.info("feature registered: {}", feature.name()); });
		ServerLifecycleEvents.SERVER_STARTED.register(server -> features.forEach(feature -> feature.start().accept(server)));
		ServerTickEvents.END_SERVER_TICK.register(server -> features.forEach(feature -> feature.tick().accept(server)));
		ServerLifecycleEvents.SERVER_STOPPING.register(server -> {
			for (int i = features.size() - 1; i >= 0; i--) features.get(i).stop().accept(server);
		});
		LOG.info("passthrough loaded");
	}
}
