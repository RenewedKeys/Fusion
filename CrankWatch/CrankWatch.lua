_addon.name = 'CrankWatch'
_addon.author = 'VelnerXI'
--twitch.tv/VelnerXI -- Live starting 5:30 pm PT most days!
_addon.version = '3.0'
_addon.commands = {'crankwatch', 'cw'}

-- CrankWatch 3.0: packet-driven party WS tracker with a built-in port of
-- Ivaar's SkillChains. Unload the separate SkillChains addon when using
-- this (//lua u skillchains), or you'll get two SC HUDs.
--
-- luau must load before config.load so S{} sets in the defaults
-- (Show.* and ws_blacklist) serialize to / parse from settings.xml.
require('luau')
require('pack')
require('actions')
local texts = require('texts')
local skills = require('skills')
local sc_engine = require('sc_engine')
local party_tracker = require('party_tracker')
local ui_hud = require('ui_hud')

-- luau replaces table.concat with a pairs-order version; keep the raw one.
local tconcat = (_raw and _raw.table and _raw.table.concat) or table.concat

-- Set-valued defaults come from constructors: config.load shares the Set
-- objects with the defaults table, so toggling a per-job display would
-- otherwise also change what factoryreset restores.
local function default_blacklist()
    return S{'Myrkr', 'Dagan', 'Starlight', 'Moonlight'}
end
local fresh_defaults = {Show = sc_engine.default_show, ws_blacklist = default_blacklist}

local defaults = {
    center_x = 1475,
    center_y = 850,
    ws_size = 36,
    dmg_size = 42,
    avg_size = 24,
    flair_size = 32,
    line_gap = 45,
    avg_gap = 99,
    flair_gap = 100,
    font = 'Highwind',
    stroke_width = 4,
    big_stroke_width = 5,
    pending_timeout = 1.25,   -- unused since chat parsing was removed; kept so old settings load cleanly
    flair_duration = 2.5,     -- unused; kept for compatibility
    fade_enabled = true,
    fade_in_duration = 0.30,
    hold_duration = 60.0,
    fade_out_duration = 5,
    pop_enabled = true,
    pop_duration = 0.35,
    pop_bonus_size = 8,
    auto_reset = true,
    flair_fade_duration = 1.5,
    flair_shrink_size = 6,
    flair_float_distance = 32,
    flair_anchor_ratio = 0.72,
    sc_anchor_ratio = 0.48,
    flair_offset_y = -6,
    whiff_shake_duration = 0.45,
    whiff_shake_strength = 6,
    sc_enabled = true,
    sc_window = 4.0,          -- unused; kept for compatibility
    sc_fade_duration = 4,
    sc_float_distance = 28,
    sc_gap = 68,
    sc_size = 34,
    sc_offset_y = 32,
    sc_bar_enabled = true,
    sc_bar_gap = 132,
    sc_bar_size = 18,
    sc_bar_width = 18,
    sc_bar_label_size = 15,
    sc_bar_label_overlap = 20,
    sc_bar_delay = 3.0,       -- fallback opening delay when skills.lua has no per-WS delay
    sc_bar_max_step = 5,
    sc_bar_font = 'Consolas',
    sc_bar_shake_duration = 0.35,
    sc_bar_shake_strength = 5,
    sc_chain_counter_enabled = true,
    sc_chain_counter_size = 18,
    sc_chain_counter_gap = 6,
    mb_enabled = true,
    mb_size = 24,
    mb_duration = 3.0,
    mb_fade_in_duration = 0.15,
    mb_fade_out_duration = 0.35,
    mb_offset_x = 95,           -- MB popup, from the banner centre line
    mb_offset_y = 101,          -- MB popup, below center_y (was relative to the SC bar in 2.0)
    mb_shake_duration = 0.50,
    mb_shake_strength = 5,
    -- Two different actions on one target inside this window reset the
    -- chain. 0 = off (Ivaar's engine already restarts at Step 1 when a
    -- follow-up doesn't chain).
    sc_bar_burst_window = 0,

    -- 3.0 additions
    sc_hud_independent = true,  -- SC HUD shows whenever your target has a resonance
    sc_color = true,            -- Ivaar's coloured property / closer text
    sc_aeonic = false,          -- assume other players have their Aeonic equipped
    sc_detail_enabled = true,   -- //cw scdetail: Step / properties / closer list block
    sc_detail_size = 13,
    sc_detail_font = 'Consolas',
    -- Horizontal offsets set by //cw move (vertical ones reuse the 2.0 gaps).
    banner_offset_x = 0,        -- banner block (WS line, damage, average, flair, SC Bonus), from the HUD centre
    banner_offset_y = 0,
    sc_bar_offset_x = -200,     -- skillchain block's left edge, from the banner centre line
    mb_party = true,            -- also pop MBs cast by party members (with their name)
    mb_max_lines = 4,           -- simultaneous MBs stack up to this many lines
    Show = sc_engine.default_show(),
    aoe_sum = false,
    banner_mode = 'self',       -- 'self' | 'party'
    track_pets = true,
    track_trusts = false,
    track_alliance = true,
    banner_hide_on_kill = false, -- //cw killfade: fade the banner when its WS's target dies
    kill_fade_duration = 1.0,   -- seconds for that fade
    party_panel = false,
    party_panel_fade = false,   -- true: party panel fades with the WS banner
    party_panel_size = 13,
    party_panel_font = 'Consolas',
    party_panel_offset_x = 260,
    party_panel_offset_y = 0,
    party_panel_rows = 8,
    ws_blacklist = default_blacklist(),
}

local settings = config.load(defaults)
if settings.auto_reset == nil then settings.auto_reset = true end

local debug_mode = false

skills.hydrate(res.weapon_skills)

local engine = sc_engine.new({skills = skills, res = res, settings = settings, api = windower.ffxi})
local tracker = party_tracker.new({settings = settings, api = windower.ffxi})
local hud = ui_hud.new({settings = settings, texts = texts})

local function chat(msg)
    windower.add_to_chat(200, '[CrankWatch] ' .. msg)
end

local function save_settings()
    config.save(settings)
end

---------------------------------------------------------------------------
-- Message classification
---------------------------------------------------------------------------

-- Damage on the target: WS damage, WS HP drain, WS resisted-but-damaged,
-- ability / pet / blood pact damage and drain, AoE secondary-target damage.
local DMG_MSGS = S{185, 187, 197, 110, 317, 802, 264}
-- Missed / no effect.
local WHIFF_MSGS = S{188, 189, 158, 323, 324}
-- Known non-damaging outcomes (heals, buffs, MP/TP drain, status). Never
-- recorded, and not reported by //cw debug.
local UTILITY_MSGS = S{100, 102, 103, 186, 194, 224, 225, 226, 238, 318, 31}

local TRACK_CATEGORIES = S{'weaponskill_finish', 'mob_tp_finish', 'avatar_tp_finish'}

local MB_FALLBACK = {252, 265, 379, 650, 747}
local function build_mb_messages()
    local set = S{}
    local ok, messages = pcall(function() return res.action_messages end)
    if ok and type(messages) == 'table' then
        for id, m in pairs(messages) do
            local en = type(m) == 'table' and rawget(m, 'en')
            if type(id) == 'number' and type(en) == 'string'
                    and en:find('Magic Burst', 1, true) and en:find('damage', 1, true) then
                set:add(id)
            end
        end
    end
    if set:empty() then
        for _, id in ipairs(MB_FALLBACK) do set:add(id) end
    end
    return set
end
local MB_DMG_MSGS = build_mb_messages()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function current_target()
    return windower.ffxi.get_mob_by_target('t', 'bt')
end

local function action_name(resource, action_id)
    local r = resource and res[resource]
    local name = r and sc_engine.res_name(r[action_id])
    if not name and resource and skills[resource] and skills[resource][action_id] then
        name = skills[resource][action_id].en
    end
    return name or ('WS #' .. tostring(action_id))
end

local function canonical_ws_name(name)
    local lower = name:lower()
    for _, ws in pairs(res.weapon_skills) do
        local en = type(ws) == 'table' and rawget(ws, 'en')
        if en and en:lower() == lower then return en end
    end
    for _, ws in pairs(skills.weapon_skills) do
        if ws.en and ws.en:lower() == lower then return ws.en end
    end
    return name
end

local function short_number(n)
    n = tonumber(n) or 0
    return ui_hud.format_number(math.floor(n))
end

local function refresh_party_panel()
    if not settings.party_panel then
        hud:set_party_lines(nil)
        return
    end
    local rows, mbs = tracker:sorted(), tracker:sorted_mb()
    if #rows == 0 and #mbs == 0 then
        hud:set_party_lines(nil)
        return
    end
    local max_rows = settings.party_panel_rows or 8
    local lines = {}
    local function section(title, list)
        if #list == 0 then return end
        if #lines > 0 then lines[#lines + 1] = '' end
        lines[#lines + 1] = ('%-12s %4s %8s %8s'):format(title, '#', 'Avg', 'Peak')
        for i = 1, math.min(#list, max_rows) do
            local s = list[i]
            local avg = s.count > 0 and math.floor(s.total / s.count) or 0
            lines[#lines + 1] = ('%-12s %4d %8s %8s'):format(
                tostring(s.name):sub(1, 12), s.count, short_number(avg), short_number(s.peak))
        end
    end
    section('Party WS', rows)
    section('Magic Bursts', mbs)
    hud:set_party_lines(tconcat(lines, '\n'))
end

-- Records a WS and, when the banner mode allows, shows it on the banner.
local function record_and_show(info, ws_name, damage, whiff, target_id)
    local s = tracker:record_ws(info, ws_name, damage, whiff)
    if not s then
        if debug_mode then chat('Blacklisted WS skipped for stats: ' .. tostring(ws_name)) end
        return nil
    end
    local on_banner = settings.banner_mode == 'party' or info.kind == 'self'
    if on_banner and not hud.moving then
        local label
        if settings.banner_mode == 'party' then
            label = tostring(info.name) .. ': ' .. ws_name .. '!'
        else
            label = 'Last WS: ' .. ws_name .. '!'
        end
        hud:show_ws({
            label = label,
            damage = damage,
            whiff = whiff,
            avg = tracker:average(s),
            trend = s.trend,
            trend_color = s.trend_color,
            streak = s.streak,
            target_id = target_id,
        })
    end
    refresh_party_panel()
    if debug_mode then
        chat(('Recorded %s (%s): %s / %s'):format(tostring(info.name), info.kind, ws_name, whiff and 'WHIFF' or tostring(damage)))
    end
    return s
end

local function self_info()
    local p = windower.ffxi.get_player()
    return {id = p and p.id or 0, name = p and p.name or 'You', kind = 'self'}
end

---------------------------------------------------------------------------
-- Packet pipeline
---------------------------------------------------------------------------

local function handle_ws(rec)
    if rec.category == 'weaponskill_finish' and rec.resource ~= 'weapon_skills' then
        if debug_mode then chat('Ignored weaponskill_finish with resource ' .. tostring(rec.resource)) end
        return
    end

    local info = tracker:resolve_actor(rec.actor)
    if not info or not tracker:should_record(info) then return end

    local main_target = rec.targets[1]
    local main = main_target and main_target.actions[1]
    if not main then return end

    local ws_name = action_name(rec.resource, rec.action_id)
    local msg = main.message_id
    local damage, whiff = 0, false

    if DMG_MSGS:contains(msg) then
        if settings.aoe_sum then
            for _, t in ipairs(rec.targets) do
                for _, a in ipairs(t.actions) do
                    if DMG_MSGS:contains(a.message_id) then damage = damage + (a.param or 0) end
                end
            end
        else
            damage = main.param or 0
        end
    elseif WHIFF_MSGS:contains(msg) then
        whiff = true
    else
        if debug_mode and not UTILITY_MSGS:contains(msg) then
            chat(('Unknown message id %d for %s from %s (category %s)'):format(msg, ws_name, tostring(info.name), rec.category))
        end
        return
    end

    record_and_show(info, ws_name, damage, whiff, main_target.id)
end

local function handle_sc_events(events, target_id)
    for _, ev in ipairs(events) do
        if ev.kind == 'skillchain' and ev.target_id == target_id then
            if debug_mode then
                chat(('Skillchain: %s (step %d) on target %s'):format(ev.skillchain, ev.reson.step, tostring(target_id)))
            end
            if not hud.moving and tracker:resolve_actor(ev.actor) then
                hud:sc_bonus(ev.damage)
            end
        elseif ev.kind == 'burst_reset' and debug_mode then
            chat('Chain reset: simultaneous actions on one target.')
        end
    end
end

-- Magic Bursts: every party burst on any mob goes on the tally board
-- (main target's damage, or all targets with aoe_sum); the popup only
-- shows bursts on your current target.
local function handle_mb(rec, target_id)
    local tally, popup_dmg, found = 0, nil, false
    for i, t in ipairs(rec.targets) do
        for _, a in ipairs(t.actions) do
            if MB_DMG_MSGS:contains(a.message_id) then
                if not found or settings.aoe_sum then
                    tally = tally + (a.param or 0)
                end
                found = true
                if t.id == target_id and not popup_dmg then popup_dmg = a.param or 0 end
            end
        end
    end
    if not found then return end

    -- Roster lookup only once an MB is actually present.
    local info = tracker:resolve_actor(rec.actor)
    if not info then return end

    if tracker:should_record(info) then
        tracker:record_mb(info, tally, action_name(rec.resource, rec.action_id))
        refresh_party_panel()
    end

    if popup_dmg and settings.mb_enabled and not hud.manual_hidden and not hud.moving
            and (info.kind == 'self' or settings.mb_party) then
        hud:mb_popup(popup_dmg, info.kind ~= 'self' and info.name or nil)
    end
end

-- Raw category numbers for the six SkillChains categories (which also
-- cover every WS / pet / MB case). Everything else, melee swings included,
-- is dropped before any parsing.
local WANTED_CATEGORIES = {[3] = true, [4] = true, [6] = true, [11] = true, [13] = true, [14] = true}

local function on_action(act)
    if not act or not WANTED_CATEGORIES[act.category] or act.param == 0 then return end
    local rec = sc_engine.parse_action(act, ActionPacket)
    if not rec then return end

    local targ = current_target()
    local target_id = targ and targ.id

    -- 1. SC engine sees every actor and every target.
    local events = engine:process(rec)
    handle_sc_events(events, target_id)

    -- 2. Party / pet / trust WS stats.
    if TRACK_CATEGORIES:contains(rec.category) and rec.param ~= 0 then
        handle_ws(rec)
    end

    -- 3. Magic Burst popup on your current target.
    handle_mb(rec, target_id)
end

-- The listener's return value would modify the packet, so always return nil.
local reported_error = false
ActionPacket.open_listener(function(act)
    local ok, err = pcall(on_action, act)
    if not ok and (debug_mode or not reported_error) then
        reported_error = true
        chat('Action error (please report): ' .. tostring(err))
    end
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function init_player()
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in then return end
    local p = windower.ffxi.get_player()
    if not p then return end
    engine:set_player(p.id, p.main_job)
    engine:load_equipment(windower.ffxi.get_items('equipment'))
end

windower.register_event('load', init_player)
windower.register_event('login', function()
    init_player()
end)

windower.register_event('logout', function()
    engine:logout()
    hud:hide_all()
end)

windower.register_event('job change', function(job_id)
    local job = res.jobs[job_id]
    local short = job and (rawget(job, 'ens') or job.english_short)
    if engine:on_job_change(short) then
        engine:update_weapon()
    end
end)

-- Mob status 2 / 3 = dead / dying.
local function target_dead(id)
    local mob = windower.ffxi.get_mob_by_id(id)
    if not mob then return true end
    return (tonumber(mob.hpp) or 0) <= 0 or mob.status == 2 or mob.status == 3
end

local function check_kill_fade()
    local id = hud.banner_target
    if not id or not settings.banner_hide_on_kill then return end
    if target_dead(id) then
        hud:kill_fade(settings.kill_fade_duration)
        if debug_mode then chat('Banner target died: fading out.') end
    end
end

-- //cw move: drag HUD parts. Returning true keeps the click from the game.
windower.register_event('mouse', function(type, x, y, delta, blocked)
    if blocked or not hud.moving then return end
    local consumed, dropped = hud:mouse(type, x, y)
    if dropped then
        save_settings()
        chat(('%s moved and saved.'):format(dropped.label))
    end
    if consumed then return true end
end)

windower.register_event('incoming chunk', function(id, data)
    engine:on_chunk(id, data)
end)

windower.register_event('prerender', function()
    local now = os.clock()
    if not engine.info.job then init_player() end
    if not hud.moving then
        local view = engine:view(current_target(), now) or hud:test_view(now)
        hud:render_sc(view)
    end
    check_kill_fade()
    hud:update(now)
end)

-- what: nil (WS and MB) | 'ws' | 'mb'
local function reset_average(silent, what)
    tracker:reset(what)
    if what ~= 'mb' then hud:reset_banner_average() end
    refresh_party_panel()
    if not silent then
        chat(what == 'mb' and 'Magic Burst tallies reset.' or what == 'ws' and 'WS stats and average reset.' or 'WS stats, average and Magic Burst tallies reset.')
    end
end

windower.register_event('zone change', function()
    engine:reset()
    if not settings.auto_reset then
        if debug_mode then chat('Auto average reset skipped on zone change.') end
        return
    end
    reset_average(true)
    if debug_mode then chat('Average reset on zone change.') end
end)

windower.register_event('unload', function()
    save_settings()
    engine:close_weapon_check()
    hud:destroy()
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- Test commands are display-only: they never touch real stats, averages
-- or peaks. The banner shows your real average (if any) next to the fake
-- hit, and a separate counter drives the CRANKED x N test streak.
local test_streak = 0
local function test_commit(ws, dmg)
    local whiff = dmg == 'WHIFF'
    local damage = whiff and 0 or tonumber(dmg) or 0
    if not whiff and damage == 99999 then test_streak = test_streak + 1 else test_streak = 0 end
    local me = tracker:get(self_info().id)
    hud:show_ws({
        label = 'Last WS: ' .. ws .. '!',
        damage = damage,
        whiff = whiff,
        avg = me and tracker:average(me) or nil,
        trend = me and me.trend or '',
        trend_color = me and me.trend_color or nil,
        streak = test_streak,
    })
end

local function on_off(value, key, label, after)
    value = tostring(value or ''):lower()
    if value == 'on' or value == 'off' then
        settings[key] = value == 'on'
        save_settings()
        if after then after() end
        chat(label .. ': ' .. (settings[key] and 'ON' or 'OFF'))
    else
        chat(label .. ': ' .. (settings[key] and 'ON' or 'OFF') .. '. Usage: on|off')
    end
end

local function number_setting(arg, key, label, apply, transform)
    local v = tonumber(arg)
    if v then
        if transform then v = transform(v) end
        settings[key] = v
        if apply then apply() end
        save_settings()
        chat(label .. ' saved: ' .. tostring(v))
    else
        chat('Current ' .. label .. ': ' .. tostring(settings[key]))
    end
end

local function relayout() hud:update_display(); hud:request_layout_refresh(0.45) end
local function revisual() hud:apply_all_visual_settings() end

local function copy_default(v)
    if class and class(v) == 'Set' then return S(v) end
    if type(v) == 'table' then
        local t = {}
        for k, x in pairs(v) do t[k] = copy_default(x) end
        return t
    end
    return v
end

-- Everything that decides where a part sits (not its size, font or behaviour).
local POSITION_KEYS = {
    'center_x', 'center_y',
    'banner_offset_x', 'banner_offset_y',
    'line_gap', 'avg_gap', 'flair_gap',
    'flair_offset_y', 'flair_anchor_ratio',
    'sc_gap', 'sc_offset_y',
    'sc_bar_gap', 'sc_bar_offset_x', 'sc_bar_label_overlap', 'sc_chain_counter_gap',
    'mb_offset_x', 'mb_offset_y',
    'party_panel_offset_x', 'party_panel_offset_y',
}

local function reset_positions()
    for _, k in ipairs(POSITION_KEYS) do
        settings[k] = defaults[k]
    end
    -- //cw size derives the banner's line gaps from the WS size; keep them
    -- matched to a non-default size so lines don't overlap.
    local size = tonumber(settings.ws_size)
    if size and size ~= defaults.ws_size then
        settings.line_gap = math.floor(size * 1.22)
        settings.avg_gap = math.floor(size * 2.40)
        settings.flair_gap = math.floor(size * 3.25)
    end
end

local HELP = 'Commands: //cw test | testwhite | testwhiff | testbig | testred | testmassive | testbar | testmb [dmg] | testcrankedstreak'
    .. ' | show | hide | layout | resetpos | pos x y | size 36 | gap 45 | avggap 99 | flairgap 100 | stroke 4 | font Highwind'
    .. ' | fade on|off | fadetime 60 8 | fadein 0.3 | killfade on|off|<sec> | pop on|off | popsize 8 | poptime 0.35 | flairfade 1.5 | flairshrink 0 | flairfloat 32 | whiffshake 6 0.45'
    .. ' | scsize 34 | scfade 4 | scfloat 28 | scoffset 32 | scbar on|off | scbargap 132 | scbarwidth 18 | scbarsize 18 | scbardelay 3 | scbarlabelsize 15 | scbarlabeloverlap 20'
    .. ' | scchaincountersize 18 | scchaincountergap 6 | scdetail on|off | scdetailsize 13 | schud on|off | scburst 0'
    .. ' | sc burst|pet|props|spell|step|timer|weapon|color | scaeonic on|off'
    .. ' | move | mb on|off | mbparty on|off | mbsize 24 | mbx 95 | mby -31'
    .. ' | bannermode self|party | party on|off | party fade on|off | testparty | partypos dx dy | partysize 13 | pets on|off | trusts on|off | alliance on|off | aoesum on|off'
    .. ' | blacklist add|remove|list <ws> | stats | autoreset on|off | reset [ws|mb|all] | factoryreset | debug'

local SC_SHOW_KEYS = {burst = true, pet = true, props = true, spell = true, step = true, timer = true, weapon = true}

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    local arg1, arg2 = args[1], args[2]
    cmd = cmd and cmd:lower() or ''

    if cmd == 'test' then
        test_commit('Savage Blade', '29973')
    elseif cmd == 'testwhite' then
        test_commit('Savage Blade', '9999')
    elseif cmd == 'testwhiff' then
        test_commit('Savage Blade', 'WHIFF')
    elseif cmd == 'testbig' then
        test_commit('Stardiver', '65000')
    elseif cmd == 'testred' then
        test_commit('Savage Blade', '90000')
    elseif cmd == 'testmassive' then
        test_commit('Torcleaver', '99999')
    elseif cmd == 'testcrankedstreak' then
        test_commit('Torcleaver', '99999')
        test_commit('Torcleaver', '99999')
        test_commit('Torcleaver', '99999')

    elseif cmd == 'testsc' or cmd == 'scinfogap' or cmd == 'scdetailgap' then
        chat('The chain line was removed: the skillchain block (closer list + bar) shows the chain. Move the block with //cw move or //cw scbargap.')

    elseif cmd == 'testbar' then
        test_commit('Savage Blade', '54321')
        hud:start_test_bar(settings.sc_bar_delay)
        chat('Test SC bar started.')

    elseif cmd == 'testmb' then
        hud:mb_popup(arg1 or '40000')

    elseif cmd == 'mb' then
        on_off(arg1, 'mb_enabled', 'Magic Burst display', function()
            if not settings.mb_enabled then hud:hide_mb() end
        end)
    elseif cmd == 'mbsize' then
        number_setting(arg1, 'mb_size', 'MB size', function() hud.mb:size(settings.mb_size); relayout() end)
    elseif cmd == 'mbx' then
        number_setting(arg1, 'mb_offset_x', 'MB horizontal offset', relayout)
    elseif cmd == 'mby' then
        number_setting(arg1, 'mb_offset_y', 'MB vertical offset', relayout)

    elseif cmd == 'scbarlabelsize' then
        number_setting(arg1, 'sc_bar_label_size', 'SC bar label size', revisual)
    elseif cmd == 'scbarlabeloverlap' then
        number_setting(arg1, 'sc_bar_label_overlap', 'SC bar label overlap', relayout)
    elseif cmd == 'scchaincountersize' then
        number_setting(arg1, 'sc_chain_counter_size', 'SC chain counter size', revisual)
    elseif cmd == 'scchaincountergap' then
        number_setting(arg1, 'sc_chain_counter_gap', 'SC chain counter offset', relayout)
    elseif cmd == 'scdetail' then
        on_off(arg1, 'sc_detail_enabled', 'Skillchain detail (Step / properties / closer list)', function()
            engine:invalidate()
            if not settings.sc_detail_enabled then hud.sc_detail:hide() end
        end)
    elseif cmd == 'scdetailsize' then
        number_setting(arg1, 'sc_detail_size', 'SC detail size', revisual)
    elseif cmd == 'scburst' then
        number_setting(arg1, 'sc_bar_burst_window', 'Simultaneous-WS reset window (0 = off)', nil, function(v) return math.max(0, v) end)

    elseif cmd == 'pos' then
        local x, y = tonumber(arg1), tonumber(arg2)
        if x and y then
            settings.center_x, settings.center_y = x, y
            relayout()
            save_settings()
            chat('Center position set and saved: ' .. x .. ', ' .. y)
        else
            chat('Current center position: ' .. tostring(settings.center_x) .. ', ' .. tostring(settings.center_y) .. '. Usage: //cw pos <x> <y>')
        end

    elseif cmd == 'size' then
        local size = tonumber(arg1)
        if size then
            settings.ws_size = size
            settings.dmg_size = size + 6
            settings.avg_size = math.max(16, size - 12)
            settings.flair_size = math.max(18, size - 4)
            settings.line_gap = math.floor(size * 1.22)
            settings.avg_gap = math.floor(size * 2.40)
            settings.flair_gap = math.floor(size * 3.25)
            revisual()
            save_settings()
            chat('Size saved: WS ' .. settings.ws_size .. ', damage ' .. settings.dmg_size)
        else
            chat('Current sizes: WS ' .. tostring(settings.ws_size) .. ', damage ' .. tostring(settings.dmg_size) .. ', avg ' .. tostring(settings.avg_size) .. ', flair ' .. tostring(settings.flair_size) .. ', SC ' .. tostring(settings.sc_size))
        end

    elseif cmd == 'gap' then
        number_setting(arg1, 'line_gap', 'Line gap', relayout)
    elseif cmd == 'avggap' then
        number_setting(arg1, 'avg_gap', 'Average gap', relayout)
    elseif cmd == 'flairgap' then
        number_setting(arg1, 'flair_gap', 'Flair gap', relayout)

    elseif cmd == 'stroke' then
        local width = tonumber(arg1)
        if width then
            settings.stroke_width = width
            settings.big_stroke_width = width + 1
            revisual()
            save_settings()
            chat('Stroke width saved: ' .. width)
        else
            chat('Current stroke width: ' .. tostring(settings.stroke_width) .. ' / big ' .. tostring(settings.big_stroke_width))
        end

    elseif cmd == 'font' then
        if arg1 and arg1 ~= '' then
            settings.font = tconcat(args, ' ')
            revisual()
            save_settings()
            chat('Font saved: ' .. settings.font)
        else
            chat('Current font: ' .. tostring(settings.font))
        end

    elseif cmd == 'fade' then
        local value = tostring(arg1 or ''):lower()
        if value == 'on' then
            settings.fade_enabled = true
            hud.last_ws_time = os.clock()
            hud:start_damage_fade_in()
            save_settings()
            chat('Fade enabled.')
        elseif value == 'off' then
            settings.fade_enabled = false
            hud.fade_state = 'visible'
            hud:apply_alpha(255)
            save_settings()
            chat('Fade disabled.')
        else
            chat('Usage: //cw fade on|off')
        end

    elseif cmd == 'fadetime' then
        local hold, out = tonumber(arg1), tonumber(arg2)
        if hold and out then
            settings.hold_duration, settings.fade_out_duration = hold, out
            save_settings()
            chat('Fade timing saved: hold ' .. hold .. 's, out ' .. out .. 's')
        else
            chat('Usage: //cw fadetime 60 8')
        end
    elseif cmd == 'fadein' then
        number_setting(arg1, 'fade_in_duration', 'Fade-in')

    elseif cmd == 'pop' then
        on_off(arg1, 'pop_enabled', 'Pop', function()
            if not settings.pop_enabled then
                hud.pop_active = false
                hud.dmg:size(settings.dmg_size)
                relayout()
            end
        end)
    elseif cmd == 'popsize' then
        number_setting(arg1, 'pop_bonus_size', 'Pop size')
    elseif cmd == 'poptime' then
        number_setting(arg1, 'pop_duration', 'Pop duration')
    elseif cmd == 'flairfade' then
        number_setting(arg1, 'flair_fade_duration', 'Flair fade duration')
    elseif cmd == 'flairshrink' then
        number_setting(arg1, 'flair_shrink_size', 'Flair shrink')
    elseif cmd == 'flairfloat' then
        number_setting(arg1, 'flair_float_distance', 'Flair float distance')

    elseif cmd == 'whiffshake' then
        local strength, duration = tonumber(arg1), tonumber(arg2)
        if strength and duration then
            settings.whiff_shake_strength, settings.whiff_shake_duration = strength, duration
            save_settings()
            chat('WHIFF shake saved: strength ' .. strength .. ', duration ' .. duration .. 's')
        else
            chat('Usage: //cw whiffshake 6 0.45')
        end

    elseif cmd == 'scbar' then
        on_off(arg1, 'sc_bar_enabled', 'Skillchain block (closer list, bar, timer)', function()
            if not settings.sc_bar_enabled then hud:hide_sc_group() end
        end)
    elseif cmd == 'schud' then
        on_off(arg1, 'sc_hud_independent', 'SC HUD independent of the WS banner')
    elseif cmd == 'scbargap' then
        number_setting(arg1, 'sc_bar_gap', 'SC bar gap', relayout)
    elseif cmd == 'scbarwidth' then
        number_setting(arg1, 'sc_bar_width', 'SC bar width', relayout, function(v) return math.max(6, math.floor(v)) end)
    elseif cmd == 'scbarsize' then
        number_setting(arg1, 'sc_bar_size', 'SC bar size', revisual, function(v) return math.max(8, math.floor(v)) end)
    elseif cmd == 'scbardelay' then
        number_setting(arg1, 'sc_bar_delay', 'SC bar delay', nil, function(v) return math.max(0, v) end)
    elseif cmd == 'scsize' then
        number_setting(arg1, 'sc_size', 'SC Bonus size', revisual, function(v) return math.max(10, math.floor(v)) end)
    elseif cmd == 'scfade' then
        number_setting(arg1, 'sc_fade_duration', 'SC fade duration')
    elseif cmd == 'scfloat' then
        number_setting(arg1, 'sc_float_distance', 'SC float distance')
    elseif cmd == 'scoffset' then
        number_setting(arg1, 'sc_offset_y', 'SC vertical offset', relayout)

    elseif cmd == 'sc' then
        local key = tostring(arg1 or ''):lower()
        local job = engine.info.job
        if key == 'color' then
            settings.sc_color = not settings.sc_color
            engine:invalidate()
            save_settings()
            chat('SC colours: ' .. (settings.sc_color and 'ON' or 'OFF'))
        elseif SC_SHOW_KEYS[key] then
            if not job then
                chat('Job not known yet; try again after logging in.')
            else
                local set = settings.Show[key]
                local had = set:contains(job)
                if had then set:remove(job) else set:add(job) end
                engine:invalidate()
                if key == 'weapon' then engine:update_weapon() end
                save_settings()
                chat(('SC %s info will no%s be displayed on %s.'):format(key, had and ' longer' or 'w', job))
            end
        else
            chat('Usage: //cw sc burst|pet|props|spell|step|timer|weapon|color')
        end

    elseif cmd == 'scaeonic' then
        on_off(arg1, 'sc_aeonic', 'Assume others have Aeonic weapons', function() engine:invalidate() end)
    elseif cmd == 'aoesum' then
        on_off(arg1, 'aoe_sum', 'Sum AoE WS damage across all targets')
    elseif cmd == 'pets' then
        on_off(arg1, 'track_pets', 'Track pet TP moves')
    elseif cmd == 'trusts' then
        on_off(arg1, 'track_trusts', 'Track trust WSs')
    elseif cmd == 'alliance' then
        on_off(arg1, 'track_alliance', 'Track alliance members')

    elseif cmd == 'bannermode' then
        local mode = tostring(arg1 or ''):lower()
        if mode == 'self' or mode == 'party' then
            settings.banner_mode = mode
            save_settings()
            chat('Banner mode: ' .. mode)
        else
            chat('Banner mode: ' .. tostring(settings.banner_mode) .. '. Usage: //cw bannermode self|party')
        end

    elseif cmd == 'party' then
        if tostring(arg1 or ''):lower() == 'fade' then
            on_off(arg2, 'party_panel_fade', 'Party panel fades with the banner', function() hud:update_party() end)
        else
            on_off(arg1, 'party_panel', 'Party panel', refresh_party_panel)
        end
    elseif cmd == 'testparty' then
        hud:start_party_test(10)
        chat('Showing a sample party panel for 10 seconds.')
    elseif cmd == 'partypos' then
        local x, y = tonumber(arg1), tonumber(arg2)
        if x and y then
            settings.party_panel_offset_x, settings.party_panel_offset_y = x, y
            relayout()
            save_settings()
            chat('Party panel offset saved: ' .. x .. ', ' .. y)
        else
            chat('Party panel offset: ' .. tostring(settings.party_panel_offset_x) .. ', ' .. tostring(settings.party_panel_offset_y) .. '. Usage: //cw partypos <dx> <dy>')
        end
    elseif cmd == 'partysize' then
        number_setting(arg1, 'party_panel_size', 'Party panel size', revisual)

    elseif cmd == 'blacklist' then
        local sub = tostring(arg1 or ''):lower()
        local name = tconcat(args, ' ', 2)
        local list = settings.ws_blacklist
        if sub == 'add' and name ~= '' then
            name = canonical_ws_name(name)
            list:add(name)
            save_settings()
            chat('Blacklisted (still feeds skillchains): ' .. name)
        elseif sub == 'remove' and name ~= '' then
            name = canonical_ws_name(name)
            list:remove(name)
            save_settings()
            chat('Removed from blacklist: ' .. name)
        elseif sub == 'list' then
            local names = {}
            for n in pairs(list) do if type(n) == 'string' then names[#names + 1] = n end end
            table.sort(names)
            chat('Blacklist: ' .. (#names > 0 and tconcat(names, ', ') or '(empty)'))
        else
            chat('Usage: //cw blacklist add|remove|list <weapon skill>')
        end

    elseif cmd == 'stats' then
        local rows = tracker:sorted()
        if #rows == 0 then
            chat('No WSs recorded yet.')
        end
        for _, s in ipairs(rows) do
            chat(('%s (%s): %d WS, avg %s, peak %s%s, whiffs %d'):format(s.name, s.kind, s.count,
                short_number(tracker:average(s) or 0), short_number(s.peak),
                s.peak_ws and (' [' .. s.peak_ws .. ']') or '', s.whiffs))
        end
        local mbs = tracker:sorted_mb()
        for _, m in ipairs(mbs) do
            chat(('%s MB: %d bursts, avg %s, peak %s%s'):format(m.name, m.count,
                short_number(math.floor(m.total / math.max(m.count, 1))), short_number(m.peak),
                m.peak_spell and (' [' .. m.peak_spell .. ']') or ''))
        end

    elseif cmd == 'layout' then
        chat('Layout: pos ' .. tostring(settings.center_x) .. ', ' .. tostring(settings.center_y)
            .. ' | gap ' .. tostring(settings.line_gap)
            .. ' | avggap ' .. tostring(settings.avg_gap)
            .. ' | flairgap ' .. tostring(settings.flair_gap)
            .. ' | scgap ' .. tostring(settings.sc_gap)
            .. ' | font ' .. tostring(settings.font))

    elseif cmd == 'reset' or cmd == 'resetavg' then
        local what = tostring(arg1 or ''):lower()
        if what == 'ws' or what == 'mb' then
            reset_average(false, what)
        elseif what == '' or what == 'all' then
            reset_average(false)
        else
            chat('Usage: //cw reset [ws|mb|all]')
        end

    elseif cmd == 'autoreset' then
        on_off(arg1, 'auto_reset', 'Auto average reset')

    elseif cmd == 'killfade' then
        local v = tonumber(arg1)
        if v then
            settings.kill_fade_duration = math.max(0, v)
            save_settings()
            chat('Kill fade time saved: ' .. tostring(settings.kill_fade_duration) .. 's')
        else
            on_off(arg1, 'banner_hide_on_kill', 'Fade the banner when its target dies')
        end

    elseif cmd == 'resetpos' then
        reset_positions()
        relayout()
        save_settings()
        chat('Positions reset to default and saved. Sizes, fonts and other settings unchanged.')

    elseif cmd == 'mbparty' then
        on_off(arg1, 'mb_party', "Show party members' Magic Bursts")

    elseif cmd == 'factoryreset' then
        for k, v in pairs(defaults) do
            settings[k] = fresh_defaults[k] and fresh_defaults[k]() or copy_default(v)
        end
        engine.settings = settings
        engine:invalidate()
        revisual()
        save_settings()
        chat('Factory settings reset and saved.')

    elseif cmd == 'move' then
        if hud.moving then
            hud:stop_move()
            refresh_party_panel()
            save_settings()
            chat('Move mode off. Positions saved.')
        else
            hud:start_move()
            chat('Move mode: every part has a coloured box and a name tag. Drag a part with the left mouse button; it saves when you let go.')
            chat('Each part moves on its own; the Banner moves the WS line, damage, average, flair and SC Bonus together. //cw pos x y moves the whole HUD. Parts: ' .. hud:legend() .. '. Parts you have switched off are not shown.')
            chat('//cw move again when done. //cw resetpos puts everything back.')
        end

    elseif cmd == 'hide' then
        if hud.moving then hud:stop_move() end
        hud:hide_all()

    elseif cmd == 'show' then
        hud:force_visible()

    elseif cmd == 'debug' then
        debug_mode = not debug_mode
        chat('Debug mode: ' .. tostring(debug_mode))

    else
        chat(HELP)
        if cmd == 'help' then
            chat('Unload the separate SkillChains addon (//lua u skillchains): CrankWatch now includes it.')
        end
    end
end)

hud:apply_all_visual_settings()
hud:update_display()
hud:apply_alpha(0)
hud.fade_state = 'hidden'
hud.alpha_current = 0
init_player()
