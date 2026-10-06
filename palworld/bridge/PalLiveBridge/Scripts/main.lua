-- PalLiveBridge: read-only bootstrap for the isolated BridgeLab server.
-- Target loader: Okaetsu/RE-UE4SS release 2281fa31.
-- No save editing, gameplay mutations, networking, UI, or key bindings.
-- The object dump writes diagnostic files in UE4SS's default dump location.
-- Lua pcall handles Lua errors; it cannot contain a native access violation.

local GENERATE_SDK = false -- Start with the smaller object dump only.
local state = "starting"
local dumpStarted = false
local requestPending = false
local readinessChecks = 0
local heartbeats = 0

local function log(message)
    print("[PalLiveBridge] " .. tostring(message) .. "\n")
end

local function dumpOnce()
    if dumpStarted then return end
    dumpStarted = true
    state = "dumping"
    log("Read-only object dump requested; no assets will be force-loaded by this script.")
    local ok, err = pcall(function()
        assert(type(DumpAllObjects) == "function", "DumpAllObjects is unavailable")
        DumpAllObjects()
        if GENERATE_SDK then
            assert(type(GenerateSDK) == "function", "GenerateSDK is unavailable")
            log("GenerateSDK requested.")
            GenerateSDK()
        end
    end)
    if ok then
        state = "dump_call_returned"
        log("Dump calls returned; verify UE4SS_ObjectDump.txt before treating the export as complete.")
    else
        state = "dump_failed"
        log("Dump failed: " .. tostring(err))
    end
end

assert(type(LoopAsync) == "function", "PalLiveBridge requires LoopAsync")
assert(type(ExecuteWithDelay) == "function", "PalLiveBridge requires ExecuteWithDelay")
assert(type(ExecuteInGameThread) == "function", "PalLiveBridge requires ExecuteInGameThread")
assert(type(FindFirstOf) == "function", "PalLiveBridge requires FindFirstOf")

log("Read-only bootstrap loaded. Waiting 15 seconds before readiness checks.")
LoopAsync(30000, function()
    heartbeats = heartbeats + 1
    log("heartbeat=" .. heartbeats .. " state=" .. state .. " checks=" .. readinessChecks)
    return false
end)

ExecuteWithDelay(15000, function()
    state = "waiting_for_item_container_manager"
    LoopAsync(2000, function()
        if dumpStarted or state == "readiness_failed" or state == "settling" then return true end
        if requestPending then return false end
        readinessChecks = readinessChecks + 1
        if readinessChecks > 90 then
            state = "readiness_failed"
            log("No ready item-container manager after 90 checks; automatic dump skipped.")
            return true
        end
        requestPending = true
        ExecuteInGameThread(function()
            local ok, ready = pcall(function()
                local manager = FindFirstOf("PalItemContainerManager")
                return manager ~= nil and manager:IsValid()
            end)
            requestPending = false
            if not ok then
                state = "readiness_failed"
                log("Readiness check failed: " .. tostring(ready))
            elseif ready then
                state = "settling"
                log("Item-container manager found; allowing 5 more seconds before dumping.")
                ExecuteWithDelay(5000, function()
                    ExecuteInGameThread(dumpOnce)
                end)
            end
        end)
        return false
    end)
end)
