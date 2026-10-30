--[[
  PBZ Perfect Heal Accessory
  Restores 10% of the player's maximum HP whenever the player lands a
  perfect deflect or a perfect dodge.

  How it works:
    - Perfect deflect (parry cue): hooks LGAAction_CheckParry result
      notification (EParryResult.Perfect = 3)
    - Perfect dodge: hooks every blueprint function named "Do Perfect Dodge"
    - Fallback: hooks DeflectComponent:GetSelfResultData and checks the
      result tag (e.g. "Deflect.Result.Perfect")
    - Healing: writes the player's AttributeSetBase Health value directly

  Requires: UE4SS for Phantom Blade Zero
  Install: copy this folder into platform/steam/ue4ss/Mods/
]]

local MOD = "PBZPerfectHeal"
local cfg = nil

local function log(fmt, ...)
    if cfg and cfg.debug == false then return end
    local ok, s = pcall(string.format, fmt, ...)
    print("[" .. MOD .. "] " .. (ok and s or tostring(fmt)) .. "\n")
end

-- Load config.lua from the mod's own Scripts folder. UE4SS adds the mod
-- Scripts directory to package.path, so a plain require works here.
local function loadConfig()
    package.loaded["config"] = nil
    local ok, res = pcall(require, "config")
    if ok and type(res) == "table" then
        cfg = res
        return true
    end
    log("config.lua load failed: %s", tostring(res))
    return false
end

local lastHeal = -100
local player = nil
local hooksDone = false
local namedScanTries = 0
local seenTags = {}

local function valid(o)
    if o == nil or type(o) ~= "userdata" or o.IsValid == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

local function getPlayer()
    if valid(player) then return player end
    player = nil
    local ok, pc = pcall(function() return FindFirstOf("PlayerController") end)
    if ok and valid(pc) then
        local okLocal, isLocal = pcall(function() return pc:IsLocalPlayerController() end)
        if not okLocal or isLocal then
            local okPawn, pawn = pcall(function() return pc.Pawn end)
            if okPawn and valid(pawn) then player = pawn end
        end
    end
    return player
end

local function getAttributes()
    local p = getPlayer()
    if not valid(p) then return nil end
    local ok, attrs = pcall(function() return p:GetPropertyValue("AttributeSetBase") end)
    if ok and valid(attrs) then return attrs end
    return nil
end

-- Optional carrier: only active while the player owns the configured accessory.
local function carrierOk()
    if not cfg or not cfg.require_carrier then return true end
    local id = cfg.carrier_item_id
    if id == nil or id == "" then return true end
    local p = getPlayer()
    if not valid(p) then return false end
    local okLib, lib = pcall(function() return StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary") end)
    if not okLib or not valid(lib) then return false end
    local okBp, backpack = pcall(function()
        return lib:GetWorldSubsystem(p, StaticFindObject("/Script/ProjectPBZ.PBZBackPackSubsystem"))
    end)
    if not okBp or not valid(backpack) then return false end
    local okInfos, infos = pcall(function() return backpack:GetAccessoryInfos() end)
    if not okInfos or infos == nil then return false end

    local found = false
    pcall(function()
        infos:ForEach(function(key)
            local name = nil
            pcall(function() name = tostring(key:get()) end)
            if name == id then found = true end
            return false
        end)
    end)
    return found
end

local function heal(reason)
    if not cfg or not cfg.enabled then return end
    if not carrierOk() then return end

    local now = os.clock()
    local cooldown = tonumber(cfg.cooldown_seconds) or 0.3
    if now - lastHeal < cooldown then return end

    local attrs = getAttributes()
    if not valid(attrs) then return end

    local cur, max
    pcall(function()
        cur = attrs.Health.CurrentValue
        max = attrs.Health_Max.CurrentValue
    end)
    if type(cur) ~= "number" or type(max) ~= "number" or cur <= 0 or max <= 0 then return end

    local percent = tonumber(cfg.heal_percent) or 10
    local amount = max * percent / 100
    local newValue = math.min(cur + amount, max)
    if newValue <= cur + 0.5 then return end

    local ok = pcall(function()
        attrs.Health.CurrentValue = newValue
        -- Writing CurrentValue alone may not refresh the HUD bar; mirror it
        -- into BaseValue so the UI follows.
        attrs.Health.BaseValue = newValue
    end)
    if ok then
        lastHeal = now
        log("heal %.1f -> %.1f (+%.1f, %.1f%%, %s)", cur, newValue, newValue - cur, percent, reason)
    else
        log("heal write failed (%s)", reason)
    end
end

-- Render an FGameplayTag param as readable text.
local function tagText(tag)
    local v = tag
    pcall(function() v = tag:get() end)
    local text = tostring(v)
    -- FGameplayTag.TagName is an FName; ToString() gives the readable name.
    local name = nil
    pcall(function() name = v.TagName end)
    if name ~= nil then
        local readable = nil
        pcall(function() readable = name:ToString() end)
        text = text .. " " .. tostring(readable ~= nil and readable or name)
    end
    pcall(function()
        local n2 = tag.TagName
        local r2 = nil
        pcall(function() r2 = n2:ToString() end)
        text = text .. " " .. tostring(r2 ~= nil and r2 or n2)
    end)
    return text
end

local function checkResultTag(tag)
    if tag == nil then return end
    local text = tagText(tag)
    if not seenTags[text] and #seenTags < 30 then
        seenTags[text] = true
        log("result tag: %s", text)
    end
    local lower = string.lower(text)
    local hasPerfect = string.find(lower, "perfect", 1, true) ~= nil
    local hasDeflect = string.find(lower, "deflect", 1, true) ~= nil
    local hasDodge = string.find(lower, "dodge", 1, true) ~= nil
    -- The game reports e.g. "Deflect.Result.Perfect"; the dodge side may be
    -- "Dodge.Result.Perfect".
    if hasPerfect and hasDeflect then
        heal("perfect deflect (tag)")
    end
    if hasPerfect and hasDodge then
        heal("perfect dodge (tag)")
    end
end

-- 1) Timed parry (parry cue): EParryResult.Perfect = 3
local function installParryHooks()
    local ok = pcall(function()
        RegisterHook("/Script/ProjectPBZ.LGAAction_CheckParry:NotifyParrayResultDetermine",
            function(self, attacker, defender, result, impactTime)
                local okR, r = pcall(function() return result:get() end)
                if okR and r == 3 then
                    local d = nil
                    pcall(function() d = defender:get() end)
                    local p = getPlayer()
                    if valid(d) and valid(p) and d:GetAddress() == p:GetAddress() then
                        heal("perfect parry")
                    end
                end
            end)
    end)
    if ok then log("hooked NotifyParrayResultDetermine") end

    pcall(function()
        RegisterHook("/Script/ProjectPBZ.LGAAction_CheckParry:NotifyParrayImpact",
            function(self, attacker, defender, result)
                local okR, r = pcall(function() return result:get() end)
                if okR and r == 3 then heal("perfect parry impact") end
            end)
    end)
