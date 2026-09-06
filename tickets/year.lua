-- year.lua - 年票渲染（移植自补丁 paintReadingYear）

local BB = require("ffi/blitbuffer")
local rl = require("lib.rl_reference")

local function render(bb, x, y, w, h, ref_date)
    ref_date = ref_date or os.time()
    local year = os.date("*t", ref_date).year
    local year_start = os.time({ year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
    local year_end = os.time({ year = year + 1, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
    local rows, ok = rl.readReadingData(year_start, year_end)
    local agg = rl.rlAggregate(rows)

    local p = rl.rlReferencePainter(bb, y, h)
    local stats_hit_books = {}
    local stats_hit_records = {}
    rl.rlReferenceFrame(bb, p, { left = false, right = false, radius = 36 })

    p.T("阅读线路 · READING LINE · 年度联票", 58, 50, 12, true, 570, BB.COLOR_DARK_GRAY)
    p.T("YEAR PASS", 58, 82, 48, true, 600, BB.COLOR_BLACK)
    p.T(string.format("%04d · 十二个月阅读", year), 58, 162, 12, false, 560, BB.COLOR_DARK_GRAY)
    p.L(790, 30, 790, 190, BB.COLOR_DARK_GRAY, 1)
    p.CT("有效期 · VALID", 810, 56, 138, 10, false, BB.COLOR_DARK_GRAY)
    p.CT("01.01", 810, 92, 138, 18, true, BB.COLOR_BLACK)
    p.L(878, 132, 878, 150, BB.COLOR_DARK_GRAY, 1)
    p.CT("12.31", 810, 158, 138, 18, true, BB.COLOR_BLACK)
    p.DL(53, 194, 952, 194, BB.COLOR_DARK_GRAY, 1)

    -- 年度概览：12个月热力图
    local month_data, max_seconds = {}, 0
    for month = 1, 12 do
        local from = os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
        local to = os.time({ year = year, month = month + 1, day = 1, hour = 0, min = 0, sec = 0 })
        local month_rows, days, books = {}, {}, {}
        for _, row in ipairs(rows) do
            if row.time >= from and row.time < to then
                month_rows[#month_rows + 1] = row
                days[os.date("%Y-%m-%d", row.time)] = true
                books[row.title] = true
            end
        end
        local month_agg = rl.rlAggregate(month_rows)
        local day_count, book_count = 0, 0
        for _ in pairs(days) do day_count = day_count + 1 end
        for _ in pairs(books) do book_count = book_count + 1 end
        month_data[month] = { seconds = month_agg.seconds, days = day_count, books = book_count, finished = rl.rlFinishedCount(month_rows) }
        max_seconds = math.max(max_seconds, month_agg.seconds)
    end

    local month_names = { "一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月" }
    local now = os.date("*t")
    local cell_w, cell_h, gap_x, gap_y = 286, 126, 12, 11
    for month = 1, 12 do
        local data = month_data[month]
        local index = month - 1
        local cx = 54 + (index % 3) * (cell_w + gap_x)
        local cy = 207 + math.floor(index / 3) * (cell_h + gap_y)
        local current_month = now.year == year and now.month == month
        local future = year > now.year or (year == now.year and month > now.month)
        local ink = future and BB.COLOR_GRAY_B or BB.COLOR_BLACK
        p.R(cx, cy, cell_w, cell_h, current_month and BB.COLOR_GRAY_E or BB.COLOR_WHITE)
        p.L(cx, cy, cx + cell_w, cy, BB.COLOR_DARK_GRAY, 1)
        p.L(cx, cy + cell_h, cx + cell_w, cy + cell_h, BB.COLOR_DARK_GRAY, 1)
        p.L(cx, cy, cx, cy + cell_h, BB.COLOR_GRAY_B, 1)
        p.L(cx + cell_w, cy, cx + cell_w, cy + cell_h, BB.COLOR_GRAY_B, 1)
        p.T(string.format("%02d", month), cx + 12, cy + 9, 20, true, 45, ink)
        p.T(month_names[month], cx + 61, cy + 13, 10, true, 65, ink)
        local intensity = max_seconds > 0 and data.seconds / max_seconds or 0
        local blocks = math.ceil(intensity * 8)
        for i = 1, 8 do
            local shade = i <= blocks and (intensity > .66 and BB.COLOR_GRAY_4 or intensity > .33 and BB.COLOR_DARK_GRAY or BB.COLOR_GRAY_B) or BB.COLOR_GRAY_E
            p.R(cx + 13 + (i - 1) * 23, cy + 49, 18, 11, shade)
        end
        p.DL(cx + 10, cy + 67, cx + cell_w - 10, cy + 67, BB.COLOR_GRAY_B, 1)
        p.T(tostring(data.days) .. " 天", cx + 13, cy + 75, 9, false, 76, ink)
        p.T(rl.rlTime(data.seconds), cx + 101, cy + 75, 10, true, 84, ink)
        p.T(tostring(data.books) .. " 本", cx + 13, cy + 98, 9, false, 90, ink)
        p.T(tostring(data.finished) .. " 读完", cx + 101, cy + 98, 9, false, 104, ink)
        for i = 1, math.min(6, data.finished) do
            p.Circle(cx + cell_w - 18, cy + 18 + (i - 1) * 17, 4, future and BB.COLOR_GRAY_B or BB.COLOR_DARK_GRAY)
        end
    end

    p.L(53, 789, 952, 789, BB.COLOR_DARK_GRAY, 1)
    local summary = {
        { "READING TIME", "阅读时长", rl.rlTime(agg.seconds), "19-vintage-timetable.svg" },
        { "ACTIVE DAYS", "阅读天数", tostring((function() local n = 0; for _ in pairs(agg.days) do n = n + 1 end; return n end)()) .. " 天", "18-vintage-ticket.svg" },
        { "FINISHED", "读完数量", tostring(rl.rlFinishedCount(rows)) .. " 读完", "20-leather-luggage.svg" },
        { "WORDS READ", "累计字数", rl.rlFormatWords(agg.words), "14-station-signboard.svg" },
    }
    rl.rlReferenceMetrics(bb, p, summary, 789, 910)
    p.L(53, 910, 952, 910, BB.COLOR_GRAY_B, 1)
    rl.rlReferenceFooter(bb, p, "Y" .. tostring(year), "阅读线路 · Y" .. tostring(year) .. "-001-READING-LINE", true)
end

return { render = render }
