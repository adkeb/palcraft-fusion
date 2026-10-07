# Legacy dropped-item texture root

The native legacy drop path still used `bridge/textures/<id>.png`, while the actual managed package stores namespaced item/block textures under the model asset root. The absent legacy torch and fallback stone files caused a failed texture import and stopped the world factory; no missing asset was synthesized or silently accepted.

The resolver retains an existing legacy file when present, then uses the original Models status asset root, the item's namespaced item/block PNG, the frozen geometry provider's stair/slab texture mapping, and the existing managed stone fallback. Invalid resources or missing final assets fail. Original material parent reacquisition, resource-pair validity, UV/lighting/filter parameters, scope checks and dropped-item behavior remain unchanged. The server-only branch still does not create materials.

Two limited source cases passed; actual managed torch/stone PNG metadata was read without altering images. Candidate26 packages only these two existing Lua source targets, with all33 cumulative targets and requirements retained. Actual normal-maintenance upgrade and survival retest are in progress; full ACK/performance and no-crash mining are not claimed here. Commercial textures and private asset/state captures are excluded.
