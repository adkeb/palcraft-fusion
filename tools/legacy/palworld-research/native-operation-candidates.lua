-- RESEARCH CANDIDATES ONLY. No automatic hooks, polling, mutation or console entrypoint.
-- Public SDK source: localcc/PalworldModdingKit e6632458b97af0083eb81715775651b08104ef6a.
-- Reconcile every signature with the actual Palworld 1.0.5 UHT/reflection dump first.
-- Invoke only from ExecuteInGameThread and only in a disposable copied test world.
-- pcall cannot catch a native C++ access violation. Never retain UObject/UScriptStruct
-- arguments across queued callbacks. Do not replace item fields, call OnRep manually,
-- or use a CDO as the context of an instance method or server RPC.
local M = {}

local function live(obj)
    return obj ~= nil and obj:IsValid()
       and not obj:GetFullName():find("Default__", 1, true)
end
local function fn(path)
    local f = StaticFindObject(path)
    if f and f:IsValid() then return f end
    return nil
end
local function full(obj)
    if not live(obj) then return nil end
    return obj:GetFullName()
end

-- Read-only discovery. FindAllOf excludes class default objects according to UE4SS.
-- No nested item struct fields are read here: some third-party mod versions report
-- native crashes on slot.ItemId.StaticId. Scalar UFunctions can be tested separately.
function M.probe()
    local result = { classes = {}, functions = {}, mutation_verified = false }
    for _, class in ipairs({"PalItemContainerManager", "PalItemContainer",
        "PalMapObjectManager", "PalBaseCampManager", "PalBaseCampModel",
        "PalPlayerController", "PalNetworkTransmitter", "PalNetworkItemComponent",
        "PalNetworkBaseCampComponent", "PalNetworkMapObjectComponent"}) do
        local list = {}
        for _, obj in ipairs(FindAllOf(class) or {}) do
            local name = full(obj)
            if name then list[#list + 1] = name end
        end
        result.classes[class] = list
    end
    for _, suffix in ipairs({
        "PalItemContainerManager:GetContainer",
        "PalItemContainer:Get", "PalItemContainer:Num",
        "PalItemSlot:GetSlotId", "PalItemSlot:GetItemId", "PalItemSlot:GetStackCount",
        "PalNetworkTransmitter:GetItem", "PalNetworkTransmitter:GetBaseCamp",
        "PalNetworkItemComponent:RequestSwap_ToServer",
        "PalNetworkItemComponent:RequestMove_ToServer",
        "PalNetworkItemComponent:RequestMoveToContainer_ToServer",
        "PalMapObjectItemContainerModule:RequestSortContainer_ServerInternal",
        "PalMapObjectManager:RequestSpawnMapObjectByPlayer_Server",
        "PalBaseCampModel:GetBaseCampName", "PalBaseCampModel:GetBuildingNum",
        "PalNetworkBaseCampComponent:RequestFixedAssignWorkInBaseCamp_ToServer",
        "PalNetworkBaseCampComponent:RequestUnassignWorkInBaseCamp_ToServer",
        "PalNetworkBaseCampComponent:RequestChangeWorkSuitability_ToServer",
        "PalNetworkBaseCampComponent:RequestChangeBaseCampBattle_ToServer"
    }) do
        local f = fn("/Script/Pal." .. suffix)
        result.functions[suffix] = f ~= nil
    end
    result.player_context_available = #result.classes.PalPlayerController > 0
    result.item_component_available = #result.classes.PalNetworkItemComponent > 0
    -- 1.0.5 runtime dump showed a real GLOBAL SERVER transmitter even with no player.
    -- Absence of a PlayerController is not evidence that no valid server item context exists.
    if not result.item_component_available then
        result.item_move_state = "no_live_item_component"
    else
        result.item_move_state = "real_instance_found_owner_and_swap_unverified"
    end
    return result
end

-- Resolves a real player's transmitter; caller must match controller:GetPlayerUId()
-- to the requested human account using a separately validated GUID serializer.
-- Never choose the first player silently. Context is usable only during this callback.
function M.item_context_for_verified_controller(controller)
    if not live(controller) then return nil, "player_context_required" end
    if not controller:IsA("/Script/Pal.PalPlayerController") then
        return nil, "not_pal_player_controller"
    end
    local transmitter = controller.Transmitter
    if not live(transmitter) then return nil, "transmitter_missing" end
    local item = transmitter:GetItem()
    if not live(item) then return nil, "item_component_missing" end
    if not item:IsA("/Script/Pal.PalNetworkItemComponent") then
        return nil, "not_pal_network_item_component"
    end
    return item
end

-- No runnable mutation is exported. This exact native-call candidate belongs in the
-- disposable-world test harness AFTER online-player context, GUID/struct marshalling,
-- source/destination ownership, same-base policy, and read-after verification exist:
--
-- local item = M.item_context_for_verified_controller(verifiedController)
-- local slotA = verifiedSourceContainer:Get(sourceIndex) -- zero-based
-- local slotB = verifiedTargetContainer:Get(targetIndex) -- zero-based
-- local slotIdA = slotA:GetSlotId() -- native returned struct; do not hand-write memory
-- local slotIdB = slotB:GetSlotId()
-- item:RequestSwap_ToServer(uniqueRequestGuid, slotIdA, slotIdB)
--
-- RequestSwap returns void; lack of Lua error is NOT success. Re-read both slots and
-- dynamic IDs, durability, corruption, stack counts; ensure the union is unchanged.
-- First test with two disposable ordinary stacks; then one dynamic item and empty slot.
-- RequestMove_ToServer additionally needs TArray<FPalItemSlotIdAndNum> marshalling and
-- may merge stacks. Prefer whole-slot swap for the no-merge classification plan.
--
-- Build candidate, NOT proven normal material-consuming construction:
-- manager:RequestSpawnMapObjectByPlayer_Server(FName(buildingId), positionStruct,
--                                             rotationStruct, verifiedPlayerUid)
-- Before/after assertions must prove material debit exactly once, owner/guild/base
-- links, completion/work state, collision/limit/technology validation and persistence.
-- No proof -> do not expose as a production build API. Do not call an actor SpawnActor
-- fallback: a visible actor alone is not a persisted, owned base facility.
return M
