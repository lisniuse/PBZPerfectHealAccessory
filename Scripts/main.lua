--[[
  PBZ Perfect Heal Accessory
  Restores a percentage of the player's maximum HP whenever the player lands a
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
local lastAttacker, lastAttackerAt = nil, -100
local cheatMgr, F_SetHealth
local F_HealthPostFunc, F_HealthPost

local function valid(o)
    if o == nil or type(o) ~= "userdata" or o.IsValid == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end

local function find_child(cls, target)
    if not valid(cls) then return nil end
    local child
    pcall(function() child = cls.Children end)
    local guard = 0
    while valid(child) and guard < 5000 do
        guard = guard + 1
        local n, t
        pcall(function() n = child:GetFName():ToString(); t = child:type() end)
        if n == target and t == "UFunction" then return child end
        local nxt
        pcall(function() nxt = child.Next end)
        child = nxt
    end
    return nil
end

local function find_function_deep(obj, target, depth_max)
    local c, d = obj, 0
    while valid(c) and d < (depth_max or 10) do
        local cls
        pcall(function() cls = c:GetClass() end)
        local f = find_child(cls, target)
        if f then return f end
        local sup
        pcall(function() sup = c.SuperStruct end)
        c = sup; d = d + 1
    end
    return nil
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

-- Boss check: reads the character's Actor Config asset and its Difficulty Tag
-- (CharacterType.Difficulty.*Boss*). Returns true/false, or nil if unknown.
local function isBossActor(actor)
    if not valid(actor) then return nil end
    local okc, asset = pcall(function() return actor:GetPropertyValue("Actor Config") end)
    if okc and valid(asset) then
        local okt, tag = pcall(function() return asset["Difficulty Tag"].TagName:ToString() end)
        if okt and type(tag) == "string" and tag ~= "None" and tag ~= "" then
            return string.find(string.lower(tag), "boss", 1, true) ~= nil
        end
    end
    -- Fallback: boss blueprints are usually named ...Boss...
    local okk, cls = pcall(function() return actor:GetClass():GetFullName() end)
    if okk and type(cls) == "string" then
        return string.find(string.lower(cls), "boss", 1, true) ~= nil
    end
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

-- Resolve the game's own cheat manager and its GM_SetHealth function. The
-- cheat manager writes health through the game's attribute path, which sticks
-- where a raw struct write may be overwritten by GAS.
local lastResolveSig = nil
local function resolveCheat()
    if valid(cheatMgr) and valid(F_SetHealth) then return end
    local ok, pc = pcall(function() return FindFirstOf("PlayerController") end)
    if ok and valid(pc) then
        local okc, cm = pcall(function() return pc.CheatManager end)
        if okc and valid(cm) then cheatMgr = cm end
    end
    if not valid(cheatMgr) then
        local okf, cm = pcall(function() return FindFirstOf("PBZCheatManager") end)
        if okf and valid(cm) then cheatMgr = cm end
    end
    if valid(cheatMgr) then
        F_SetHealth = find_function_deep(cheatMgr, "GM_SetHealth", 8)
        if not valid(F_SetHealth) then
            ForEachUObject(function(obj)
                if valid(F_SetHealth) then return true end
                local okc, cls = pcall(function() return obj:GetClass():GetFName():ToString() end)
                if okc and cls == "Function" then
                    local okn, full = pcall(function() return obj:GetFullName() end)
                    if okn and full and string.find(full, ":GM_SetHealth", 1, true) then
                        F_SetHealth = obj
                    end
                end
            end)
        end
    end
    -- The player blueprint has Health Post Func(NewValue, OldValue), which is
    -- what refreshes the HUD/material after a health change.
    local p = getPlayer()
    if valid(p) then
        if not valid(F_HealthPostFunc) then
            F_HealthPostFunc = find_function_deep(p, "Health Post Func", 10)
        end
        if not valid(F_HealthPost) then
            F_HealthPost = find_function_deep(p, "Health Post", 10)
        end
    end

    local sig = string.format("pc=%s cm=%s F=%s healthPostFunc=%s healthPost=%s",
        tostring(ok), tostring(valid(cheatMgr)), tostring(valid(F_SetHealth)),
        tostring(valid(F_HealthPostFunc)), tostring(valid(F_HealthPost)))
    if sig ~= lastResolveSig then
        lastResolveSig = sig
        log("cheat resolve: %s", sig)
    end
end

-- Wall-clock stamp with milliseconds, so a heal can be lined up with the event that asked for it.
local function stamp()
    local secs = os.time()
    return os.date("%H:%M:%S", secs) .. string.format(".%03d", math.floor((os.clock() % 1) * 1000))
end

local function heal(reason, attacker)
    if not cfg or not cfg.enabled then return end
    local t0 = os.clock()
    if cfg.debug then log("%s heal called (%s)", stamp(), reason) end
    if not carrierOk() then return end

    if cfg.boss_only then
        local boss = isBossActor(attacker)
        if boss == false then
            log("heal skipped (%s): attacker is not a boss", reason)
            return
        elseif boss == nil then
            log("heal (%s): attacker unknown, boss_only allowed", reason)
        end
    end

    local now = os.clock()
    local cooldown = tonumber(cfg.cooldown_seconds) or 0.3
    if now - lastHeal < cooldown then
        log("%s heal skipped (%s): %.2fs since last heal", stamp(), reason, now - lastHeal)
        return
    end

    local attrs = getAttributes()
    if not valid(attrs) then return end

    local cur, max
    pcall(function()
        cur = attrs.Health.CurrentValue
        max = attrs.Health_Max.CurrentValue
    end)
    if type(cur) ~= "number" or type(max) ~= "number" or cur <= 0 or max <= 0 then return end
    local gh0 = nil
    pcall(function() gh0 = getPlayer():GetHealth() end)

    local percent = tonumber(cfg.heal_percent) or 10
    local amount = max * percent / 100
    local newValue = math.min(cur + amount, max)
    if newValue <= cur + 0.5 then return end

    local usedCheat = false
    resolveCheat()
    if valid(cheatMgr) and valid(F_SetHealth) then
        usedCheat = pcall(function() F_SetHealth(cheatMgr, newValue) end)
    end

    -- Read back and fall back to the direct attribute write if the game's
    -- setter did not take effect (or is unavailable).
    local after = nil
    pcall(function() after = attrs.Health.CurrentValue end)
    local needFallback = (not usedCheat) or (type(after) == "number" and math.abs(after - newValue) > 1.0)
    if needFallback then
        pcall(function() attrs.Health.CurrentValue = newValue end)
        pcall(function() after = attrs.Health.CurrentValue end)
    end
    -- BaseValue is what GAS recomputes CurrentValue from: writing only CurrentValue (what GM_SetHealth does) is
    -- undone by the next attribute update (measured 2026-11-06: 1694.4 read back as 354.9 half a second later).
    pcall(function() attrs.Health.BaseValue = newValue end)
    local base = nil
    pcall(function() base = attrs.Health.BaseValue end)

    if type(after) == "number" and math.abs(after - cur) > 0.5 then
        lastHeal = now
        -- Applying the game's heal GameplayEffect here (to force GAS to broadcast) crashed the game on 2026-11-06:
        -- it is a SetByCaller effect and without a spec its magnitude is garbage. Do not do that.
        -- The bar is event driven: its own OnHeathChanged(NewValue, OldValue) is what the game's attribute binding
        -- calls. Call it ourselves (safe: it is a plain widget function) so the bar moves at once.
        local hudCalls = 0
        pcall(function()
            local widgets = FindAllOf("WB_PlayerHPBar_V1_C")
            if widgets then
                for _, w in pairs(widgets) do
                    if valid(w) then
                        local okw = pcall(function() w:OnHeathChanged(after, cur) end)
                        if okw then hudCalls = hudCalls + 1 end
                    end
                end
            end
        end)
        if hudCalls == 0 then
            pcall(function()
                local widgets = FindAllOf("WB_PlayerHPBar_C")
                if widgets then
                    for _, w in pairs(widgets) do
                        if valid(w) then
                            if pcall(function() w:OnHeathChanged(after, cur) end) then hudCalls = hudCalls + 1 end
                        end
                    end
                end
            end)
        end
        log("%s hud refresh: OnHeathChanged called on %d widget(s)", stamp(), hudCalls)
        if hudCalls == 0 then
            if valid(F_HealthPostFunc) then
                pcall(function() F_HealthPostFunc(getPlayer(), after, cur) end)
            elseif valid(F_HealthPost) then
                pcall(function() F_HealthPost(getPlayer()) end)
            end
        end
        -- What the game itself reports for the player's health (the bar reads this, not our struct write).
        local gh, gmh = nil, nil
        pcall(function() gh = getPlayer():GetHealth(); gmh = getPlayer():GetMaxHealth() end)
        local who = "?"
        pcall(function() who = getPlayer():GetAddress() .. " " .. getPlayer():GetFullName() end)
        log("%s heal %.1f -> %.1f (+%.1f, %.1f%%, %s) readback=%.1f base=%s cheat=%s took=%.0fms gameHealth=%s gameMax=%s pawn=%s",
            stamp(), cur, newValue, newValue - cur, percent, reason, after, tostring(base), tostring(usedCheat),
            (os.clock() - t0) * 1000, tostring(gh0) .. "->" .. tostring(gh), tostring(gmh), tostring(who))
        -- the value can be overwritten by the game's own attribute update a moment later: look again
        ExecuteInGameThreadWithDelay(500, function()
            local a2 = nil
            local attrs2 = getAttributes()
            pcall(function() a2 = attrs2.Health.CurrentValue end)
            log("%s heal check +0.5s: %s (wanted %.1f)", stamp(), tostring(a2), newValue)
        end)
    else
        log("%s heal did not stick (%s): cur=%.1f new=%.1f readback=%s cheat=%s",
            stamp(), reason, cur, newValue, tostring(after), tostring(usedCheat))
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

-- Returns "deflect", "dodge" or nil from a result tag text.
local function resultKind(text)
    if not text then return nil end
    local lower = string.lower(text)
    local hasPerfect = string.find(lower, "perfect", 1, true) ~= nil
    if not hasPerfect then return nil end
    if string.find(lower, "deflect", 1, true) then return "deflect" end
    if string.find(lower, "dodge", 1, true) then return "dodge" end
    return nil
end

-- Derive the attacking actor from a FDeflectReceiveFrame (used for dodge).
local function attackerFromFrameData(frameData)
    local fd = frameData
    pcall(function() fd = frameData:get() end)
    if fd == nil then return nil end
    local action = nil
    pcall(function()
        local w = fd.SourceAction
        action = w
        pcall(function() action = w:get() end)
    end)
    if not valid(action) then return nil end

    local avatar = nil
    pcall(function() avatar = action:GetAvatarActor() end)
    if valid(avatar) then return avatar end

    local cur = action
    for _ = 1, 6 do
        if not valid(cur) then break end
        local okc, asset = pcall(function() return cur:GetPropertyValue("Actor Config") end)
        if okc and valid(asset) then return cur end
        local oko, outer = pcall(function() return cur:GetOuter() end)
        if not oko or not valid(outer) then break end
        cur = outer
    end
    return nil
end

-- 1) Timed parry (parry cue): EParryResult.Perfect = 3
local parryLogs = 0
local function installParryHooks()
    local ok = pcall(function()
        RegisterHook("/Script/ProjectPBZ.LGAAction_CheckParry:NotifyParrayResultDetermine",
            function(self, attacker, defender, result, impactTime)
                local okR, r = pcall(function() return result:get() end)
                if okR and parryLogs < 40 then
                    parryLogs = parryLogs + 1
                    log("%s parry determine: result=%s", stamp(), tostring(r))
                end
                if okR and r == 3 then
                    local d, a = nil, nil
                    pcall(function() d = defender:get() end)
                    pcall(function() a = attacker:get() end)
                    local p = getPlayer()
                    if valid(d) and valid(p) and d:GetAddress() == p:GetAddress() then
                        if valid(a) then lastAttacker = a; lastAttackerAt = os.clock() end
                        log("%s parry event: perfect", stamp())
                        heal("perfect parry", a)
                    end
                end
            end)
    end)
    if ok then log("hooked NotifyParrayResultDetermine") end

    pcall(function()
        RegisterHook("/Script/ProjectPBZ.LGAAction_CheckParry:NotifyParrayImpact",
            function(self, attacker, defender, result)
                local okR, r = pcall(function() return result:get() end)
                if okR then log("%s parry impact: result=%s", stamp(), tostring(r)) end
                if okR and r == 3 then
                    local a = nil
                    pcall(function() a = attacker:get() end)
                    heal("perfect parry impact", a)
                end
            end)
    end)
end

-- 2) Perfect dodge: every blueprint function named "Do Perfect Dodge"
local dodgeNamesLogged = false
local function installDodgeHooks()
    local installed = 0
    local candidates = {}
    ForEachUObject(function(obj)
        local okCls, cls = pcall(function() return obj:GetClass():GetFName():ToString() end)
        if okCls and cls == "Function" then
            local okName, full = pcall(function() return obj:GetFullName() end)
            if okName and full and string.find(string.lower(full), "dodge", 1, true) then
                if #candidates < 80 then candidates[#candidates + 1] = full end
            end
            if okName and full and string.find(full, ":Do Perfect Dodge", 1, true) then
                local okHook = pcall(function()
                    RegisterHook(full, function(self, handle, frameData)
                        local attacker = attackerFromFrameData(frameData)
                        if not valid(attacker) and lastAttacker ~= nil and (os.clock() - lastAttackerAt) < 1.5 then
                            attacker = lastAttacker
                        end
                        log("Do Perfect Dodge fired: %s", full)
                        heal("perfect dodge", attacker)
                    end)
                end)
                if okHook then
                    installed = installed + 1
                    log("hooked %s", full)
                end
            end
        end
    end)
    if not dodgeNamesLogged then
        dodgeNamesLogged = true
        log("objects whose name mentions dodge (%d): %s", #candidates, table.concat(candidates, " | "))
    end
    return installed
end

-- 3) Fallback: DeflectComponent result query (local player component only).
--    Pre: log tags. Post: OutResultData has SourceAvatar, so the boss filter
--    can see the attacker.
local function installResultHook()
    local function isLocalComponent(self)
        local comp = nil
        pcall(function() comp = self:get() end)
        local p = getPlayer()
        if not (valid(comp) and valid(p)) then return true end
        local okOwner, owner = pcall(function() return comp:GetOwner() end)
        if not okOwner or not valid(owner) then return true end
        return owner:GetAddress() == p:GetAddress()
    end

    pcall(function()
        RegisterHook("/Script/PBZDeflectSystem.DeflectComponent:GetSelfResultData",
            function(self, handle, resultTag, outData)
                if not isLocalComponent(self) then return end
                local text = tagText(resultTag)
                if not seenTags[text] and #seenTags < 30 then
                    seenTags[text] = true
                    log("%s result tag: %s", stamp(), text)
                end
            end,
            function(self, handle, resultTag, outData)
                if not isLocalComponent(self) then return end
                local kind = resultKind(tagText(resultTag))
                if not kind then return end

                local src = nil
                pcall(function() src = outData:get().SourceAvatar end)
                if not valid(src) then pcall(function() src = outData.SourceAvatar end) end
                if valid(src) then lastAttacker = src; lastAttackerAt = os.clock() end

                log("%s result event: %s -> %s", stamp(), tostring(kind), text)
                if kind == "deflect" then
                    heal("perfect deflect (tag)", src)
                else
                    heal("perfect dodge (tag)", src)
                end
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
    -- Resolve the cheat manager before the first fight, not inside the first heal: doing it there cost 520 ms
    -- (measured 2026-11-06).
    if not (valid(cheatMgr) and valid(F_SetHealth)) then pcall(resolveCheat) end
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
        log("config reloaded: heal=%s%% cooldown=%ss boss_only=%s",
            tostring(cfg.heal_percent), tostring(cfg.cooldown_seconds), tostring(cfg.boss_only))
    end
    return false
end)

-- Startup
if loadConfig() then
    log("config loaded: heal=%s%% cooldown=%ss boss_only=%s carrier=%s",
        tostring(cfg.heal_percent), tostring(cfg.cooldown_seconds), tostring(cfg.boss_only), tostring(cfg.carrier_item_id))
else
    log("config.lua not found; using defaults")
    cfg = { enabled = true, heal_percent = 10, cooldown_seconds = 0.3, boss_only = false, require_carrier = false, carrier_item_id = "", debug = true }
end
ExecuteInGameThreadWithDelay(500, tick)

-- Diagnostics: report whether the cheat manager path is available, without
-- waiting for a perfect deflect.
ExecuteInGameThreadWithDelay(5000, function()
    resolveCheat()
end)

-- Manual test without the console: F9 heals once (the console key does not open for everyone).
if cfg and cfg.debug then
    pcall(function()
        RegisterKeyBind(Key.F9, function()
            heal("manual test (F9)", nil)
        end)
        log("test key F9 bound (heal once)")
    end)
end

RegisterConsoleCommandHandler("perfectheal", function(_, params)
    local a = params and params[1] and tostring(params[1]):lower() or "status"
    if a == "on" then cfg.enabled = true
    elseif a == "off" then cfg.enabled = false
    elseif a == "test" then heal("manual test", nil) end
    log("enabled=%s percent=%s cooldown=%s boss_only=%s carrier=%s",
        tostring(cfg.enabled), tostring(cfg.heal_percent), tostring(cfg.cooldown_seconds),
        tostring(cfg.boss_only), tostring(cfg.carrier_item_id))
    return true
end)

log("loaded")
