-- screen.lua - 阅读屏保票渲染（移植自补丁 paintReadingScreen）

local BB = require("ffi/blitbuffer")
local rl = require("lib.rl_reference")

local function render(bb, x, y, w, h, ref_date)
    local now = os.date("*t")
    local month_start = os.time({ year = now.year, month = now.month, day = 1, hour = 0, min = 0, sec = 0 })
    local next_month_start = os.time({ year = now.year, month = now.month + 1, day = 1, hour = 0, min = 0, sec = 0 })
    local rows, ok = rl.readReadingData(month_start, next_month_start)
    local latest = rows[#rows]
    if not latest then
        local all_rows = rl.readReadingDataAll()
        latest = all_rows[#all_rows]
    end
    local month = string.format("%04d.%02d", now.year, now.month)
    local show_title = true

    local p = rl.rlReferencePainter(bb, y, h)
    local stats_hit_books = {}
    local stats_hit_records = {}
    p.R(12, 8, 982, 1070, BB.COLOR_BLACK)
    p.R(18, 14, 970, 1064, BB.COLOR_GRAY_E)
    p.R(42, 38, 922, 1012, BB.COLOR_WHITE)
    p.L(18, 14, 18, 1078, BB.COLOR_BLACK, 2)
    p.L(988, 14, 988, 1078, BB.COLOR_BLACK, 2)
    p.L(18, 1078, 988, 1078, BB.COLOR_BLACK, 2)
    rl.rlPaintTicketNotches(bb, p.X(18), p.Y(14), p.X(988) - p.X(18), p.Y(1078) - p.Y(14),
        math.max(8, math.floor(14 * p.s)), BB.COLOR_GRAY_E, { stamp = true })

    local title_text = "READING SCREEN"
    local title_width, title_font = p.M(title_text, 46, BB.COLOR_BLACK)
    local title_center = p.X(503)
    local title_left = title_center - math.floor(title_width / 2)
    p.T("READING LINE", 503 - title_width / (2 * p.s), 82, 12, false, nil, BB.COLOR_DARK_GRAY)
    local number_text = "NO. WT" .. string.format("%04d-%02d", now.year, now.month)
    local number_width = p.M(number_text, 12, BB.COLOR_DARK_GRAY)
    p.T(number_text, 503 + title_width / (2 * p.s) - number_width / p.s, 82, 12, false, nil, BB.COLOR_DARK_GRAY)
    rl.drawText(bb, title_text, title_left, p.Y(111), title_font, true, nil, BB.COLOR_BLACK)
    p.CT("阅读车票", 303, 196, 400, 18, true, BB.COLOR_BLACK)
    p.T(latest and (show_title and ("当前阅读 · 《" .. latest.title .. "》") or "当前阅读 · 隐私模式") or "当前没有阅读记录",
        112, 233, 15, true, 760, BB.COLOR_BLACK)

    local screen_agg = rl.rlAggregate(rows)
    local stops, seen = {}, {}
    for i = #rows, 1, -1 do
        local row = rows[i]
        if not seen[row.id] then
            seen[row.id] = true
            stops[#stops + 1] = row
            if #stops >= 5 then break end
        end
    end
    local first_date = rows[1] and rl.rlDate(rows[1].time):sub(6) or string.format("%02d.01", now.month)
    local current_date = string.format("%02d.%02d", now.month, now.day)
    local last_day = tonumber(os.date("%d", os.time({ year = now.year, month = now.month + 1, day = 0 }))) or 30

    p.R(112, 310, 190, 372, BB.COLOR_WHITE)
    p.L(112, 310, 302, 310, BB.COLOR_DARK_GRAY, 1)
    p.L(112, 434, 302, 434, BB.COLOR_GRAY_B, 1)
    p.L(112, 558, 302, 558, BB.COLOR_GRAY_B, 1)
    p.L(112, 682, 302, 682, BB.COLOR_DARK_GRAY, 1)
    p.L(112, 310, 112, 682, BB.COLOR_GRAY_B, 1)
    p.L(302, 310, 302, 682, BB.COLOR_GRAY_B, 1)
    p.T("出发 · DEPART", 130, 334, 9, false, 150, BB.COLOR_DARK_GRAY)
    p.T(first_date, 130, 369, 22, true, 150, BB.COLOR_BLACK)
    p.T("当前 · CURRENT", 130, 458, 9, false, 150, BB.COLOR_DARK_GRAY)
    p.T(current_date, 130, 493, 22, true, 150, BB.COLOR_BLACK)
    p.T("终点 · DESTINATION", 130, 582, 9, false, 150, BB.COLOR_DARK_GRAY)
    p.T(string.format("%02d.%02d", now.month, last_day), 130, 617, 22, true, 150, BB.COLOR_BLACK)

    local route_top, route_bottom, route_x = 310, 685, 420
    if #stops > 0 then
        p.L(route_x, route_top, route_x, route_bottom, BB.COLOR_BLACK, 2)
        for i, row in ipairs(stops) do
            local cy = route_top + math.floor((i - 1) * (route_bottom - route_top) / math.max(1, #stops - 1))
            p.Circle(route_x, cy, i == 1 and 11 or 8, i == 1 and BB.COLOR_BLACK or BB.COLOR_WHITE)
            if i ~= 1 then p.Circle(route_x, cy, 4, BB.COLOR_DARK_GRAY) end
            local label = (show_title and ("《" .. row.title .. "》") or "隐私阅读节点")
            p.T(label, route_x + 32, cy - 13, 13, true, 430, BB.COLOR_BLACK)
            p.T((show_title and ("第 " .. tostring(row.display_page or row.page or 0) .. " 页") or "阅读节点") .. " · " .. rl.rlTime(row.duration),
                route_x + 32, cy + 12, 9, false, 430, BB.COLOR_DARK_GRAY)
        end
    else
        p.T("本月尚无阅读路线", 460, 460, 14, false, 360, BB.COLOR_DARK_GRAY)
    end

    p.DL(106, 208, 410, 208, BB.COLOR_DARK_GRAY, 1)
    p.DL(595, 208, 900, 208, BB.COLOR_DARK_GRAY, 1)
    p.DL(53, 789, 952, 789, BB.COLOR_DARK_GRAY, 1)
    local active_days = 0
    for _ in pairs(screen_agg.days) do active_days = active_days + 1 end
    local summary = {
        { "READING TIME", "阅读时长", rl.rlTime(screen_agg.seconds), "19-vintage-timetable.svg" },
        { "PAGES READ", "阅读页数", tostring(screen_agg.pages) .. " 页", "18-vintage-ticket.svg" },
        { "BOOKS", "阅读书籍", tostring((function() local n = 0; for _ in pairs(screen_agg.books) do n = n + 1 end; return n end)()) .. " 本", "20-leather-luggage.svg" },
        { "ACTIVE DAYS", "阅读天数", tostring(active_days) .. " 天", "14-station-signboard.svg" },
    }
    rl.rlReferenceMetrics(bb, p, summary, 789, 910)
    p.L(53, 910, 952, 910, BB.COLOR_GRAY_B, 1)
    rl.rlReferenceFooter(bb, p, "S" .. month, "KEEP READING, KEEP GOING.", true)
end

return { render = render }
