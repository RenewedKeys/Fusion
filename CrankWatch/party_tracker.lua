-- party_tracker.lua: party/alliance roster lookup and per-actor WS statistics.
--
-- Roster rules (locked decisions 3 and 5):
--   * p0-p5 always; a10-a15 / a20-a25 when settings.track_alliance is on.
--   * Trusts are party slots whose mob has is_npc == true. They are only
--     recorded when settings.track_trusts is on (default off).
--   * Pets are matched by comparing the actor mob's index with each party
--     member's mob.pet_index. Recorded when settings.track_pets is on.
--   * Anyone else returns nil (their actions still feed sc_engine upstream).

require('luau')

local M = {}

M.party_slots = {'p0', 'p1', 'p2', 'p3', 'p4', 'p5'}
M.alliance_slots = {'a10', 'a11', 'a12', 'a13', 'a14', 'a15', 'a20', 'a21', 'a22', 'a23', 'a24', 'a25'}

M.RECENT_MAX = 25
M.CRANK_VALUE = 99999

local Tracker = {}
Tracker.__index = Tracker

-- opts: settings, api (windower.ffxi-like)
function M.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Tracker)
    self.settings = opts.settings or {}
    self.api = opts.api or (windower and windower.ffxi)
    self.stats = {}
    self.order = 0
    return self
end

local function member_id(member)
    if type(member) ~= 'table' then return nil end
    if type(member.mob) == 'table' and member.mob.id then
        return tonumber(member.mob.id)
    end
    return tonumber(member.id)
end

local function set_has(set, key)
    if not set or key == nil then return false end
    if type(set.contains) == 'function' then return set:contains(key) end
    return set[key] and true or false
end

function Tracker:player_id()
    local p = self.api and self.api.get_player and self.api.get_player()
    return p and p.id
end

-- Returns a list of {id, name, slot, is_npc, mob} for the roster in scope.
function Tracker:roster()
    local party = self.api and self.api.get_party and self.api.get_party()
    local list = {}
    if not party then return list end
    local function add(slot)
        local m = party[slot]
        local id = member_id(m)
        if id then
            list[#list + 1] = {
                id = id,
                name = m.name or (m.mob and m.mob.name) or tostring(id),
                slot = slot,
                is_npc = type(m.mob) == 'table' and m.mob.is_npc == true or false,
                mob = m.mob,
            }
        end
    end
    for _, slot in ipairs(M.party_slots) do add(slot) end
    if self.settings.track_alliance then
        for _, slot in ipairs(M.alliance_slots) do add(slot) end
    end
    return list
end

-- Resolve an actor id into roster info, or nil when the actor is outside
-- the tracked party/alliance. info.kind is 'self' | 'party' | 'alliance' |
-- 'trust' | 'pet'.
function Tracker:resolve_actor(actor_id)
    actor_id = tonumber(actor_id)
    if not actor_id then return nil end
    local me = self:player_id()
    local roster = self:roster()

    for _, m in ipairs(roster) do
        if m.id == actor_id then
            local kind
            if m.id == me then
                kind = 'self'
            elseif m.is_npc then
                kind = 'trust'
            elseif m.slot:sub(1, 1) == 'a' then
                kind = 'alliance'
            else
                kind = 'party'
            end
            return {id = actor_id, name = m.name, kind = kind, is_npc = m.is_npc, slot = m.slot}
        end
    end

    -- Pet: actor mob index == some member's pet_index.
    local mob = self.api and self.api.get_mob_by_id and self.api.get_mob_by_id(actor_id)
    if mob and mob.index then
        for _, m in ipairs(roster) do
            if type(m.mob) == 'table' and m.mob.pet_index and m.mob.pet_index == mob.index then
                return {
                    id = actor_id,
                    name = mob.name or ('Pet #' .. actor_id),
                    kind = 'pet',
                    is_npc = true,
                    owner_id = m.id,
                    owner_name = m.name,
                }
            end
        end
    end
    return nil
end

