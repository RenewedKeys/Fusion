-- ui_hud.lua: every CrankWatch text object, layout and animation.
--
-- All text objects are created through hud:obj() and stored in one ordered
-- registry, so hide / apply_alpha / apply_all_visual_settings / destroy can
-- never miss one (the old file leaked 7 of 16 on unload).
--
-- Groups:
--   banner : Last WS line, damage, Avg label/value/trend, flair, SC Bonus,
--            Fades in/holds/fades out as before.
--   party  : party panel. Stays up while it has data (or follows the banner
--            fade with settings.party_panel_fade); see Hud:update_party().
--   sc     : bar, "SC Window:" label + status, Chain counter, chain info
--            (prefix / coloured name / elements) and the SC detail block
--            (Step, properties, closer list). Independent of the banner
--            when settings.sc_hud_independent is on.
--   mb     : Magic Burst popup (own fade/shake timer).

require('luau')

local M = {}

-- luau replaces table.concat with a pairs-order version; keep the raw one.
local tconcat = (_raw and _raw.table and _raw.table.concat) or table.concat

local Hud = {}
Hud.__index = Hud

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
M.clamp = clamp

function M.format_number(num)
    local s = tostring(num or '')
    s = s:gsub(',', '')
    return (s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
end

---------------------------------------------------------------------------
-- Skillchain colours / element strings (unchanged from CrankWatch 2.0)
---------------------------------------------------------------------------

function M.damage_style(dmg, whiff, settings, cranked_text)
    if whiff then
        return 180, 180, 180, settings.stroke_width, 'LOL'
    end
    dmg = tonumber(dmg) or 0
    if dmg == 99999 then
        return 180, 100, 255, settings.big_stroke_width, cranked_text or 'CRANKED!!!'
    elseif dmg >= 80000 then
        return 255, 70, 70, settings.big_stroke_width, 'MASSIVE HIT!!'
    elseif dmg >= 50000 then
        return 255, 215, 0, settings.big_stroke_width, 'BIG HIT!'
    elseif dmg >= 10000 then
        return 100, 170, 255, settings.stroke_width, nil
    end
    return 255, 255, 255, settings.stroke_width, nil
end

function M.cranked_text(streak)
    if (streak or 0) <= 1 then return 'CRANKED!!!' end
    return 'CRANKED x ' .. tostring(streak)
end

function M.make_bar(width, percent)
    width = math.max(6, math.floor(width or 34))
    percent = clamp(percent or 0, 0, 1)
    local filled = math.floor((width * percent) + 0.5)
    return string.rep('█', filled) .. string.rep('░', width - filled)
end

---------------------------------------------------------------------------
-- Construction / registry
---------------------------------------------------------------------------

M.BANNER = {'ws', 'dmg', 'avg', 'avg_label', 'avg_value', 'avg_trend', 'flair', 'sc'}
M.SC = {'sc_bar', 'sc_bar_label', 'sc_bar_status', 'sc_chain_counter', 'sc_detail'}

-- opts: settings, texts (library), clock
function M.new(opts)
    local self = setmetatable({}, Hud)
    self.settings = opts.settings
    self.texts = opts.texts or require('texts')
    self.clock = opts.clock or os.clock
    self.registry = {}
    self.by_name = {}

    -- banner state
    self.alpha_current = 0
    self.fade_state = 'hidden'
    self.fade_start = 0
    self.last_ws_time = 0
    self.ws_queue = {}
    self.is_whiff = false
    self.whiff_shaking, self.whiff_shake_start = false, 0
    self.pop_active, self.pop_start = false, 0
    self.flair_visible, self.flair_fading = false, false
    self.flair_fade_start, self.flair_base_size, self.flair_fade_start_alpha, self.flair_start_y = 0, 0, 255, 0
    self.sc_visible, self.sc_fading = false, false
    self.sc_fade_start, self.sc_fade_start_alpha, self.sc_start_y = 0, 255, 0
    self.layout_refresh_until = 0
    self.banner = {label = 'Last WS: -!', dmg = '-', avg = '-', avg_raw = 0, trend = '', trend_color = {255, 255, 255}, raw = 0, cranked = 'CRANKED!!!'}
    self.party_lines = nil

    -- sc state
    self.sc_bar_active = false
    self.sc_phase = nil
    self.sc_target = nil
    self.sc_bar_shake_start = 0
    self.chain_counter_visible = false
    self.detail_value = ''

    -- mb state
    self.mb_visible, self.mb_start_time, self.mb_expire, self.mb_shake_start = false, 0, 0, 0
    self.mb_lines = {}

    -- move (drag) mode
    self.moving = false
    self.drag = nil

    local s = self.settings
    self:obj('ws', s.ws_size)
    self:obj('dmg', s.dmg_size)
    self:obj('avg', s.avg_size)
    self:obj('avg_label', s.avg_size)
    self:obj('avg_value', s.avg_size)
    self:obj('avg_trend', s.avg_size)
    self:obj('sc', s.sc_size or s.avg_size)
    self:obj('sc_bar', s.sc_bar_size or s.avg_size)
    self:obj('sc_bar_label', s.sc_bar_label_size or 15)
    self:obj('sc_bar_status', s.sc_bar_label_size or 15)
    self:obj('sc_chain_counter', s.sc_chain_counter_size or 18)
    self:obj('sc_detail', s.sc_detail_size or 13)
    self:obj('mb', s.mb_size or 18)
    self:obj('flair', s.flair_size)
    self:obj('party', s.party_panel_size or 13)
    -- move-mode name tags, one per draggable part
    for _, part in ipairs(M.PARTS) do
        self:obj('tag_' .. part.name, TAG_SIZE)
    end

    for _, o in ipairs(self.registry) do o:hide() end
    return self
end

function Hud:text_settings(size)
    local s = self.settings
    return {
        pos = {x = s.center_x, y = s.center_y},
        bg = {visible = false, alpha = 0},
        flags = {bold = true, draggable = false, right = false, bottom = false},
        padding = 0,
        text = {
            font = s.font, size = size, alpha = 255, red = 255, green = 255, blue = 255,
            stroke = {width = s.stroke_width, alpha = 255, red = 0, green = 0, blue = 0},
        },
    }
end

function Hud:obj(name, size)
    local o = self.texts.new('', self:text_settings(size))
    self.registry[#self.registry + 1] = o
    self.by_name[name] = o
    self[name] = o
    return o
end

function Hud:each(names, fn)
    for _, n in ipairs(names) do fn(self.by_name[n], n) end
end

local function set_alpha(o, a)
    o:alpha(a)
    o:stroke_alpha(a)
end

local function extents(o)
    local w = o:extents()
    return tonumber(w) or 0
end

---------------------------------------------------------------------------
-- Visibility rules
---------------------------------------------------------------------------

function Hud:banner_visible()
    return self.fade_state ~= 'hidden' and self.alpha_current > 0
end

function Hud:sc_allowed()
    if self.manual_hidden then return false end
    if self.settings.sc_hud_independent then return true end
    return self:banner_visible()
end

function Hud:sc_alpha()
    if self.settings.sc_hud_independent then return 255 end
    return self.alpha_current > 0 and self.alpha_current or 255
end

function Hud:party_enabled()
    return self.settings.party_panel and self.party_lines ~= nil and self.party_lines ~= ''
end

function Hud:apply_alpha(alpha)
    alpha = clamp(math.floor(alpha or 255), 0, 255)
    self.alpha_current = alpha

    for _, n in ipairs({'ws', 'dmg', 'avg', 'avg_label', 'avg_value', 'avg_trend'}) do
        set_alpha(self[n], alpha)
    end
    if self.sc_visible and not self.sc_fading then set_alpha(self.sc, alpha) end
    if not self.flair_fading then set_alpha(self.flair, alpha) end
    if not self.settings.sc_hud_independent then
        if self.sc_bar_active then
            set_alpha(self.sc_bar, alpha); set_alpha(self.sc_bar_label, alpha); set_alpha(self.sc_bar_status, alpha)
            set_alpha(self.sc_detail, alpha)
        end
        if self.chain_counter_visible then set_alpha(self.sc_chain_counter, alpha) end
    end

    if alpha <= 0 then
        self:each(M.BANNER, function(o) o:hide() end)
        if not self.settings.sc_hud_independent then
            self:each(M.SC, function(o) o:hide() end)
        end
    else
        self.ws:show(); self.dmg:show()
        self.avg:hide()
        self:show_avg_line()
        if self.sc_visible then self.sc:show() end
        if self.flair_visible then self.flair:show() end
    end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

function Hud:request_layout_refresh(duration)
    self.layout_refresh_until = self.clock() + (duration or 0.35)
end

-- The banner (Last WS line, damage, average, hit flair, SC Bonus) is one
-- block. Its origin is the HUD centre plus its own offset, so dragging it
-- in //cw move never moves the skillchain block, party panel or MB popup.
function Hud:banner_x()
    local s = self.settings
    return s.center_x + (s.banner_offset_x or 0)
end

function Hud:banner_y()
    local s = self.settings
    return s.center_y + (s.banner_offset_y or 0)
end

-- Centre a banner line on the banner origin.
function Hud:position_line(o, y)
    o:pos(math.floor(self:banner_x() - (extents(o) / 2)), y)
end

function Hud:position_avg_line()
    local s = self.settings
    -- left-aligned with the Last WS line, as in 2.0
    local x = self.ws:pos()
    local y = self:banner_y() + s.avg_gap
    self.avg_label:pos(x, y)
    local lw = extents(self.avg_label)
    self.avg_value:pos(math.floor(x + lw), y)
    local vw = extents(self.avg_value)
    self.avg_trend:pos(math.floor(x + lw + vw + 8), y - 5)
    self.avg:hide()
end

local function shake_offset(start, duration, strength, freq, clock)
    if not start or start <= 0 then return 0, 0 end
    local t = (clock - start) / math.max(duration, 0.01)
    if t >= 1 then return 0, 0 end
    return math.floor(math.sin(t * freq) * strength * (1 - t)), start
end

-- The skillchain block moves as one unit, top to bottom:
--     red/green bar
--     "SC Window: GO!! 4.2  Chain: N"
--     closer list (Step / properties / what to use next)  - //cw scdetail
-- The bar stays put; the closer list grows downward under it.
-- sc_bar_gap / sc_bar_offset_x place the block's top-left corner.
local function text_height(o, size)
    local _, h = o:extents()
    h = tonumber(h) or 0
    if h <= 0 then h = math.floor((size or 12) * 1.4) end
    return h
end

-- Height of the closer list plus its gap (0 when it isn't shown).
function Hud:block_detail_height()
    if not (self:detail_enabled() and self.detail_value ~= '') then return 0 end
    return text_height(self.sc_detail, self.settings.sc_detail_size or 13) + 4
end

-- Height of the whole block from its top edge.
function Hud:block_height()
    local s = self.settings
    return self:block_detail_height() + (s.sc_bar_label_overlap or 20)
        + text_height(self.sc_bar_label, s.sc_bar_label_size or 15)
end

function Hud:position_sc_bar()
    local s = self.settings
    local now = self.clock()
    local y = s.center_y + (s.sc_bar_gap or ((s.avg_gap or 99) + 34))
    do
        -- y is the block's top. Keep the whole block on screen: flip it
        -- above the banner if it would run off the bottom.
        local _, sh = M.screen()
        local dragging = self.drag and self.drag.part.name == 'sc_bar'
        local total = self:block_height()
        if y + total > sh and not dragging then
            y = math.floor(s.center_y - total - 8)
        end
        y = math.max(0, y)
        self.block_top = y   -- the bar is the top of the block
    end
    local bar_w = extents(self.sc_bar)
    -- block x is from the banner centre, so it doesn't shift with the
    -- length of the WS name on the Last WS line
    local x = s.center_x + (s.sc_bar_offset_x or -200)

    local dx, keep = shake_offset(self.sc_bar_shake_start, s.sc_bar_shake_duration or 0.35, s.sc_bar_shake_strength or 5, 60, now)
    self.sc_bar_shake_start = keep
    x = math.floor(x + dx)
    self.sc_bar:pos(x, y)

    local lw = extents(self.sc_bar_label)
    local sw = extents(self.sc_bar_status)
    local lx = math.floor(x + (bar_w / 2) - ((lw + sw) / 2))
    local ly = math.floor(y + (s.sc_bar_label_overlap or 20))
    self.sc_bar_label:pos(lx, ly)
    self.sc_bar_status:pos(math.floor(lx + lw), ly)
    self.sc_chain_counter:pos(math.floor(lx + lw + sw + (s.sc_chain_counter_gap or 6)), ly)
end

-- Screen size from Windower (falls back to 1080p).
function M.screen()
    local ok, ws = pcall(function() return windower.get_windower_settings() end)
    if ok and type(ws) == 'table' then
        return ws.ui_x_res or ws.x_res or 1920, ws.ui_y_res or ws.y_res or 1080
    end
    return 1920, 1080
end

-- Closer list: under the SC Window line, left-aligned with the bar.
function Hud:position_detail()
    local s = self.settings
    local x = self.sc_bar:pos()
    local _, ly = self.sc_bar_label:pos()
    self.sc_detail:pos(math.floor(x), math.floor(ly + text_height(self.sc_bar_label, s.sc_bar_label_size or 15) + 4))
end

-- MB popup: its own position, from the banner centre (mb_offset_x is from
-- the centre line, mb_offset_y from center_y). Nothing else moves it.
function Hud:position_mb()
    local s = self.settings
    local w = extents(self.mb)
    local x = math.floor(s.center_x - (w / 2) + (s.mb_offset_x or 0))
    local y = math.floor(s.center_y + (s.mb_offset_y or 101))
    local dx, keep = shake_offset(self.mb_shake_start, s.mb_shake_duration or 0.50, s.mb_shake_strength or 5, 80, self.clock())
    self.mb_shake_start = keep
    self.mb:pos(x + dx, y)
end

-- Party panel docks to the right of the banner, or to the left when the
-- right side would run off screen.
function Hud:position_party()
    local s = self.settings
    local sw, sh = M.screen()
    local w, h = self.party:extents()
    w, h = tonumber(w) or 0, tonumber(h) or 0
    local off = s.party_panel_offset_x or 260
    local x = math.floor(s.center_x + off)
    local dragging = self.drag and self.drag.part.name == 'party'
    if x + w > sw and not dragging then
        x = math.floor(s.center_x - off - w)
    end
    local y = math.floor(s.center_y + (s.party_panel_offset_y or 0))
    if y + h > sh and not dragging then y = sh - h end
    self.party:pos(math.max(0, x), math.max(0, y))
end

function Hud:update_display()
    local s = self.settings
    local b = self.banner
    self.ws:text(b.label)
    self.dmg:text(self.is_whiff and 'WHIFF!!' or (b.dmg .. ' damage!!'))
    self.avg:text('')
    self.avg_label:text('Avg: ')
    self.avg_value:text(b.avg)
    self:apply_trend_style()

    self:position_line(self.ws, self:banner_y())
    if not self.whiff_shaking then
        self:position_line(self.dmg, self:banner_y() + s.line_gap)
    end
    self:position_avg_line()
    if not self:avg_shown() then
        self.avg_label:hide(); self.avg_value:hide(); self.avg_trend:hide()
    end
    if self.sc_bar_active then self:position_sc_bar() end
    if self.sc_bar_active then self:position_detail() end
    if self.mb_visible then self:position_mb() end
    if self.flair_visible and not self.flair_fading then
        self:position_flair(self:banner_y() + s.flair_gap)
    end
    self:position_party()
end

---------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------

function Hud:apply_avg_style(avg)
    local s = self.settings
    avg = tonumber(avg) or 0
    local o = self.avg_value
    if avg >= 80000 then
        o:color(255, 70, 70); o:stroke_width(s.big_stroke_width)
    elseif avg >= 50000 then
        o:color(255, 215, 0); o:stroke_width(s.big_stroke_width)
    elseif avg >= 10000 then
        o:color(100, 170, 255); o:stroke_width(s.stroke_width)
    else
        o:color(255, 255, 255); o:stroke_width(s.stroke_width)
    end
end

function Hud:apply_trend_style()
    local b = self.banner
    local o = self.avg_trend
    o:text(b.trend or '')
    o:font('Consolas')
    o:size(self.settings.avg_size)
    o:color(b.trend_color[1] or 255, b.trend_color[2] or 255, b.trend_color[3] or 255)
    o:stroke_width(self.settings.stroke_width)
    if b.trend ~= '' and self:avg_shown() and self:banner_visible() then o:show() else o:hide() end
end

-- Show or hide the Avg line according to //cw avg.
function Hud:show_avg_line()
    if self:avg_shown() then
        self.avg_label:show(); self.avg_value:show()
        if self.banner.trend ~= '' then self.avg_trend:show() else self.avg_trend:hide() end
    else
        self.avg_label:hide(); self.avg_value:hide(); self.avg_trend:hide()
    end
end

function Hud:apply_damage_style()
    local s = self.settings
    local r, g, b, stroke, flair = M.damage_style(self.banner.raw, self.is_whiff, s, self.banner.cranked)
    self.dmg:color(r, g, b)
    self.dmg:stroke_width(stroke)
    local f = self.flair
    if flair then
        f:text(flair)
        f:color(255, 255, 255)
        f:stroke_width(stroke)
        f:size(s.flair_size)
        set_alpha(f, self.alpha_current)
        f:show()
        self.flair_visible, self.flair_fading = true, true
        self.flair_fade_start = self.clock()
        self.flair_base_size = s.flair_size
        self.flair_fade_start_alpha = self.alpha_current
        self.flair_start_y = self:banner_y() + s.flair_gap
    else
        f:hide()
        self.flair_visible, self.flair_fading = false, false
        self.flair_fade_start = 0
    end
end

---------------------------------------------------------------------------
-- Banner (hero) updates
---------------------------------------------------------------------------

function Hud:start_damage_fade_in()
    if not self.settings.fade_enabled then
        self.fade_state = 'visible'
        self:apply_alpha(255)
        return
    end
    self.fade_state = 'damage_fade_in'
    self.fade_start = self.clock()
    self.ws:show(); self.dmg:show()
    self:show_avg_line()
    if self.sc_visible then self.sc:show() end
    for _, n in ipairs({'ws', 'avg', 'avg_label', 'avg_value', 'avg_trend'}) do set_alpha(self[n], 255) end
    if self.sc_visible and not self.sc_fading then set_alpha(self.sc, 255) end
    set_alpha(self.dmg, 1)
    if self.flair_visible then
        self.flair:show()
        if self.flair_fading then
            self.flair_fade_start_alpha = 255
            set_alpha(self.flair, 255)
        end
    end
    self.alpha_current = 255
end

function Hud:start_pop(raw)
    local s = self.settings
    if not s.pop_enabled or (tonumber(raw) or 0) < 50000 then return end
    self.pop_active = true
    self.pop_start = self.clock()
    self.dmg:size(s.dmg_size + s.pop_bonus_size)
    self:update_display()
end

-- entry: {label, damage (number), whiff (bool), avg (number|nil),
--         trend, trend_color, streak}
-- Back-to-back WSs: each one stays on the banner for at least
-- settings.banner_min_show seconds before the next takes over, so fast
-- WSs are all readable. Your own WS (entry.is_self) goes ahead of queued
-- party WSs. Past WS_QUEUE_MAX waiting, the oldest party WS is skipped so
-- the banner never lags far behind. 0 = show every WS instantly.
M.WS_QUEUE_MAX = 3

function Hud:min_show()
    return math.max(0, tonumber(self.settings.banner_min_show) or 0)
end

function Hud:queue_ws(entry)
    local min, q = self:min_show(), self.ws_queue
    local banner_free = self.fade_state == 'hidden' or self.manual_hidden
        or self.clock() - self.last_ws_time >= min
    if min <= 0 or (#q == 0 and banner_free) then
        self:show_ws(entry)
        return 'shown'
    end
    local pos = #q + 1
    if entry.is_self then
        for i, e in ipairs(q) do
            if not e.is_self then pos = i break end
        end
    end
    table.insert(q, pos, entry)
    while #q > M.WS_QUEUE_MAX do
        local drop = 1
        for i, e in ipairs(q) do
            if not e.is_self then drop = i break end
        end
        table.remove(q, drop)
    end
    return 'queued'
end

function Hud:pump_ws_queue(now)
    local q = self.ws_queue
    if #q == 0 or self.moving then return end
    if (now or self.clock()) - self.last_ws_time < self:min_show() then return end
    self:show_ws(table.remove(q, 1))
end

function Hud:clear_ws_queue()
    self.ws_queue = {}
end

-- A skillchain's bonus belongs to the WS that closed it. If that WS is
-- still waiting in the queue, the bonus shows when the WS does.
function Hud:sc_bonus_for(actor, dmg)
    local q = self.ws_queue
    for i = #q, 1, -1 do
        if q[i].actor == actor and q[i].sc_bonus == nil then
            q[i].sc_bonus = dmg
            return 'queued'
        end
    end
    return self:sc_bonus(dmg)
end

function Hud:show_ws(entry)
    self.manual_hidden = false
    self.banner_target = entry.target_id
    self.fade_out_override = nil
    self.is_whiff = entry.whiff and true or false
    local b = self.banner
    b.label = entry.label
    b.raw = self.is_whiff and 0 or (tonumber(entry.damage) or 0)
    b.dmg = self.is_whiff and 'WHIFF' or M.format_number(b.raw)
    if entry.avg then
        b.avg = M.format_number(entry.avg)
        b.avg_raw = entry.avg
    else
        b.avg, b.avg_raw = '-', 0
    end
    b.trend = entry.trend or ''
    b.trend_color = entry.trend_color or {255, 255, 255}
    b.cranked = M.cranked_text(entry.streak)

    self.last_ws_time = self.clock()
    self:apply_avg_style(b.avg_raw)
    self:apply_damage_style()
    self:update_display()
    self:request_layout_refresh(0.45)
    if self.is_whiff then
        self.whiff_shaking = true
        self.whiff_shake_start = self.clock()
    else
        self.whiff_shaking = false
        self:start_pop(b.raw)
    end
    self:start_damage_fade_in()
    if entry.sc_bonus then self:sc_bonus(entry.sc_bonus) end
end

function Hud:reset_banner_average()
    local b = self.banner
    b.avg, b.avg_raw, b.trend, b.trend_color = '-', 0, '', {255, 255, 255}
    self:apply_avg_style(0)
    self:apply_trend_style()
    self:update_display()
    self:request_layout_refresh(0.45)
end

-- //cw avg: show the Avg line (and trend arrow) on the banner. Averages
-- are tracked either way, for the party panel and //cw stats.
function Hud:avg_shown()
    return self.settings.show_banner_avg == true
end

-- SC Bonus sits directly under the lowest banner line: the Avg line when it
-- is shown, otherwise the damage line. Worked out from settings (not live
-- positions) so pop / shake animations don't move it.
function Hud:sc_anchor_bottom()
    local s = self.settings
    if self:avg_shown() then
        return self:banner_y() + s.avg_gap + text_height(self.avg_label, s.avg_size)
    end
    return self:banner_y() + s.line_gap + text_height(self.dmg, s.dmg_size or 42)
end

-- SC Bonus top edge before it floats (sc_offset_y is a small nudge).
function Hud:sc_start()
    return math.floor(self:sc_anchor_bottom() + (self.settings.sc_offset_y or 4))
end

function Hud:position_sc_line(y)
    local s = self.settings
    self.sc:pos(math.floor(self:banner_x() - (extents(self.sc) / 2)), y)
end

-- Hit flair (BIG HIT! / MASSIVE HIT!! / CRANKED!!!) starts at the right end
-- of the damage line, level with it (flair_anchor_ratio 1 = right edge, plus
-- a small gap), then floats up and fades. flair_gap sets its height.
function Hud:position_flair(y)
    local s = self.settings
    local dx = self.dmg:pos()
    local ratio = s.flair_anchor_ratio or 1
    local gap = ratio >= 1 and math.floor((s.ws_size or 36) * 0.3) or 0
    self.flair:pos(
        math.floor(dx + (extents(self.dmg) * ratio) + gap),
        math.floor(y + (s.flair_offset_y or -4)))
end

-- SC Bonus float: tied to the banner (decision 6).
function Hud:sc_bonus(dmg)
    local s = self.settings
    if not s.sc_enabled or not self:banner_visible() then return false end
    local raw = tonumber(dmg) or 0
    if raw < 0 then return false end
    local o = self.sc
    o:text('SC Bonus: ' .. M.format_number(raw) .. '!!')
    o:font(s.font)
    o:size(s.sc_size or s.flair_size)
    o:color(120, 255, 255)
    o:stroke_width(s.stroke_width)
    set_alpha(o, 255)
    self.sc_start_y = self:sc_start()
    self:position_sc_line(self.sc_start_y)
    self.sc_visible, self.sc_fading = true, true
    self.sc_fade_start = self.clock()
    self.sc_fade_start_alpha = 255
    o:show()
    return true
end

-- who: nil for your own burst, otherwise the caster's name. Bursts that
-- land while the popup is still up stack as extra lines (newest last).
function Hud:mb_popup(dmg, who)
    local s = self.settings
    if not s.mb_enabled then return false end
    local raw = tonumber(tostring(dmg or '0'):gsub(',', ''), 10) or 0
    if raw < 0 then return false end
    local now = self.clock()
    local line = (who and (tostring(who) .. ' MB: ') or 'MB: ') .. M.format_number(raw) .. '!!'
    local stacking = self.mb_visible and now < self.mb_expire
    if not stacking then
        self.mb_lines = {}
        self.mb_start_time = now
    end
    local lines = self.mb_lines
    lines[#lines + 1] = line
    while #lines > (s.mb_max_lines or 4) do table.remove(lines, 1) end
    local o = self.mb
    o:text(tconcat(lines, '\n'))
    o:font(s.font or 'Highwind')
    o:size(s.mb_size or 18)
    o:color(255, 140, 255)
    o:stroke_width(s.stroke_width)
    if not stacking then set_alpha(o, 0) end
    self.mb_visible = true
    self.mb_shake_start = now
    self.mb_expire = now + (s.mb_duration or 3.0)
    self:position_mb()
    o:show()
    return true
end

function Hud:hide_mb()
    self.mb_visible = false
    self.mb:hide()
end

function Hud:set_party_lines(text)
    self.party_lines = text
    local o = self.party
    o:font(self.settings.party_panel_font or 'Consolas')
    o:size(self.settings.party_panel_size or 13)
    o:color(255, 255, 255)
    o:stroke_width(math.max(1, (self.settings.stroke_width or 4) - 2))
    self.party_shown_text = nil
    self:update_party()
end

---------------------------------------------------------------------------
-- SC HUD (the skillchain block)
---------------------------------------------------------------------------

-- //cw scdetail: the Step / properties / closer list block.
function Hud:detail_enabled()
    return self.settings.sc_detail_enabled ~= false
end

function Hud:parts()
    return M.PARTS
end

-- Move mode only shows (and lets you drag) parts that are switched on.
function Hud:part_enabled(part)
    local s = self.settings
    local name = part.name
    if name == 'mb' then return s.mb_enabled ~= false end
    if name == 'party' then return s.party_panel == true end
    if name == 'sc_bar' then return s.sc_bar_enabled ~= false end
    return true   -- banner, damage, average and flair are always on
end

-- Some parts are groups; a member can be off on its own.
function Hud:obj_enabled(n)
    if n == 'sc' then return self.settings.sc_enabled ~= false end
    if n == 'sc_detail' then return self:detail_enabled() end
    if n == 'sc_chain_counter' then return self.settings.sc_chain_counter_enabled ~= false end
    if n == 'avg_label' or n == 'avg_value' then return self:avg_shown() end
    if n == 'avg_trend' then return self:avg_shown() and self.banner.trend ~= '' end
    return true
end

function Hud:hide_sc_group()
    self.sc_bar_active = false
    self.sc_phase, self.sc_target = nil, nil
    self.sc_bar:hide(); self.sc_bar_label:hide(); self.sc_bar_status:hide()
    self.chain_counter_visible = false
    self.sc_chain_counter:hide()
    self.sc_detail:hide()
end

function M.detail_lines(view)
    local lines = {}
    if view.show_step then
        lines[#lines + 1] = ('Step: %d → %s'):format(view.step or 1, tostring(view.name or '?'))
    end
    if view.show_props then
        lines[#lines + 1] = ('[%s] %s'):format(view.props or '', view.elements or '')
    elseif view.show_burst and (view.elements or '') ~= '' then
        lines[#lines + 1] = view.elements
    end
    if view.closers and view.closers ~= '' then
        lines[#lines + 1] = view.closers
    end
    return tconcat(lines, '\n')
end

-- view: sc_engine Engine:view() output (or a test view), or nil.
function Hud:render_sc(view)
    local s = self.settings
    if not s.sc_bar_enabled or not view then
        if self.sc_bar_active then self:hide_sc_group() end
        return
    end

    local now = self.clock()
    local first = not self.sc_bar_active or self.sc_target ~= view.target_id
    self.sc_bar_active = true
    local a = self:sc_alpha()

    -- Bar + status
    local bar, label, status = self.sc_bar, self.sc_bar_label, self.sc_bar_status
    local width = s.sc_bar_width or 34
    local timer = ''
    if view.phase == 'wait' then
        if view.show_timer then timer = (' %.1f'):format(view.wait_remaining) end
        bar:color(255, 70, 70)
        bar:text(M.make_bar(width, view.wait_remaining / math.max(view.wait_total, 0.01)))
        status:color(255, 40, 40)
        status:text('Wait. . .' .. timer)
    elseif view.phase == 'go' then
        if not first and self.sc_phase == 'wait' then self.sc_bar_shake_start = now end
        if view.show_timer then timer = (' %.1f'):format(view.remaining) end
        bar:color(80, 255, 120)
        bar:text(M.make_bar(width, view.remaining / math.max(view.window_total, 0.01)))
        status:color(80, 255, 80)
        status:text('GO!!' .. timer)
    else -- burst
        if view.show_timer then timer = (' %d'):format(math.floor(view.remaining)) end
        bar:color(255, 140, 255)
        bar:text(M.make_bar(width, view.remaining / math.max(view.window_total, 0.01)))
        status:color(255, 140, 255)
        status:text('Burst!' .. timer)
    end
    label:color(255, 255, 255)
    label:text('SC Window: ')
    self.sc_phase = view.phase
    self.sc_target = view.target_id

    bar:font(s.sc_bar_font or 'Consolas'); bar:size(s.sc_bar_size or s.avg_size); bar:stroke_width(s.stroke_width)
    for _, o in ipairs({label, status, self.sc_chain_counter}) do
        o:font(s.font or 'Highwind'); o:stroke_width(s.stroke_width)
    end
    label:size(s.sc_bar_label_size or 15); status:size(s.sc_bar_label_size or 15)
    self.sc_chain_counter:size(s.sc_chain_counter_size or 18)

    -- Chain counter
    self.chain_counter_visible = s.sc_chain_counter_enabled and (view.chain or 0) > 0
    if self.chain_counter_visible then
        self.sc_chain_counter:text('Chain: ' .. tostring(view.chain))
        self.sc_chain_counter:color(255, 255, 255)
    end

    -- Detail block (Step / properties / closers)
    self.detail_value = M.detail_lines(view)
    local d = self.sc_detail
    d:text(self.detail_value)
    d:font(s.sc_detail_font or 'Consolas')
    d:size(s.sc_detail_size or 13)
    d:color(255, 255, 255)
    d:stroke_width(math.max(1, (s.stroke_width or 4) - 2))

    self:position_sc_bar()
    self:position_detail()
    if self.mb_visible then self:position_mb() end

    if self:sc_allowed() then
        for _, o in ipairs({bar, label, status}) do set_alpha(o, a); o:show() end
        if self.chain_counter_visible then set_alpha(self.sc_chain_counter, a); self.sc_chain_counter:show() else self.sc_chain_counter:hide() end
        if self:detail_enabled() and self.detail_value ~= '' then set_alpha(d, a); d:show() else d:hide() end
    else
        for _, o in ipairs({bar, label, status, self.sc_chain_counter, d}) do o:hide() end
    end
end

-- Synthetic view for //cw testbar: Wait for `delay`, then a 7s GO window.
function Hud:start_test_bar(delay)
    self.test_bar = {start = self.clock(), delay = tonumber(delay) or 3}
end

function Hud:test_view(now)
    local t = self.test_bar
    if not t then return nil end
    now = now or self.clock()
    local elapsed = now - t.start
    local window = 7
    if elapsed >= t.delay + window then
        self.test_bar = nil
        return nil
    end
    return {
        target_id = 'test',
        phase = elapsed < t.delay and 'wait' or 'go',
        wait_remaining = math.max(0, t.delay - elapsed),
        wait_total = math.max(t.delay, 0.01),
        remaining = t.delay + window - elapsed,
        window_total = window,
        step = 1, chain = 0, name = 'Savage Blade',
        props = 'Fragmentation,Scission', elements = '',
        closers = '', show_timer = true, show_step = self:part_shown('step'), show_props = true, show_burst = true,
    }
end

---------------------------------------------------------------------------
-- Per-frame animation
---------------------------------------------------------------------------

function Hud:update_frame(now)
    now = now or self.clock()
    local s = self.settings
    if self.moving then
        self:render_move()
        return
    end

    if self.layout_refresh_until > 0 then
        if now <= self.layout_refresh_until then
            self:update_display()
        else
            self.layout_refresh_until = 0
        end
    end

    -- MB popup
    if self.mb_visible then
        if now >= self.mb_expire then
            self:hide_mb()
        else
            local fade_in = math.max(s.mb_fade_in_duration or 0.15, 0.01)
            local fade_out = math.max(s.mb_fade_out_duration or 0.35, 0.01)
            local elapsed = now - self.mb_start_time
            local remaining = self.mb_expire - now
            local a = 255
            if elapsed < fade_in then
                a = math.floor(255 * (elapsed / fade_in))
            elseif remaining < fade_out then
                a = math.floor(255 * (remaining / fade_out))
            end
            set_alpha(self.mb, clamp(a, 0, 255))
            self:position_mb()
            self.mb:show()
        end
    end

    -- SC Bonus float
    if self.sc_visible and self.sc_fading then
        local t = (now - self.sc_fade_start) / math.max(s.sc_fade_duration or 4.5, 0.01)
        if t >= 1 then
            self.sc:hide()
            self.sc_visible, self.sc_fading = false, false
            set_alpha(self.sc, 0)
        else
            local eased = 1 - ((1 - t) * (1 - t))
            set_alpha(self.sc, math.floor(self.sc_fade_start_alpha * (1 - t)))
            self.sc:show()
            local y = math.floor(self.sc_start_y - ((s.sc_float_distance or 32) * eased))
            -- float up, but never into the line above it
            self:position_sc_line(math.max(y, math.floor(self:sc_anchor_bottom() + 2)))
        end
    end

    -- Flair float / shrink
    if self.flair_visible and self.flair_fading then
        local t = (now - self.flair_fade_start) / math.max(s.flair_fade_duration, 0.01)
        if t >= 1 then
            self.flair:hide()
            self.flair_visible, self.flair_fading = false, false
            self.flair:size(s.flair_size)
            set_alpha(self.flair, 0)
        else
            local eased = 1 - ((1 - t) * (1 - t))
            local y = math.floor(self.flair_start_y - ((s.flair_float_distance or 32) * eased))
            self.flair:size(math.max(1, math.floor(self.flair_base_size - ((s.flair_shrink_size or 0) * t))))
            set_alpha(self.flair, math.floor(self.flair_fade_start_alpha * (1 - t)))
            self.flair:show()
            self:position_flair(y)
        end
    end

    -- WHIFF shake
    if self.whiff_shaking then
        local t = (now - self.whiff_shake_start) / math.max(s.whiff_shake_duration, 0.01)
        if t >= 1 then
            self.whiff_shaking = false
            self:update_display()
        else
            local offset = math.floor(math.sin(t * 70) * s.whiff_shake_strength * (1 - t))
            self.dmg:pos(math.floor(self:banner_x() - (extents(self.dmg) / 2)) + offset, self:banner_y() + s.line_gap)
        end
    end

    -- Pop
    if self.pop_active then
        local t = (now - self.pop_start) / math.max(s.pop_duration, 0.01)
        if t >= 1 then
            self.pop_active = false
            self.dmg:size(s.dmg_size)
        else
            local eased = 1 - ((1 - t) * (1 - t))
            self.dmg:size(math.floor((s.dmg_size + s.pop_bonus_size) - (s.pop_bonus_size * eased)))
        end
        self:update_display()
    end

    if not s.fade_enabled and not self.fade_out_override then return end

    if self.fade_state == 'damage_fade_in' then
        local t = (now - self.fade_start) / math.max(s.fade_in_duration, 0.01)
        for _, n in ipairs({'ws', 'avg', 'avg_label', 'avg_value', 'avg_trend'}) do set_alpha(self[n], 255) end
        if t >= 1 then
            self.fade_state = 'visible'
            set_alpha(self.dmg, 255)
        else
            set_alpha(self.dmg, math.max(1, math.floor(255 * t)))
        end
    elseif self.fade_state == 'visible' then
        if self.last_ws_time > 0 and (now - self.last_ws_time) >= s.hold_duration then
            self.fade_state = 'fade_out'
            self.fade_start = now
        end
    elseif self.fade_state == 'fade_out' then
        local t = (now - self.fade_start) / math.max(self.fade_out_override or s.fade_out_duration, 0.01)
        if t >= 1 then
            self.fade_state = 'hidden'
            self:apply_alpha(0)
        else
            self:apply_alpha(255 * (1 - t))
        end
    end
end

-- killfade: the mob the banner's WS hit is dead (or gone). Fade the banner
-- out over `duration` seconds now instead of waiting for the hold timer.
-- Works with fade off too (the banner would otherwise stay up for good).
function Hud:kill_fade(duration)
    self.banner_target = nil
    if self.moving or not self:banner_visible() or self.fade_state == 'fade_out' and self.fade_out_override then
        return false
    end
    local a = self.alpha_current
    self.fade_state = 'fade_out'
    self.fade_out_override = math.max(tonumber(duration) or 1, 0.01)
    -- start from the current alpha so a fade-in in progress doesn't jump
    self.fade_start = self.clock() - (1 - a / 255) * self.fade_out_override
    if self.pop_active then
        self.pop_active = false
        self.dmg:size(self.settings.dmg_size)
    end
    set_alpha(self.dmg, a)
    return true
end

---------------------------------------------------------------------------
-- Move (drag) mode: //cw move
---------------------------------------------------------------------------

-- Draggable parts, in hit-test priority order (small / on-top first).
-- Dragging changes the part's two settings by the mouse delta. Every part
-- is placed from the HUD centre (center_x / center_y) on its own, so
-- dragging one never moves another. //cw pos moves the whole HUD.
-- color: the highlight box and name tag colour shown in move mode.
M.PARTS = {
    {name = 'mb',         label = 'MB popup',      color = {255, 80, 200},  objs = {'mb'}, x = 'mb_offset_x', y = 'mb_offset_y'},
    {name = 'party',      label = 'Party panel',   color = {0, 170, 90},    objs = {'party'}, x = 'party_panel_offset_x', y = 'party_panel_offset_y'},
    {name = 'sc_bar',     label = 'Skillchain',    color = {60, 120, 255},  objs = {'sc_bar', 'sc_bar_label', 'sc_bar_status', 'sc_chain_counter', 'sc_detail'}, x = 'sc_bar_offset_x', y = 'sc_bar_gap'},
    {name = 'banner',     label = 'Banner',        color = {230, 60, 60},   objs = {'ws', 'dmg', 'avg_label', 'avg_value', 'avg_trend', 'flair', 'sc'}, x = 'banner_offset_x', y = 'banner_offset_y'},
}

local TAG_SIZE = 10

local SAMPLE_PARTY = tconcat({
    ('%-12s %4s %8s %8s'):format('Party WS', '#', 'Avg', 'Peak'),
    ('%-12s %4d %8s %8s'):format('Velner', 12, '48,210', '99,999'),
    ('%-12s %4d %8s %8s'):format('Partymember', 9, '31,402', '62,118'),
    ('%-12s %4d %8s %8s'):format('Ifrit', 4, '12,950', '18,330'),
}, '\n')

local SAMPLE_CLOSERS = tconcat({
    ('%-16s → Lv.%d %-14s'):format('Torcleaver', 4, 'Radiance'),
    ('%-16s → Lv.%d %-14s'):format('Upheaval', 3, 'Light'),
    ('%-16s → Lv.%d %-14s'):format('Savage Blade', 2, 'Distortion'),
}, '\n')

-- Party panel visibility:
--   * //cw hide hides it until //cw show or your next WS
--   * //cw move and //cw testparty show sample rows, data or not
--   * otherwise it needs party_panel on AND at least one recorded row; it
--     then stays up, or follows the banner fade with party_panel_fade on.
function Hud:party_testing()
    return self.party_test_until ~= nil and self.clock() < self.party_test_until
end

function Hud:start_party_test(seconds)
    self.party_test_until = self.clock() + (seconds or 10)
    self:update_party()
end

function Hud:party_visible()
    if self.manual_hidden then return false end
    if self:party_testing() then return true end
    if self.moving then return self.settings.party_panel == true end
    if not self:party_enabled() then return false end
    if self.settings.party_panel_fade then return self:banner_visible() end
    return true
end

function Hud:update_party()
    local o = self.party
    local sample = self.moving or self:party_testing()
    local text = sample and SAMPLE_PARTY or self.party_lines
    if not self:party_visible() or not text or text == '' then
        o:hide()
        return
    end
    if self.party_shown_text ~= text then
        o:text(text)
        self.party_shown_text = text
    end
    self:position_party()
    local fade = self.settings.party_panel_fade and not sample
    set_alpha(o, fade and self.alpha_current or 255)
    o:show()
end

function Hud:update(now)
    self:pump_ws_queue(now)
    self:update_frame(now)
    self:update_party()
end

-- Move mode highlight: a tinted box behind every object of a part (brighter
-- under the mouse) and a name tag just above the part's first object.
local function set_bg(o, on, color, alpha)
    if on then
        o:bg_color(color[1], color[2], color[3])
        o:bg_alpha(alpha)
        o:bg_visible(true)
    else
        o:bg_visible(false)
        o:bg_alpha(0)
    end
end

function Hud:highlight_parts(on)
    local s = self.settings
    for _, part in ipairs(M.PARTS) do
        local tag = self.by_name['tag_' .. part.name]
        tag:bg_visible(false)
        tag:hide()
    end
    if not on then
        for _, part in ipairs(M.PARTS) do
            for _, n in ipairs(part.objs) do set_bg(self.by_name[n], false) end
        end
    end
    for _, part in ipairs(self:parts()) do
        local hovered = self.hover == part.name or (self.drag and self.drag.part.name == part.name)
        for _, n in ipairs(part.objs) do
            set_bg(self.by_name[n], on, part.color, hovered and 170 or 80)
        end
        local tag = self.by_name['tag_' .. part.name]
        if on and self:part_enabled(part) then
            local first = self.by_name[part.objs[1]]
            local x, y = first:pos()
            tag:text(' ' .. part.label .. ' ')
            tag:font('Consolas')
            tag:size(TAG_SIZE)
            tag:color(255, 255, 255)
            tag:stroke_width(1)
            set_bg(tag, true, part.color, 230)
            local _, th = tag:extents()
            tag:pos(math.floor(x), math.max(0, math.floor(y - (tonumber(th) or 14) - 1)))
            set_alpha(tag, 255)
            tag:show()
        else
            set_bg(tag, false)
            tag:hide()
        end
    end
end

-- Names of the parts currently draggable, top of the HUD first.
function Hud:legend()
    local names = {}
    local parts = self:parts()
    for i = #parts, 1, -1 do
        local part = parts[i]
        if self:part_enabled(part) then
            names[#names + 1] = (part.label:gsub(' %(.*%)', ''))
        end
    end
    return tconcat(names, ', ')
end

function Hud:move_view()
    return {
        target_id = 'move', phase = 'go',
        wait_remaining = 0, wait_total = 3, remaining = 4.2, window_total = 6,
        step = 3, chain = 2, sc_name = 'Light', name = 'Torcleaver',
        props = 'Light', elements = '(Fire,Wind,Lightning,Light)',
        closers = SAMPLE_CLOSERS,
        show_timer = self:part_shown('timer'), show_step = self:part_shown('step'),
        show_props = self:part_shown('props'), show_burst = self:part_shown('burst'),
    }
end

-- Per-job SC part switches for sample views (//cw testbar, move mode).
-- CrankWatch.lua sets hud.show_part to the engine's check for the current
-- job; without it (tests, early load) everything shows.
function Hud:part_shown(key)
    if self.show_part then return self.show_part(key) and true or false end
    return true
end

function Hud:start_move()
    if self.moving then return end
    local b = self.banner
    self.saved_banner = {label = b.label, dmg = b.dmg, avg = b.avg, avg_raw = b.avg_raw, trend = b.trend,
        trend_color = b.trend_color, raw = b.raw, cranked = b.cranked, whiff = self.is_whiff}
    self.moving = true
    self.drag = nil
    self.manual_hidden = false
    self.test_bar = nil
    self.is_whiff, self.whiff_shaking, self.pop_active = false, false, false
    b.label, b.dmg, b.raw = 'Last WS: Savage Blade!', '54,321', 54321
    b.avg, b.avg_raw, b.trend, b.trend_color = '43,210', 43210, '↑', {80, 255, 80}
    self.fade_state, self.alpha_current = 'visible', 255

    local s = self.settings
    self.dmg:size(s.dmg_size)
    self:apply_avg_style(b.avg_raw)
    self.dmg:color(255, 215, 0)
    self.flair:text('BIG HIT!'); self.flair:size(s.flair_size); self.flair:color(255, 255, 255)
    self.sc:text('SC Bonus: 12,345!!'); self.sc:size(s.sc_size or s.flair_size); self.sc:color(120, 255, 255)
    self.mb_lines = {'MB: 40,000!!', 'Mage MB: 35,120!!'}
    self.mb:text(tconcat(self.mb_lines, '\n')); self.mb:size(s.mb_size or 18); self.mb:color(255, 140, 255)
    self:render_sc(self:move_view())
    self:render_move()
end

-- Draw every part at its resting position, fully visible, every frame.
function Hud:render_move()
    local s = self.settings
    self:render_sc(self:move_view())
    self.sc_bar_shake_start, self.mb_shake_start = 0, 0
    self:update_display()
    self:position_flair(self:banner_y() + s.flair_gap)
    self:position_sc_line(self:sc_start())
    self:position_mb()
    self:position_party()
    for _, part in ipairs(self:parts()) do
        for _, n in ipairs(part.objs) do
            local o = self.by_name[n]
            if not self:part_enabled(part) or not self:obj_enabled(n) then
                o:hide()
            else
                set_alpha(o, 255)
                o:show()
            end
        end
    end
    self.avg:hide()
    self:highlight_parts(true)
end

function Hud:stop_move()
    if not self.moving then return end
    self.moving = false
    self.drag = nil
    self.hover = nil
    self:highlight_parts(false)
    local saved = self.saved_banner or {}
    local b = self.banner
    for _, k in ipairs({'label', 'dmg', 'avg', 'avg_raw', 'trend', 'trend_color', 'raw', 'cranked'}) do
        if saved[k] ~= nil then b[k] = saved[k] end
    end
    self.is_whiff = saved.whiff or false
    self.flair_visible, self.flair_fading = false, false
    self.sc_visible, self.sc_fading = false, false
    self.mb_visible, self.mb_lines = false, {}
    self:hide_sc_group()
    self:apply_damage_style()
    self:apply_avg_style(b.avg_raw)
    self.fade_state = 'hidden'
    self:apply_alpha(0)
    for _, o in ipairs(self.registry) do o:hide() end
    self:update_party()
end

local function hit(o, x, y)
    if not o:visible() then return false end
    local px, py = o:pos()
    local w, h = o:extents()
    w, h = tonumber(w) or 0, tonumber(h) or 0
    return x >= px and x <= px + w and y >= py and y <= py + h
end

-- Name tags win: where parts overlap, grabbing a part by its tag always
-- picks the right one. Otherwise the topmost part body under the mouse.
function Hud:part_at(x, y)
    for _, part in ipairs(self:parts()) do
        if self:part_enabled(part) and hit(self.by_name['tag_' .. part.name], x, y) then
            return part
        end
    end
    for _, part in ipairs(self:parts()) do
        for _, n in ipairs(part.objs) do
            if hit(self.by_name[n], x, y) then return part end
        end
    end
end

-- Windower mouse event. Returns blocked (true keeps the click away from
-- the game) and, on release, the part that was dropped.
-- type: 0 move, 1 left down, 2 left up.
function Hud:mouse(type, x, y)
    if not self.moving then return false end
    local s = self.settings
    if type == 1 then
        local part = self:part_at(x, y)
        if not part then return false end
        local sx, sy = s[part.x] or 0, s[part.y] or 0
        -- Closer list and party panel can be auto-flipped to stay on screen;
        -- start the drag from where they are actually drawn.
        if part.name == 'sc_bar' then
            -- start from where the block is drawn (it may be flipped)
            sy = (self.block_top or (s.center_y + sy)) - s.center_y
        elseif part.name == 'party' then
            local px, py = self.party:pos()
            sx, sy = px - s.center_x, py - s.center_y
        end
        s[part.x], s[part.y] = sx, sy
        self.drag = {part = part, mx = x, my = y, sx = sx, sy = sy}
        return true
    elseif type == 0 and not self.drag then
        local part = self:part_at(x, y)
        self.hover = part and part.name or nil
        return false
    elseif type == 0 and self.drag then
        local d = self.drag
        s[d.part.x] = math.floor(d.sx + (x - d.mx))
        s[d.part.y] = math.floor(d.sy + (y - d.my))
        self:render_move()
        return true
    elseif type == 2 and self.drag then
        local part = self.drag.part
        self.drag = nil
        self:render_move()
        return true, part
    end
    return false
end

---------------------------------------------------------------------------
-- Commands support
---------------------------------------------------------------------------

function Hud:force_visible()
    self.manual_hidden = false
    self.fade_state = 'visible'
    self.alpha_current = 255
    self.last_ws_time = self.clock()
    self:apply_alpha(255)
    self:update_display()
    self:request_layout_refresh(0.45)
end

-- //cw hide: hides every object, including chain info and MB.
-- Stays hidden (SC HUD included) until //cw show or your next banner WS.
function Hud:hide_all()
    self.manual_hidden = true
    self.ws_queue = {}
    for _, o in ipairs(self.registry) do o:hide() end
    self.fade_state = 'hidden'
    self.alpha_current = 0
    self.sc_bar_active = false
    self.chain_counter_visible = false
    self.mb_visible = false
    self.sc_visible, self.sc_fading = false, false
    self.flair_visible, self.flair_fading = false, false
    self.test_bar = nil
end

function Hud:apply_all_visual_settings()
    local s = self.settings
    local font = s.font
    for _, o in ipairs(self.registry) do o:font(font) end
    self.avg_trend:font('Consolas')
    self.sc_bar:font(s.sc_bar_font or 'Consolas')
    self.sc_detail:font(s.sc_detail_font or 'Consolas')
    self.party:font(s.party_panel_font or 'Consolas')
    for _, part in ipairs(self:parts()) do
        local tag = self.by_name['tag_' .. part.name]
        tag:font('Consolas'); tag:size(TAG_SIZE)
    end

    local sizes = {
        ws = s.ws_size, dmg = s.dmg_size, avg = s.avg_size, avg_label = s.avg_size,
        avg_value = s.avg_size, avg_trend = s.avg_size, sc = s.sc_size or s.flair_size,
        sc_bar = s.sc_bar_size or s.avg_size, sc_bar_label = s.sc_bar_label_size or 15,
        sc_bar_status = s.sc_bar_label_size or 15, sc_chain_counter = s.sc_chain_counter_size or 18,
        sc_detail = s.sc_detail_size or 13,
        mb = s.mb_size or 22, flair = s.flair_size, party = s.party_panel_size or 13,
    }
    for name, size in pairs(sizes) do self.by_name[name]:size(size) end

    local thin = math.max(1, (s.stroke_width or 4) - 2)
    for _, o in ipairs(self.registry) do o:stroke_width(s.stroke_width) end
    self.sc_detail:stroke_width(thin)
    self.party:stroke_width(thin)

    self.ws:color(255, 255, 255)
    self.avg:color(255, 255, 255)
    self.avg_label:color(255, 255, 255)
    self.sc:color(120, 255, 255)
    self.sc_bar:color(80, 255, 120)
    self.sc_bar_label:color(255, 255, 255)
    self.sc_bar_status:color(80, 255, 80)
    self.sc_chain_counter:color(255, 255, 255)
    self.sc_detail:color(255, 255, 255)
    self.party:color(255, 255, 255)
    self:apply_trend_style()
    self:apply_avg_style(self.banner.avg_raw)
    self:apply_damage_style()
    self:update_display()
    self:request_layout_refresh(0.45)
end

function Hud:destroy()
    for _, o in ipairs(self.registry) do
        pcall(o.destroy, o)
    end
    self.registry = {}
end

return M