end

-- 2) Perfect dodge: every blueprint function named "Do Perfect Dodge"
local function installDodgeHooks()
    local installed = 0
    ForEachUObject(function(obj)
        local okCls, cls = pcall(function() return obj:GetClass():GetFName():ToString() end)
        if okCls and cls == "Function" then
            local okName, full = pcall(function() return obj:GetFullName() end)
            if okName and full and string.find(full, ":Do Perfect Dodge", 1, true) then
                local okHook = pcall(function()
                    RegisterHook(full, function()
                        log("Do Perfect Dodge fired: %s", full)
                        heal("perfect dodge")
                    end)
                end)
                if okHook then
                    installed = installed + 1
                    log("hooked %s", full)
                end
            end
        end
    end)
    return installed
end

-- 3) Fallback: DeflectComponent result query (local player component only)
local function installResultHook()
    pcall(function()
        RegisterHook("/Script/PBZDeflectSystem.DeflectComponent:GetSelfResultData",
            function(self, handle, resultTag, outData)
                local comp = nil
                pcall(function() comp = self:get() end)
                local p = getPlayer()
                if valid(comp) and valid(p) then
                    local okOwner, owner = pcall(function() return comp:GetOwner() end)
                    if not okOwner or not valid(owner) or owner:GetAddress() ~= p:GetAddress() then
                        return
                    end
                end
                checkResultTag(resultTag)
            end)
    end)
end

local function installHooks()
    if hooksDone then return end
    if not valid(getPlayer()) then return end
    hooksDone = true
    installParryHooks()
    installResultHook()
    log("base hooks installed")
end

local function scanDodgeHooks()
    if namedScanTries > 20 then return true end
    namedScanTries = namedScanTries + 1
    local n = installDodgeHooks()
    if n > 0 then
        log("dodge hooks installed: %d", n)
        return true
    end
    return false
end

local dodgeHooksReady = false

local function tick()
    if not cfg then loadConfig() end
    if not valid(getPlayer()) then
        ExecuteInGameThreadWithDelay(1000, tick)
        return
    end
    installHooks()
    if not dodgeHooksReady then
        dodgeHooksReady = scanDodgeHooks()
    end
    ExecuteInGameThreadWithDelay(1500, tick)
end

-- Hot-reload the settings file every 3 seconds.
LoopAsync(3000, function()
    local before = cfg and cfg.heal_percent
    loadConfig()
    if cfg and cfg.heal_percent ~= before then
        log("config reloaded: heal=%s%% cooldown=%ss", tostring(cfg.heal_percent), tostring(cfg.cooldown_seconds))
    end
    return false
end)

-- Startup
if loadConfig() then
    log("config loaded: heal=%s%% cooldown=%ss carrier=%s",
        tostring(cfg.heal_percent), tostring(cfg.cooldown_seconds), tostring(cfg.carrier_item_id))
else
    log("config.lua not found; using defaults")
    cfg = { enabled = true, heal_percent = 10, cooldown_seconds = 0.3, require_carrier = false, carrier_item_id = "", debug = true }
end
ExecuteInGameThreadWithDelay(500, tick)

RegisterConsoleCommandHandler("perfectheal", function(_, params)
    local a = params and params[1] and tostring(params[1]):lower() or "status"
    if a == "on" then cfg.enabled = true
    elseif a == "off" then cfg.enabled = false
    elseif a == "test" then heal("manual test") end
    log("enabled=%s percent=%s cooldown=%s carrier=%s",
        tostring(cfg.enabled), tostring(cfg.heal_percent), tostring(cfg.cooldown_seconds), tostring(cfg.carrier_item_id))
    return true
end)

log("loaded")
