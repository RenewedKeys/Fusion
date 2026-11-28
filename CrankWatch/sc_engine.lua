--[[
Copyright © 2017, Ivaar
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
* Neither the name of SkillChains nor the
  names of its contributors may be used to endorse or promote products
  derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL IVAAR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

-- sc_engine.lua: Ivaar's SkillChains resonance engine (v2.20.08.25), ported
-- into a module for CrankWatch. The chain logic (sc_info, check_props,
-- aeonic_prop, aeonic_am, chain buffs, chainbound, timers) is unchanged.
-- CrankWatch changes:
--   * state lives on an engine object instead of globals
--   * guards for buffs[info.player] / check_weapon being nil
-- Like Ivaar, only the first (main) target of an action is tracked; the
-- game only lets the main target be skillchained.
--   * view() returns plain data for ui_hud instead of drawing text

require('luau')
require('pack')

local M = {}

local tconcat = (_raw and _raw.table and _raw.table.concat) or table.concat

local function S_(t)
    local s = {}
    for _, v in ipairs(t) do s[v] = true end
    return s
end

M.message_ids = S_{110, 185, 187, 317, 802}
M.skillchain_ids = S_{288,289,290,291,292,293,294,295,296,297,298,299,300,301,
    385,386,387,388,389,390,391,392,393,394,395,396,397,398,767,768,769,770}
-- Skillchain messages where the mob absorbs the damage ("recovers N hit
-- points"). They still count for the chain, but N is healing, not damage.
M.absorb_ids = S_{385,386,387,388,389,390,391,392,393,394,395,396,397,398,769,770}
M.buff_dur = {[163]=40, [164]=30, [470]=60}
M.categories = S_{
    'weaponskill_finish',
    'spell_finish',
    'job_ability',
    'mob_tp_finish',
    'avatar_tp_finish',
    'job_ability_unblinkable',
}

-- Fallback for packets whose add-effect animation could not be named.
M.sc_by_message = {
    [288]='Light', [289]='Darkness', [290]='Gravitation', [291]='Fragmentation',
    [292]='Distortion', [293]='Fusion', [294]='Compression', [295]='Liquefaction',
    [296]='Induration', [297]='Reverberation', [298]='Transfixion', [299]='Scission',
    [300]='Detonation', [301]='Impaction',
    [767]='Radiance', [768]='Umbra', [769]='Radiance', [770]='Umbra',
    -- the same skillchains when the mob absorbs the damage (recovers HP)
    [385]='Light', [386]='Darkness', [387]='Gravitation', [388]='Fragmentation',
    [389]='Distortion', [390]='Fusion', [391]='Compression', [392]='Liquefaction',
    [393]='Induration', [394]='Reverberation', [395]='Transfixion', [396]='Scission',
    [397]='Detonation', [398]='Impaction',
}

local colors = {}            -- CrankWatch palette: bright enough to read over any zone
colors.Light =         '\\cs(255,255,170)'   -- pale gold
colors.Radiance =      '\\cs(255,250,225)'   -- near-white glow (Lv.4)
colors.Dark =          '\\cs(165,115,255)'   -- violet
colors.Umbra =         '\\cs(200,160,255)'   -- bright violet (Lv.4)
colors.Ice =           '\\cs(140,230,255)'   -- frost
colors.Water =         '\\cs(100,150,255)'   -- clear blue
colors.Earth =         '\\cs(230,185,85)'    -- sand / amber
colors.Wind =          '\\cs(110,255,130)'   -- green
colors.Fire =          '\\cs(255,90,80)'     -- red
colors.Lightning =     '\\cs(255,110,220)'   -- hot magenta
colors.Gravitation =   '\\cs(205,150,115)'   -- bronze (Earth + Dark)
colors.Fragmentation = '\\cs(255,185,245)'   -- soft pink (Wind + Lightning)
colors.Fusion =        '\\cs(255,154,60)'    -- orange (Fire + Light)
colors.Distortion =    '\\cs(60,185,255)'    -- azure (Ice + Water)
colors.Darkness =      colors.Dark
colors.Compression =   colors.Dark
colors.Transfixion =   colors.Light
colors.Induration =    colors.Ice
colors.Reverberation = colors.Water
colors.Scission =      colors.Earth
colors.Detonation =    colors.Wind
colors.Liquefaction =  colors.Fire
colors.Impaction =     colors.Lightning
M.colors = colors

local sc_info = {
    Radiance = {'Fire','Wind','Lightning','Light', lvl=4},
    Umbra = {'Earth','Ice','Water','Dark', lvl=4},
    Light = {'Fire','Wind','Lightning','Light', Light={4,'Light','Radiance'}, lvl=3},
    Darkness = {'Earth','Ice','Water','Dark', Darkness={4,'Darkness','Umbra'}, lvl=3},
    Gravitation = {'Earth','Dark', Distortion={3,'Darkness'}, Fragmentation={2,'Fragmentation'}, lvl=2},
    Fragmentation = {'Wind','Lightning', Fusion={3,'Light'}, Distortion={2,'Distortion'}, lvl=2},
    Distortion = {'Ice','Water', Gravitation={3,'Darkness'}, Fusion={2,'Fusion'}, lvl=2},
    Fusion = {'Fire','Light', Fragmentation={3,'Light'}, Gravitation={2,'Gravitation'}, lvl=2},
    Compression = {'Darkness', Transfixion={1,'Transfixion'}, Detonation={1,'Detonation'}, lvl=1},
    Liquefaction = {'Fire', Impaction={2,'Fusion'}, Scission={1,'Scission'}, lvl=1},
    Induration = {'Ice', Reverberation={2,'Fragmentation'}, Compression={1,'Compression'}, Impaction={1,'Impaction'}, lvl=1},
    Reverberation = {'Water', Induration={1,'Induration'}, Impaction={1,'Impaction'}, lvl=1},
    Transfixion = {'Light', Scission={2,'Distortion'}, Reverberation={1,'Reverberation'}, Compression={1,'Compression'}, lvl=1},
    Scission = {'Earth', Liquefaction={1,'Liquefaction'}, Reverberation={1,'Reverberation'}, Detonation={1,'Detonation'}, lvl=1},
    Detonation = {'Wind', Compression={2,'Gravitation'}, Scission={1,'Scission'}, lvl=1},
    Impaction = {'Lightning', Liquefaction={1,'Liquefaction'}, Detonation={1,'Detonation'}, lvl=1},
}
M.sc_info = sc_info

local chainbound = {}
chainbound[1] = {'Compression','Liquefaction','Induration','Reverberation','Scission'}
chainbound[2] = {'Gravitation','Fragmentation','Distortion','Compression','Liquefaction','Induration','Reverberation','Scission'}
chainbound[3] = {'Light','Darkness','Gravitation','Fragmentation','Distortion','Compression','Liquefaction','Induration','Reverberation','Scission'}
M.chainbound = chainbound

M.aeonic_weapon = {
    [20515] = 'Godhands',
    [20594] = 'Aeneas',
    [20695] = 'Sequence',
    [20843] = 'Chango',
    [20890] = 'Anguta',
    [20935] = 'Trishula',
    [20977] = 'Heishi Shorinken',
    [21025] = 'Dojikiri Yasutsuna',
    [21082] = 'Tishtrya',
    [21147] = 'Khatvanga',
    [21485] = 'Fomalhaut',
    [21694] = 'Lionheart',
    [21753] = 'Tri-edge',
    [22117] = 'Fail-Not',
    [22131] = 'Fail-Not',
    [22143] = 'Fomalhaut'
}

-- Ivaar's per-job display defaults. Each key gets its own set so toggling
-- one category never mutates another.
M.all_jobs = {'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'}
function M.default_show()
    return {
        burst  = S(M.all_jobs),
        pet    = S{'BST','SMN'},
        props  = S(M.all_jobs),
        spell  = S{'SCH','BLU'},
        step   = S{},              -- CrankWatch: Step line off by default (the timer line's Chain: N covers it)
        timer  = S(M.all_jobs),
        weapon = S(M.all_jobs),
    }
end

local function ucfirst(s)
    s = tostring(s or '')
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

local function res_name(entry)
    if type(entry) ~= 'table' then return nil end
    return entry.name or rawget(entry, 'en') or rawget(entry, 'english')
end
M.res_name = res_name

local function has(set, key)
    if not set or key == nil then return false end
    if type(set.contains) == 'function' then return set:contains(key) end
    return set[key] and true or false
end

---------------------------------------------------------------------------
-- Pure Ivaar logic
---------------------------------------------------------------------------

function M.check_props(old, new)
    for k = 1, #old do
        local first = old[k]
        local combo = sc_info[first]
        if combo then
            for i = 1, #new do
                local second = new[i]
                local result = combo[second]
                if result then
                    return unpack(result)
                end
                if #old > 3 and sc_info[second] and combo.lvl == sc_info[second].lvl then
                    break
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Action packet normalisation
---------------------------------------------------------------------------

-- Turns a raw act table (windower.packets.parse_action) into a plain record,
-- using Windower's ActionPacket library for category/resource resolution.
-- Every target and every sub-action is kept so damage parsing and per-target
-- resonance can share it.
function M.parse_action(act, AP)
    AP = AP or ActionPacket
    if not act or not AP then return nil end
    local ap = AP.new(act)
    if not ap then return nil end

    local rec = {
        category = ap:get_category_string(),
        actor = ap:get_id(),
        param = act.param,
        targets = {},
    }

    for target in ap:get_targets() do
        local t = {id = target.id, actions = {}}
        for action in target:get_actions() do
            local param, resource, action_id, interruption, conclusion = action:get_spell()
            local add_effect = action:get_add_effect()
            t.actions[#t.actions + 1] = {
                message_id = action:get_message_id(),
                param = tonumber(action.param) or 0,
                spell_param = param,
                resource = resource,
                action_id = action_id,
                interruption = interruption,
                conclusion = conclusion,
                add_effect = add_effect or nil,
            }
        end
        rec.targets[#rec.targets + 1] = t
    end

    local first = rec.targets[1] and rec.targets[1].actions[1]
    if first then
        rec.resource = first.resource
        rec.action_id = first.action_id
        rec.conclusion = first.conclusion
    end
    return rec
end

---------------------------------------------------------------------------
-- Engine object
---------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

-- opts: skills, res, settings, api (windower.ffxi-like), clock, time
function M.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Engine)
    self.skills = opts.skills or require('skills')
    self.res = opts.res or res
    self.settings = opts.settings or {}
    self.api = opts.api or (windower and windower.ffxi)
    self.clock = opts.clock or os.clock
    self.time = opts.time or os.time
    self.info = {}
    self.resonating = {}
    self.buffs = {}
    return self
end

function Engine:set_player(id, job)
    if id then self.info.player = id end
    if job then self.info.job = job end
    if self.info.player and not self.buffs[self.info.player] then
        self.buffs[self.info.player] = {}
    end
end

function Engine:show(key)
    local show = self.settings.Show
    return show ~= nil and has(show[key], self.info.job)
end

function Engine:aeonic_am(step)
    local mine = self.buffs[self.info.player]
    if not mine then return false end
    for x = 270, 272 do
        if mine[x] then
            return 272 - x < step
        end
    end
    return false
end

function Engine:aeonic_prop(ability, actor)
    local info = self.info
    if ability.aeonic and (ability.weapon == info.aeonic and actor == info.player
            or self.settings.sc_aeonic and info.player ~= actor) then
        return {ability.skillchain[1], ability.skillchain[2], ability.aeonic}
    end
    return ability.skillchain
end

local function check_buff(t, i, now)
    if t[i] == true or (type(t[i]) == 'number' and t[i] - (now or os.time()) > 0) then
        return true
    end
    t[i] = nil
end

-- now: the engine's clock (self.time()); os.time() when omitted, as in Ivaar.
function M.chain_buff(t, now)
    local i = t[164] and 164 or t[470] and 470
    if i and check_buff(t, i, now) then
        t[i] = nil
        return true
    end
    return t[163] and check_buff(t, 163, now) or false
end

function Engine:apply_properties(target, resource, action_id, properties, delay, step, closed, bound, extra)
    local clock = self.clock()
    local reson = {
        res = resource,
        id = action_id,
        active = properties,
        start = clock,
        delay = clock + delay,
        times = clock + delay + 8 - step,
        step = step,
        closed = closed,
        bound = bound,
    }
    if extra then
        for k, v in pairs(extra) do reson[k] = v end
    end
    self.resonating[target] = reson
    return reson
end

function Engine:default_delay(ability)
    return ability and ability.delay or tonumber(self.settings.sc_bar_delay) or 3
end

-- Ivaar's action_handler for one target. Returns an event table or nil.
function Engine:process_target(rec, target, ability)
    local action = target.actions[1]
    if not action then return nil end

    local actor = rec.actor
    local resource, action_id = rec.resource, rec.action_id
    local message_id = action.message_id
    local add_effect = action.add_effect
    local param = action.spell_param
    local extra = {actor = actor}

    if add_effect and action.conclusion and M.skillchain_ids[tonumber(add_effect.message_id)] then
        local skillchain = add_effect.animation and ucfirst(add_effect.animation)
        if not sc_info[skillchain] then
            skillchain = M.sc_by_message[tonumber(add_effect.message_id)]
        end
        if not skillchain or not sc_info[skillchain] then return nil end

        local level = sc_info[skillchain].lvl
        local reson = self.resonating[target.id]
        local delay = self:default_delay(ability)
        local step = (reson and reson.step or 1) + 1

        if level == 3 and reson and ability then
            level = M.check_props(reson.active, self:aeonic_prop(ability, actor))
        end

        local closed = step > 5 or level == 4
        local absorbed = M.absorb_ids[tonumber(add_effect.message_id)] and true or false
        extra.sc_damage = absorbed and 0 or (tonumber(add_effect.param) or 0)
        local new = self:apply_properties(target.id, resource, action_id, {skillchain}, delay, step, closed, nil, extra)
        return {kind = 'skillchain', target_id = target.id, actor = actor, reson = new,
            skillchain = skillchain, damage = extra.sc_damage, absorbed = absorbed}

    elseif ability and (M.message_ids[message_id]
            or message_id == 2 and self.buffs[actor] and M.chain_buff(self.buffs[actor], self.time())) then
        local reson = self:apply_properties(target.id, resource, action_id,
            self:aeonic_prop(ability, actor), self:default_delay(ability), 1, nil, nil, extra)
        return {kind = 'open', target_id = target.id, actor = actor, reson = reson}

    elseif message_id == 529 and chainbound[param] then
        local reson = self:apply_properties(target.id, resource, action_id, chainbound[param], 2, 1, false, param, extra)
        return {kind = 'chainbound', target_id = target.id, actor = actor, reson = reson}

    elseif message_id == 100 and M.buff_dur[param] then
        self.buffs[actor] = self.buffs[actor] or {}
        self.buffs[actor][param] = M.buff_dur[param] + self.time()
        return {kind = 'buff', actor = actor, buff = param}
    end
end

-- Feed one normalised record. Returns a list of events (possibly empty).
-- As in Ivaar's action_handler, only the first target is looked at.
function Engine:process(rec)
    local events = {}
    if not rec or not M.categories[rec.category] or rec.param == 0 then
        return events
    end
    local skills = self.skills
    local ability = rec.resource and skills[rec.resource] and skills[rec.resource][rec.action_id]
    local target = rec.targets[1]
    local ev = target and self:process_target(rec, target, ability)
    if ev then events[1] = ev end
    return events
end

---------------------------------------------------------------------------
-- Display data
---------------------------------------------------------------------------

function Engine:colorize(t)
    if not t then return '' end
    local out = {}
    for k = 1, #t do
        out[k] = self.settings.sc_color and ('%s%s\\cr'):format(colors[t[k]] or '', t[k]) or t[k]
    end
    return tconcat(out, ',')
end

function Engine:add_skills(t, abilities, active, resource, AM)
    local tt = {{}, {}, {}, {}}
    local skill_table = self.skills[resource]
    if not skill_table or not abilities then return t end
    for k = 1, #abilities do
        local ability_id = abilities[k]
        local skillchain = skill_table[ability_id]
        if skillchain then
            local lv, prop, aeonic = M.check_props(active, self:aeonic_prop(skillchain, self.info.player))
            if prop then
                prop = AM and aeonic or prop
                local r = self.res[resource]
                local name = r and res_name(r[ability_id]) or skillchain.en or tostring(ability_id)
                tt[lv][#tt[lv] + 1] = {lv = lv, text = self.settings.sc_color and
                    ('%-16s → Lv.%d %s%-14s\\cr'):format(name, lv, colors[prop] or '', prop) or
                    ('%-16s → Lv.%d %-14s'):format(name, lv, prop)}
            end
        end
    end
    for x = 4, 1, -1 do
        for k = #tt[x], 1, -1 do
            t[#t + 1] = tt[x][k]
        end
    end
    return t
end

-- Ivaar's check_results: the "what to use -> what it makes" list.
-- Ivaar's check_results, plus a row cap (settings.sc_closer_rows, 0 = no
-- cap). Rows from every source (spells / pet moves / weapon skills) are
-- sorted by level, highest first, before the cap is applied, so the cap
-- never drops a Lv.4 weapon skill in favour of a Lv.1 spell.
function Engine:compute_closers(reson)
    local api = self.api or {}
    local job = self.info.job
    local t = {}
    if self:show('spell') and job == 'SCH' then
        t = self:add_skills(t, {0,1,2,3,4,5,6,7}, reson.active, 'elements')
    elseif self:show('spell') and job == 'BLU' then
        local mjob = api.get_mjob_data and api.get_mjob_data()
        t = self:add_skills(t, mjob and mjob.spells, reson.active, 'spells')
    elseif self:show('pet') and api.get_mob_by_target and api.get_mob_by_target('pet') then
        local abilities = api.get_abilities and api.get_abilities()
        t = self:add_skills(t, abilities and abilities.job_abilities, reson.active, 'job_abilities')
    end
    if self:show('weapon') then
        local abilities = api.get_abilities and api.get_abilities()
        t = self:add_skills(t, abilities and abilities.weapon_skills, reson.active, 'weapon_skills',
            self.info.aeonic and self:aeonic_am(reson.step))
    end
    for i, row in ipairs(t) do row.order = i end
    table.sort(t, function(a, b)
        if a.lv ~= b.lv then return a.lv > b.lv end
        return a.order < b.order
    end)
    local cap = tonumber(self.settings.sc_closer_rows) or 0
    local lines = {}
    for i, row in ipairs(t) do
        if cap > 0 and i > cap then break end
        lines[i] = row.text
    end
    return tconcat(lines, '\n')
end

function Engine:expire(now)
    now = now or self.clock()
    for k, v in pairs(self.resonating) do
        if v.times - now + 10 < 0 then
            self.resonating[k] = nil
        end
    end
end

-- Ivaar's prerender logic, returning data instead of drawing.
-- targ: a mob table ({id=, hpp=}) or nil.
function Engine:view(targ, now)
    now = now or self.clock()
    self:expire(now)
    if not targ or not targ.id then return nil end
    local reson = self.resonating[targ.id]
    if not reson then return nil end
    local timer = reson.times - now
    if not ((tonumber(targ.hpp) or 0) > 0 and timer > 0) then return nil end

    local phase
    if not reson.closed then
        -- //cw scdetail off: skip the closer list entirely.
        if self.settings.sc_detail_enabled == false then
            reson.disp_info = ''
        else
            reson.disp_info = reson.disp_info or self:compute_closers(reson)
        end
        phase = now < reson.delay and 'wait' or 'go'
    elseif self:show('burst') then
        reson.disp_info = ''
        phase = 'burst'
    else
        self.resonating[targ.id] = nil
        return nil
    end

    local r = self.res[reson.res]
    reson.name = (r and res_name(r[reson.id]))
        or (self.skills[reson.res] and self.skills[reson.res][reson.id] and self.skills[reson.res][reson.id].en)
        or '?'
    reson.props = reson.props or (not reson.bound and self:colorize(reson.active) or ('Chainbound Lv.%d'):format(reson.bound))
    reson.elements = reson.elements or (reson.step > 1 and self:show('burst')
        and ('(%s)'):format(self:colorize(sc_info[reson.active[1]])) or '')

    return {
        target_id = targ.id,
        phase = phase,
        wait_remaining = math.max(0, reson.delay - now),
        wait_total = math.max(reson.delay - (reson.start or reson.delay), 0.01),
        remaining = timer,
        window_total = math.max(reson.times - reson.delay, 0.01),
        step = reson.step,
        chain = reson.step - 1,
        sc_name = reson.step > 1 and reson.active[1] or nil,
        name = reson.name,
        props = reson.props,
        elements = reson.elements,
        closers = reson.disp_info or '',
        bound = reson.bound,
        show_timer = self:show('timer'),
        show_step = self:show('step'),
        show_props = self:show('props'),
        show_burst = self:show('burst'),
    }
end

-- Drop cached strings so job / colour changes re-render immediately.
function Engine:invalidate()
    for _, reson in pairs(self.resonating) do
        reson.disp_info = nil
        reson.props = nil
        reson.elements = nil
    end
end

function Engine:on_job_change(job)
    if job and job ~= self.info.job then
        self.info.job = job
        self:invalidate()
        return true
    end
    return false
end

function Engine:reset()
    self.resonating = {}
end

function Engine:logout()
    self:close_weapon_check()
    self.info = {}
    self.resonating = {}
    self.buffs = {}
end

---------------------------------------------------------------------------
-- Equipment / buff tracking (incoming chunks)
---------------------------------------------------------------------------

function Engine:close_weapon_check()
    if self.check_weapon and coroutine.close then
        pcall(coroutine.close, self.check_weapon)
    end
    self.check_weapon = nil
end

function Engine:update_weapon()
    if not self:show('weapon') then
        return
    end
    local api = self.api
    if not api or not api.get_items or not self.info.main_bag or not self.info.main_weapon then
        return
    end
    local item = api.get_items(self.info.main_bag, self.info.main_weapon)
    local main_weapon = item and item.id or 0
    if main_weapon ~= 0 then
        local ranged = self.info.range and self.info.range_bag and api.get_items(self.info.range_bag, self.info.range)
        self.info.aeonic = M.aeonic_weapon[main_weapon] or (ranged and M.aeonic_weapon[ranged.id]) or nil
        return
    end
    if coroutine.schedule and (not self.check_weapon or coroutine.status(self.check_weapon) ~= 'suspended') then
        self.check_weapon = coroutine.schedule(function() self:update_weapon() end, 10)
    end
end

function Engine:load_equipment(equip)
    if not equip then return end
    self.info.main_weapon = equip.main
    self.info.main_bag = equip.main_bag
    self.info.range = equip.range
    self.info.range_bag = equip.range_bag
    self:update_weapon()
end

-- Must never return a value: Windower treats a return from an
-- incoming chunk handler as a packet modification.
function Engine:on_chunk(id, data)
    if id == 0x29 then
        if data:unpack('H', 25) == 206 and data:unpack('I', 9) == self.info.player then
            local mine = self.buffs[self.info.player]
            if mine then
                mine[data:unpack('H', 13)] = nil
            end
        end
    elseif id == 0x50 and data:byte(6) == 0 then
        self.info.main_weapon = data:byte(5)
        self.info.main_bag = data:byte(7)
        self:update_weapon()
    elseif id == 0x50 and data:byte(6) == 2 then
        self.info.range = data:byte(5)
        self.info.range_bag = data:byte(7)
        self:update_weapon()
    elseif id == 0x63 and data:byte(5) == 9 then
        local set_buff = {}
        for n = 1, 32 do
            local buff = data:unpack('H', n * 2 + 7)
            if M.buff_dur[buff] or buff > 269 and buff < 273 then
                set_buff[buff] = true
            end
        end
        if self.info.player then
            self.buffs[self.info.player] = set_buff
        end
    end
end

return M
