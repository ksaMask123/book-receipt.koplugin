-- week.lua - 周票渲染（移植自补丁 paintReadingWeek）

local BB = require("ffi/blitbuffer")
local rl = require("lib.rl_reference")

local function render(bb, x, y, w, h, ref_date)
    ref_date = ref_date or os.time()
    local base = rl.rlDayStart(ref_date)
    local monday = rl.rlWeekStart(ref_date)
    local rows, ok = rl.readReadingData(monday, monday + 7 * 86400)
    local p = rl.rlReferencePainter(bb, y, h)
    local stats_hit_books = {}
    local stats_hit_records = {}
    rl.rlReferenceFrame(bb, p, { top = false, bottom = false, radius = 36 })

    local week_no = tonumber(os.date("%V", monday)) or 1
    local _, _, gate_index = rl.rlWeekday(base)
    local gate = string.format("%02dA", gate_index)
    p.T("阅读周票 · READING WEEK PASS", 58, 55, 12, true, 560, BB.COLOR_DARK_GRAY)
    p.T("WEEK TICKET", 58, 86, 48, true, 690, BB.COLOR_BLACK)
    p.T("七日阅读路线 / SEVEN DAY LINE", 58, 164, 12, false, 560, BB.COLOR_DARK_GRAY)
    p.DL(790, 30, 790, 258, BB.COLOR_DARK_GRAY, 1)

    local gate_width = p.M(gate, 28, BB.COLOR_BLACK)
    local a_width = p.M("A", 28, BB.COLOR_BLACK)
    local gate_right = p.X(796) + math.floor((130 * p.s + gate_width) / 2) + a_width

    local function RT(text, top, size, bold, color)
        local actual, fitted = p.M(text, size, color)
        rl.drawText(bb, tostring(text or ""), gate_right - actual, p.Y(top), fitted, bold, nil, color)
    end

    RT("NO. WT" .. os.date("%Y", monday) .. "-" .. string.format("%02d", week_no), 48, 10, false, BB.COLOR_DARK_GRAY)
    RT("检票口 · GATE", 75, 8, false, BB.COLOR_DARK_GRAY)
    RT(gate, 94, 28, true, BB.COLOR_BLACK)
    p.DL(795, 143, 952, 143, BB.COLOR_GRAY_B, 1)
    RT("▼", 146, 10, true, BB.COLOR_BLACK)
    RT("7 DAYS", 169, 10, false, BB.COLOR_BLACK)
    RT("WEEK PASS", 191, 10, false, BB.COLOR_DARK_GRAY)
    p.DL(53, 190, 760, 190, BB.COLOR_GRAY_B, 1)
    p.T("周次 · WEEK", 58, 206, 8, false, 120, BB.COLOR_DARK_GRAY)
    p.T("W" .. string.format("%02d", week_no), 58, 228, 16, true, 120, BB.COLOR_BLACK)
    p.L(205, 202, 205, 254, BB.COLOR_GRAY_B, 1)
    p.T("起止日期 · VALID", 236, 206, 8, false, 170, BB.COLOR_DARK_GRAY)
    p.T(rl.rlDate(monday) .. " — " .. rl.rlDate(monday + 6 * 86400), 236, 228, 15, true, 350, BB.COLOR_BLACK)
    p.L(625, 202, 625, 254, BB.COLOR_GRAY_B, 1)
    p.T("有效期 · VALID", 655, 206, 8, false, 100, BB.COLOR_DARK_GRAY)
    p.T("7 DAYS", 655, 228, 15, true, 100, BB.COLOR_BLACK)
    p.DL(53, 270, 952, 270, BB.COLOR_DARK_GRAY, 1)

    -- 周日历区域
    local line_y = 386
    p.L(68, line_y, 938, line_y, BB.COLOR_BLACK, 3)
    local total_seconds, active_days = 0, 0
    for d = 0, 6 do
        local day_start = monday + d * 86400
        local day_rows = {}
        for _, row in ipairs(rows) do
            if row.time >= day_start and row.time < day_start + 86400 then
                day_rows[#day_rows + 1] = row
            end
        end
        local agg = rl.rlAggregate(day_rows)
        total_seconds = total_seconds + agg.seconds
        if agg.sessions > 0 then active_days = active_days + 1 end
        local cx = 113 + d * 128
        local is_today = rl.rlDayStart(os.time()) == day_start
        p.CT(rl.rlWeekday(day_start), cx - 55, 307, 110, 10, true, BB.COLOR_BLACK)
        p.CT(rl.rlDate(day_start):sub(6), cx - 55, 328, 110, 9, false, BB.COLOR_DARK_GRAY)
        p.CT(rl.rlTime(agg.seconds), cx - 55, 347, 110, 10, true, BB.COLOR_BLACK)
        p.Circle(cx, line_y, is_today and 11 or 9, is_today and BB.COLOR_BLACK or BB.COLOR_WHITE)
        if not is_today then p.Circle(cx, line_y, 5, BB.COLOR_DARK_GRAY) end
        local branch_y, seen, book_count = line_y + 18, {}, 0
        for _, row in ipairs(rl.rlBoardings(day_rows)) do
            if not seen[row.id] and book_count < 3 then
                seen[row.id] = true
                book_count = book_count + 1
                p.L(cx, branch_y, cx, branch_y + 25, BB.COLOR_DARK_GRAY, 1)
                p.CT("《" .. rl.rlEllipsize(row.title, 8) .. "》", cx - 60, branch_y + 31, 120, 9, true, BB.COLOR_BLACK)
                p.CT("第 " .. tostring(row.first_page or 0) .. " 页", cx - 60, branch_y + 50, 120, 8, false, BB.COLOR_DARK_GRAY)
                branch_y = branch_y + 78
            end
        end
    end

    p.L(53, 736, 952, 736, BB.COLOR_DARK_GRAY, 1)
    p.T("本周", 58, 750, 16, true, 100, BB.COLOR_BLACK)
    p.T("WEEKLY", 120, 755, 9, false, 100, BB.COLOR_DARK_GRAY)
    p.L(53, 789, 952, 789, BB.COLOR_GRAY_B, 1)

    local week_agg = rl.rlAggregate(rows)
    local summary = {
        { "READING TIME", "阅读时长", rl.rlTime(total_seconds), "19-vintage-timetable.svg" },
        { "ACTIVE DAYS", "阅读天数", tostring(active_days) .. " 天", "18-vintage-ticket.svg" },
        { "FINISHED", "读完数量", tostring(rl.rlFinishedCount(rows)) .. " 读完", "20-leather-luggage.svg" },
        { "PAGES READ", "阅读页数", tostring(week_agg.pages) .. " 页", "14-station-signboard.svg" },
    }
    rl.rlReferenceMetrics(bb, p, summary, 789, 910)
    p.L(53, 910, 952, 910, BB.COLOR_GRAY_B, 1)
    rl.rlReferenceFooter(bb, p, "W" .. tostring(monday), "保持阅读 · KEEP READING · WEEK " .. string.format("%02d", week_no), true)

    if not ok then
        p.T("统计库暂不可用", 300, 690, 12, false, 400, BB.COLOR_DARK_GRAY)
    end
end

return { render = render }