-- Whether this actor's WSs go into damage stats / banner.
function Tracker:should_record(info)
    if not info then return false end
    if info.kind == 'trust' then return self.settings.track_trusts and true or false end
    if info.kind == 'pet' then return self.settings.track_pets and true or false end
    return true
end

function Tracker:is_blacklisted(ws_name)
    return set_has(self.settings.ws_blacklist, ws_name)
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------

local function new_entry(info, order)
    return {
        id = info.id,
        name = info.name,
        kind = info.kind,
        order = order,
        total = 0,
        count = 0,
        whiffs = 0,
        peak = 0,
        peak_ws = nil,
        recent = {},
        streak = 0,
        trend = '',
        trend_color = {255, 255, 255},
        last_ws = nil,
        last_dmg = 0,
        last_whiff = false,
        by_ws = {},
    }
end

-- Port of CrankWatch's update_avg_trend: last 5 versus the previous 20,
-- starting once 10 successful WSs exist.
function M.trend(recent)
    local n = #recent
    if n < 10 then
        return '', {255, 255, 255}
    end
    local recent_count = math.min(5, math.floor(n / 2))
    local previous_count = math.min(20, n - recent_count)
    local recent_sum, previous_sum = 0, 0
    for i = n - recent_count + 1, n do
        recent_sum = recent_sum + (recent[i] or 0)
    end
    for i = n - recent_count - previous_count + 1, n - recent_count do
        previous_sum = previous_sum + (recent[i] or 0)
    end
    local recent_avg = recent_sum / math.max(recent_count, 1)
    local previous_avg = previous_sum / math.max(previous_count, 1)
    if recent_avg > previous_avg * 1.02 then
        return '↑', {80, 255, 80}
    elseif recent_avg < previous_avg * 0.98 then
        return '↓', {255, 80, 80}
    end
    return '→', {255, 255, 255}
end

-- Record one WS. Returns the actor's stats entry, or nil when the WS is
-- blacklisted (blacklisted WSs never touch stats or the banner).
function Tracker:record_ws(info, ws_name, damage, whiff)
    if not info or not ws_name then return nil end
    if self:is_blacklisted(ws_name) then return nil end

    local s = self.stats[info.id]
    if not s then
        self.order = self.order + 1
        s = new_entry(info, self.order)
        self.stats[info.id] = s
    end
    s.name = info.name or s.name
    s.kind = info.kind or s.kind

    damage = tonumber(damage) or 0
    s.last_ws = ws_name
    s.last_whiff = whiff and true or false
    s.last_dmg = whiff and 0 or damage

    local w = s.by_ws[ws_name]
    if not w then
        w = {total = 0, count = 0, whiffs = 0, peak = 0}
        s.by_ws[ws_name] = w
    end

    if whiff then
        s.whiffs = s.whiffs + 1
        w.whiffs = w.whiffs + 1
        s.streak = 0
        return s
    end

    s.total = s.total + damage
    s.count = s.count + 1
    w.total = w.total + damage
    w.count = w.count + 1
    if damage > w.peak then w.peak = damage end
    if damage > s.peak then
        s.peak = damage
        s.peak_ws = ws_name
    end

    s.recent[#s.recent + 1] = damage
    if #s.recent > M.RECENT_MAX then
        table.remove(s.recent, 1)
    end
    s.trend, s.trend_color = M.trend(s.recent)

    if damage == M.CRANK_VALUE then
        s.streak = s.streak + 1
    else
        s.streak = 0
    end
    return s
end

function Tracker:average(s)
    if not s or s.count <= 0 then return nil end
    return math.floor(s.total / s.count)
end

function Tracker:get(id)
    return self.stats[id]
end

-- Entries sorted by total damage (desc), then first-seen order.
function Tracker:sorted()
    local list = {}
    for _, s in pairs(self.stats) do list[#list + 1] = s end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.order < b.order
    end)
    return list
end

function Tracker:reset()
    self.stats = {}
    self.order = 0
end

return M
