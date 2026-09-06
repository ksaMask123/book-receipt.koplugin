-- month.lua - 月票渲染（对齐源插件 paintReadingMonth）

local BB = require("ffi/blitbuffer")
local rl = require("lib.rl_reference")

local function render(bb, x, y, w, h, ref_date)
    ref_date = ref_date or os.time()
    local current = os.date("*t", ref_date)
    local month_start = os.time({ year = current.year, month = current.month, day = 1, hour = 0, min = 0, sec = 0 })
    local days_in_month = tonumber(os.date("%d", os.time({ year = current.year, month = current.month + 1, day = 0 }))) or 30
    local next_month_start = os.time({ year = current.year, month = current.month + 1, day = 1, hour = 0, min = 0, sec = 0 })

    local rows, ok = rl.readReadingData(month_start, next_month_start)
    local agg = rl.rlAggregate(rows)
    local active_days = 0
    for _ in pairs(agg.days) do active_days = active_days + 1 end

    local p = rl.rlReferencePainter(bb, y, h)
    local stats_hit_books = {}
    local stats_hit_records = {}
    rl.rlReferenceFrame(bb, p, { left = false, right = false, radius = 36 })

    local month_names = { "一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月" }
    p.T("阅读线路 · READING LINE · 月度联票", 58, 50, 12, true, 500, BB.COLOR_DARK_GRAY)
    p.T("MONTH PASS", 58, 72, 48, true, 540, BB.COLOR_BLACK)
    p.T("NO. WT" .. string.format("%04d-%02d", current.year, current.month), 58, 141, 11, false, 250, BB.COLOR_DARK_GRAY)
    p.T(tostring(current.year), 690, 69, 20, true, 92, BB.COLOR_BLACK)
    p.T(month_names[current.month], 690, 105, 22, true, 94, BB.COLOR_BLACK)
    local now = os.date("*t")
    if now.year == current.year and now.month == current.month then
        p.T("CURRENT", 690, 43, 8, true, 86, BB.COLOR_DARK_GRAY)
    end
    p.DL(53, 188, 785, 188, BB.COLOR_DARK_GRAY, 1)
    p.DL(800, 30, 800, 770, BB.COLOR_DARK_GRAY, 1)

    -- 添加列车图标（源版有，移植版缺失）
    local train_size = math.max(84, math.floor(120 * p.ui_s))
    -- 注意：需要 rlMetricIcon，目前移植版未导出，跳过

    p.CT("有效期 · VALID", 813, 170, 132, 10, false, BB.COLOR_DARK_GRAY)
    p.CT(string.format("%02d.%02d", current.month, 1), 813, 205, 132, 20, true, BB.COLOR_BLACK)
    p.DL(878, 239, 878, 260, BB.COLOR_DARK_GRAY, 1)
    p.CT(string.format("%02d.%02d", current.month, days_in_month), 813, 266, 132, 20, true, BB.COLOR_BLACK)

    -- 日历网格（源版核心功能，移植版缺失）
    local gx, gy, grid_right, grid_bottom = 53, 213, 785, 754
    local cell_w, cell_h = (grid_right - gx) / 7, (grid_bottom - (gy + 30)) / 6

    -- 星期表头
    local weekdays = {"周一", "周二", "周三", "周四", "周五", "周六", "周日"}
    for col = 0, 6 do
        p.CT(weekdays[col+1], gx + col * cell_w, gy, cell_w, 10, true, BB.COLOR_BLACK)
    end
    p.L(gx, gy + 28, grid_right, gy + 28, BB.COLOR_DARK_GRAY, 1)

    -- 网格线
    for col = 0, 7 do
        p.L(gx + col * cell_w, gy + 28, gx + col * cell_w, grid_bottom, BB.COLOR_DARK_GRAY, 1)
    end
    for row = 0, 6 do
        p.L(gx, gy + 28 + row * cell_h, grid_right, gy + 28 + row * cell_h, BB.COLOR_DARK_GRAY, 1)
    end

    -- 日期数字
    local first_wday = tonumber(os.date("%w", month_start)) or 0
    first_wday = (first_wday + 6) % 7  -- 转为周一为0
    for day = 1, days_in_month do
        local slot = first_wday + day - 1
        local col, row = slot % 7, math.floor(slot / 7)
        local cx, cy = gx + col * cell_w, gy + 28 + row * cell_h
        p.T(tostring(day), cx + 6, cy + 5, 11, true, cell_w - 12, BB.COLOR_BLACK)
    end

    p.L(53, 789, 952, 789, BB.COLOR_DARK_GRAY, 1)
    local summary = {
        { "READING TIME", "阅读时长", rl.rlTime(agg.seconds), "19-vintage-timetable.svg" },
        { "READING DAYS", "阅读天数", tostring(active_days) .. " 天", "18-vintage-ticket.svg" },
        { "FINISHED", "读完数量", tostring(rl.rlFinishedCount(rows)) .. " 读完", "20-leather-luggage.svg" },
        { "PAGES READ", "阅读页数", tostring(agg.pages) .. " 页", "14-station-signboard.svg" },
    }
    rl.rlReferenceMetrics(bb, p, summary, 789, 910)
    p.L(53, 910, 952, 910, BB.COLOR_GRAY_B, 1)
    rl.rlReferenceFooter(bb, p, string.format("M%04d%02d", current.year, current.month),
        string.format("阅读线路 · READING LINE · MONTH PASS · %04d.%02d", current.year, current.month), true)

    -- 书籍跨度条（可选，依赖SQL数据库）
    local calendar_ok = false
    local calendar_books, calendar_ok = rl.readingCalendarBooks(current.year, current.month)
    if calendar_ok then
        local calendar_weeks = rl.rlCalendarWeeks(current.year, current.month, days_in_month, first_wday, calendar_books, 3)
        local span_colors = {
            { fg = BB.COLOR_WHITE, bg = BB.COLOR_GRAY_4 },
            { fg = BB.COLOR_WHITE, bg = BB.COLOR_DARK_GRAY },
            { fg = BB.COLOR_WHITE, bg = BB.COLOR_GRAY_4 },
            { fg = BB.COLOR_WHITE, bg = BB.COLOR_GRAY_4 },
        }
        for week_index, week in ipairs(calendar_weeks) do
            for col, day_books in ipairs(week.days_books) do
                for lane, book in ipairs(day_books) do
                    if book and book.start_day == col then
                        local color = span_colors[(book.id % #span_colors) + 1]
                        local sx = gx + (col - 1) * cell_w + 4
                        local sy = gy + 28 + (week_index - 1) * cell_h + 29 + (lane - 1) * 19
                        local span_w = book.span_days * cell_w - 8
                        p.R(sx, sy, span_w, 16, color.bg)
                        local max_chars = math.max(3, math.floor((span_w - 8) / 10))
                        p.CT(rl.rlEllipsize(book.title, max_chars), sx, sy + 2, span_w, 7, true, color.fg)
                    end
                end
            end
        end
    end
end

return { render = render }
