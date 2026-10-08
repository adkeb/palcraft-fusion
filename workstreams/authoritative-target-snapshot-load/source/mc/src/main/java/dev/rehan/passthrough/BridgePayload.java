package dev.rehan.passthrough;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
/** Fabric transports this over the player's existing Minecraft connection. */
public record BridgePayload(String json) implements CustomPacketPayload {
 public static final int PROTOCOL_VERSION=2;
 public static final int MAX_JSON_CHARACTERS=1048576;
 public static final int MAX_PACKET_BYTES=4194304;
 public BridgePayload {java.util.Objects.requireNonNull(json,"json");if(json.length()>MAX_JSON_CHARACTERS)throw new IllegalArgumentException("Bridge message is too large");}
 public static final Type<BridgePayload> TYPE=new Type<>(net.minecraft.resources.Identifier.parse("passthrough:bridge"));
 public static final StreamCodec<FriendlyByteBuf,BridgePayload> CODEC=StreamCodec.of((b,v)->b.writeUtf(v.json,MAX_JSON_CHARACTERS),b->new BridgePayload(b.readUtf(MAX_JSON_CHARACTERS)));
 @Override public Type<BridgePayload> type(){return TYPE;}
}
