package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.client.mixin.KeyMappingAccessor;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.player.Inventory;
import org.lwjgl.sdl.SDLVideo;

/** Host input, applied on the client thread: the host window has the focus, so Minecraft never sees these itself. */
public final class ClientInput {
    public static boolean buildMode;
    private static double pointerX,pointerY;
    private static int pointerButton=-1;
    private static int pointerMods;
    private static net.minecraft.client.gui.screens.Screen pressedScreen, inputScreen;
    private static final java.util.Set<KeyMapping> held = new java.util.HashSet<>();

    static void releaseIfDetached() {
        Minecraft mc=Minecraft.getInstance();
        if(HostState.live()==null||mc.level==null){sessionDisconnected();return;}
        if(mc.gui.screen()!=inputScreen){releaseAllHostKeys();inputScreen=mc.gui.screen();}
    }

    public static void releaseAllHostKeys() {
        Minecraft mc=Minecraft.getInstance();
        for(KeyMapping key:held){key.setDown(false);((KeyMappingAccessor)key).passthrough$setClickCount(0);}
        held.clear();
        mc.options.keyAttack.setDown(false);mc.options.keyUse.setDown(false);
        ((KeyMappingAccessor)mc.options.keyAttack).passthrough$setClickCount(0);
        ((KeyMappingAccessor)mc.options.keyUse).passthrough$setClickCount(0);
        if(mc.gameMode!=null&&mc.gameMode.isDestroying())mc.gameMode.stopDestroyBlock();
        if(pointerButton>=0&&pressedScreen!=null){
            pressedScreen.mouseReleased(new net.minecraft.client.input.MouseButtonEvent(pointerX,pointerY,new net.minecraft.client.input.MouseButtonInfo(pointerButton,pointerMods)));
        }
        pointerButton=-1;pressedScreen=null;
    }

    public static void modeChanged(boolean enabled) {
        releaseAllHostKeys();
        buildMode=enabled;
        Minecraft mc=Minecraft.getInstance();
        if(!enabled&&mc.gui.screen()!=null)mc.gui.setScreen(null);
        inputScreen=mc.gui.screen();
    }

    public static void sessionDisconnected() {
        releaseAllHostKeys();
        buildMode=false;
        inputScreen=null;
    }

	private ClientInput() {
	}

