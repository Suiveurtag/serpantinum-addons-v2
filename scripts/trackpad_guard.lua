-- Consume trackpad buttons briefly during text entry, without stopping motion.
-- Keyboard events stay inside Hyprland; no text is stored or sent elsewhere.
return function(devices)
    local typing = false
    local held = {}
    local modifiers = {}
    local timer
    local shortcutModifiers = { [37] = true, [105] = true, [64] = true,
        [108] = true, [133] = true, [134] = true }
    local function textKey(code)
        return (code >= 10 and code <= 22) or (code >= 24 and code <= 36)
            or (code >= 38 and code <= 49) or (code >= 51 and code <= 61)
            or code == 65 or code == 94 or code == 104
            or (code >= 79 and code <= 91)
    end
    timer = hl.timer(function()
        if next(held) == nil then
            typing = false
            timer:set_enabled(false)
        end
    end, { timeout = 600, type = "repeat" })
    timer:set_enabled(false)
    hl.on("input.keyboard.key", function(code, time, state)
        if shortcutModifiers[code] then
            modifiers[code] = state == 1 and true or nil
            if state == 1 then
                typing = false
                held = {}
                timer:set_enabled(false)
            end
            return
        end
        if not textKey(code) then return end
        if state == 0 then
            held[code] = nil
            if typing then timer:set_timeout(600) end
        elseif next(modifiers) == nil then
            held[code] = true
            typing = true
            timer:set_timeout(600)
        end
    end)
    for button = 272, 274 do
        hl.bind("mouse:" .. button, function()
            return { ok = typing }
        end, {
            auto_consuming = true, ignore_mods = true, locked = true,
            dont_inhibit = true, submap_universal = true,
            device = { inclusive = true, list = devices },
            description = "Serpantinum: ignore trackpad clicks while typing",
        })
    end
end
