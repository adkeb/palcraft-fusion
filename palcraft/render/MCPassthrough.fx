// Palworld owns the world. This pass samples only MC's premultiplied HUD/hand.
// There are deliberately no MCWORLD/MCDEPTH textures or reprojection passes.
#include "ReShade.fxh"

texture MCOverlayTex : MCOVERLAY;
sampler sOverlay {
    Texture = MCOverlayTex;
    MinFilter = LINEAR; MagFilter = LINEAR;
    AddressU = CLAMP; AddressV = CLAMP;
};
uniform bool McActive = false;
uniform bool NativeBlocks = true; // Also forced by the add-on after every preset reload.
uniform bool RowsBottomUp = true;

float4 PS_HUD(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    const float4 host = tex2D(ReShade::BackBuffer, uv);
    if (!McActive || !NativeBlocks) return host;
    const float4 hud = tex2D(sOverlay, float2(uv.x, RowsBottomUp ? 1.0 - uv.y : uv.y));
    return float4(hud.rgb + host.rgb * (1.0 - saturate(hud.a)), host.a);
}
technique MCPassthrough < ui_tooltip = "Minecraft HUD and hand; native Palworld world."; > {
    pass HUD {
        VertexShader = PostProcessVS;
        PixelShader = PS_HUD;
    }
}
