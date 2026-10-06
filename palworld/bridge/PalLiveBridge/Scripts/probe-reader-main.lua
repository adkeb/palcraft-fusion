-- One-shot, READ-ONLY BridgeLab scan. Candidate before its first UE4SS runtime test.
-- Intended to be installed by the root agent as main.lua ONLY in the isolated lab.
-- Scripts/readers.lua, targets.lua and json.lua must be present beside this file.
-- Does not call RPC, Save, console exec, network, mutations or production server code.
local OUTPUT = "D:/PalworldServer-LAN/BridgeLab/rpc/audit-live.json"
local START_DELAY_MS = 20000
local source = debug.getinfo(1, "S").source
assert(source:sub(1,1)=="@", "script path unavailable")
local directory = source:sub(2):match("^(.*[/\\])")
assert(directory, "script directory unavailable")
local Readers = dofile(directory .. "readers.lua")
local Targets = dofile(directory .. "targets.lua")
local Json = dofile(directory .. "json.lua")
assert(type(Json)=="table" and type(Json.encode)=="function", "json.lua must export encode")
local ran = false
local function log(message) print("[PalLiveBridge reader probe] "..tostring(message).."\n") end
local function run()
    if ran then return end
    ran = true
    local ok, data = pcall(function()
        return Readers.snapshot(Targets, {include_items=true, lookup="manager"})
    end)
    if not ok then data = {ok=false, error=tostring(data), candidate_unvalidated=true} end
    data.probe = "ordinary_chests_and_bases_read_only"
    data.target_count = #Targets.chests
    data.server_kind = "BridgeLab isolated copied world"
    local wrote, err = pcall(function()
        if data.storage then
            Json.array(data.storage.chests)
            Json.array(data.storage.errors)
            for _, chest in ipairs(data.storage.chests) do Json.array(chest.slots) end
        end
        if data.bases then Json.array(data.bases.bases); Json.array(data.bases.errors) end
        local encoded = Json.encode(data, {max_bytes=16777216})
        assert(type(encoded)=="string", "JSON encoder did not return a string")
        local temp = OUTPUT .. ".tmp"
        local f, open_error = io.open(temp, "wb")
        assert(f, open_error)
        local success, write_error = f:write(encoded)
        local closed, close_error = f:close()
        assert(success, write_error)
        assert(closed, close_error)
        os.remove(OUTPUT)
        local moved, move_error = os.rename(temp, OUTPUT)
        assert(moved, move_error)
    end)
    if wrote then
        local chest_ok = data.storage and data.storage.ok
        local base_ok = data.bases and data.bases.ok
        log("audit-live.json written; storage_ok="..tostring(chest_ok).." bases_ok="..tostring(base_ok))
    else log("audit output failed: "..tostring(err)) end
end
log("One read-only scan queued in "..START_DELAY_MS.." ms.")
ExecuteWithDelay(START_DELAY_MS, function() ExecuteInGameThread(run) end)
