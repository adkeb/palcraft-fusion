# Material resource lifetime after ordinary torch mining

This two-source fix targets the original legacy dropped-item material producer on both configured role copies. Client source is based on the reviewed candidate22 caeb context hotpath; the server copy retains its existing client=false early return. No model/provider/shader pipeline is replaced.

On a new or expired texture key, the producer reacquires the exact original wood parent and normal assets through LoadAsset immediately before CreateDynamicMaterialInstance and validates the parent. Cached entries now hold the MID/texture pair and validate both before reuse; dead resources follow the original import/create path. Original PalCraft texture names, stone fallback, nearest filter, normal map, roughness0.6, UVs and native material attachment are unchanged. No texture, lighting, geometry, drops or entity capability is disabled.

Stop and abandon clear only this Lua instance's cached resource references after the original cleanup. They do not destroy borrowed assets/materials or claim unsupported engine root pinning. Original engine component/MID reference ownership remains unchanged. Exact21 rich material_profiles already validates cached parent/probe/MID/texture; that pipeline is left unchanged.

Four source fixtures load the actual changed material/drop/cleanup functions with synthetic asset/UObject/native callbacks. Run `lua checks/check_material.lua DELTA_ROOT`. The first fixture run incorrectly expected a parameter absent from the original legacy producer; only that fixture expectation was corrected. All four then passed. No Game, GUI, RPC, Saved body, native compilation or runtime installation occurred.

The reviewed crash unwind and captured reflected parameters identify a stale parent argument surface; the precise FName source label remains unobserved. This fixes the source lifetime gap and awaits one ordinary runtime mining/drop trial. Source tests do not certify actual crash resolution or successful pickup.
