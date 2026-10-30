-- PBZ Perfect Heal Accessory - settings
-- Edit and save; the mod re-reads this file every 3 seconds.
-- No game restart is needed while the game is running.
return {
    -- Master switch.
    enabled = true,

    -- Heal amount, in percent of the player's maximum HP (10 = 10%).
    heal_percent = 10,

    -- Minimum interval between heals, in seconds. Prevents several hooks
    -- from healing for the same event.
    cooldown_seconds = 0.3,

    -- Only heal when the perfect deflect/dodge was against a boss.
    -- Boss = Difficulty Tag containing "Boss" (MiniBoss, NormalBoss,
    -- GreatBoss, UltimateBoss). If the attacker cannot be identified,
    -- the heal is allowed and a log line says so.
    boss_only = false,

    -- Optional: only heal while the player owns a specific accessory.
    -- Set require_carrier = true and put the item ID in carrier_item_id.
    require_carrier = false,
    carrier_item_id = "",

    -- Print detailed lines to ue4ss/UE4SS.log.
    debug = true,
}