	static void handle(final Minecraft minecraft, final JsonObject m) {
		if(!ClientBridge.worldInteractionsReady()){
			String type=m.get("t").getAsString();
			boolean close=type.equals("key")&&m.has("k")&&m.get("k").getAsString().equals("escape");
			boolean presentation=type.equals("hud")||type.equals("view")||type.equals("mode");
			if(!close&&!presentation){releaseAllHostKeys();return;}
		}
		if(minecraft.gui.screen()!=inputScreen){releaseAllHostKeys();inputScreen=minecraft.gui.screen();}
		LocalPlayer player = minecraft.player;
		switch (m.get("t").getAsString()) {
			case "mode" -> {
                modeChanged(m.get("on").getAsBoolean());
            }
            case "inventory_toggle" -> {
                if(player!=null) {
                    releaseAllHostKeys();
                    if(minecraft.gui.screen()!=null) minecraft.gui.screen().onClose();
                    else minecraft.gui.setScreen(new net.minecraft.client.gui.screens.inventory.InventoryScreen(player));
                    inputScreen=minecraft.gui.screen();
                }
            }
            case "pointer" -> {
                if(minecraft.gui.screen()==null) return;
                double x=m.get("x").getAsDouble()*minecraft.getWindow().getGuiScaledWidth();
                double y=m.get("y").getAsDouble()*minecraft.getWindow().getGuiScaledHeight();
                minecraft.mouseHandler.onMove(minecraft.getWindow().handle(),m.get("x").getAsDouble()*minecraft.getWindow().getWidth(),m.get("y").getAsDouble()*minecraft.getWindow().getHeight(),0,0);
                var screen=minecraft.gui.screen();
                if(screen instanceof net.minecraft.client.gui.screens.inventory.InventoryScreen && m.has("button") && m.get("button").getAsInt()==1 && m.get("down").getAsBoolean() && Math.abs(x-minecraft.getWindow().getGuiScaledWidth()/2.0)<64 && y>=minecraft.getWindow().getGuiScaledHeight()-34 && y<minecraft.getWindow().getGuiScaledHeight()-18){minecraft.gui.setScreen(new ExchangeScreen(screen));pointerButton=-1;return;}
                screen.mouseMoved(x,y);
                int mods=m.has("mods")?m.get("mods").getAsInt():0;
                if(m.has("button")) {
                    int b=m.get("button").getAsInt();
                    var event=new net.minecraft.client.input.MouseButtonEvent(x,y,new net.minecraft.client.input.MouseButtonInfo(b,mods));
                    if(m.get("down").getAsBoolean()){pointerButton=b;pointerMods=mods;pressedScreen=screen;screen.mouseClicked(event,false);}
                    else {if(pressedScreen!=null)pressedScreen.mouseReleased(event);else screen.mouseReleased(event);pointerButton=-1;pressedScreen=null;}
                } else if(pointerButton>=0) {
                    screen.mouseDragged(new net.minecraft.client.input.MouseButtonEvent(x,y,new net.minecraft.client.input.MouseButtonInfo(pointerButton,mods)),x-pointerX,y-pointerY);
                }
                pointerX=x;pointerY=y;
            }
            case "wheel" -> {
                if(minecraft.gui.screen()!=null) minecraft.gui.screen().mouseScrolled(pointerX,pointerY,0,m.get("d").getAsDouble());
            }
            case "gui_key" -> {
                if(minecraft.gui.screen()!=null) minecraft.gui.screen().keyPressed(new net.minecraft.client.input.KeyEvent(m.get("scan").getAsInt(),m.get("key").getAsInt(),m.has("mods")?m.get("mods").getAsInt():0));
            }
            case "text" -> {
                if(minecraft.gui.screen()!=null) for(int c:m.get("text").getAsString().codePoints().toArray()) minecraft.gui.screen().charTyped(new net.minecraft.client.input.CharacterEvent(c));
            }
            case "key" -> {
				String k = m.get("k").getAsString();
				boolean down = !m.has("down") || m.get("down").getAsBoolean();
                if(down&&minecraft.gui.screen()!=null&&(k.equals("attack")||k.equals("use")))return;
				if (k.equals("escape")) {
					if (down && minecraft.gui.screen() != null) {
						minecraft.gui.screen().onClose();
					}

					return;
				}

				KeyMapping key = switch (k) {
					case "use" -> minecraft.options.keyUse;
					case "attack" -> minecraft.options.keyAttack;
					case "pick" -> minecraft.options.keyPickItem;
					case "inventory" -> minecraft.options.keyInventory;
					case "drop" -> minecraft.options.keyDrop;
					case "swap" -> minecraft.options.keySwapOffhand;
					default -> null;
				};
				if (k.equals("attack") && down && player != null
					&& BuiltInRegistries.ITEM.getKey(player.getMainHandItem().getItem()).getPath().endsWith("_sword")) {
					// a sword swing: the host hits what's in front of Steve in its own world
					Passthrough.events.accept("{\"t\":\"melee\"}");
				}

				if (key != null) {
					if (down && !key.isDown()) {
						KeyMappingAccessor access = (KeyMappingAccessor)key;
						access.passthrough$setClickCount(access.passthrough$getClickCount() + 1);
					}

					key.setDown(down);
                    if (down) held.add(key); else held.remove(key);
				}
			}
			case "slot" -> {
				if (player != null) {
					player.getInventory().setSelectedSlot(Math.clamp(m.get("n").getAsInt(), 0, Inventory.getSelectionSize() - 1));
				}
			}
			case "scroll" -> {
				if (player != null) {
					Inventory inventory = player.getInventory();
					int size = Inventory.getSelectionSize();
					inventory.setSelectedSlot(Math.floorMod(inventory.getSelectedSlot() - m.get("d").getAsInt(), size));
				}
			}
			case "hud" -> {
				if (minecraft.gui.hud.isHidden() != m.get("hidden").getAsBoolean()) {
					minecraft.gui.hud.toggle();
				}
			}
			case "view" -> {
				// match the host's picture exactly: un-minimize/un-maximize first (resizing a maximized window is ignored)
				int w = m.get("w").getAsInt(), h = m.get("h").getAsInt();
				long handle = minecraft.getWindow().handle();
				SDLVideo.SDL_RestoreWindow(handle);
				minecraft.getWindow().setWindowed(w, h);
				SDLVideo.SDL_SetWindowSize(handle, w, h);
				SDLVideo.SDL_SyncWindow(handle);
			}
			default -> {
			}
		}
	}
}
