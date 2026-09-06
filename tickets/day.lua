-- day.lua - 日票渲染
-- 基于 readingline.koplugin 的 paintReadingDay 移植

local BB = require("ffi/blitbuffer")
local rl = require("lib.rl_reference")

local function render(bb, x, y, w, h, ref_date)
    ref_date = ref_date or os.time()
    local start_ts = rl.rlDayStart(ref_date)
    local rows, ok = rl.readReadingData(start_ts, start_ts + 86400)
    local boardings = rl.rlBoardings(rows)
    local agg = rl.rlAggregate(rows)
    local cn_weekday, en_weekday, weekday_index = rl.rlWeekday(start_ts)
    
    local p = rl.rlReferencePainter(bb, y, h)
    local stats_hit_books = {}
    local ink = BB.COLOR_BLACK
    local muted = BB.COLOR_DARK_GRAY
    local line = BB.COLOR_GRAY_B
    
    -- 背景
    bb:paintRect(p.X(12), p.Y(8), math.max(1, p.X(994) - p.X(12)), math.max(1, p.Y(1084) - p.Y(8)), BB.COLOR_BLACK)
    bb:paintRect(p.X(18), p.Y(14), math.max(1, p.X(988) - p.X(18)), math.max(1, p.Y(1078) - p.Y(14)), BB.COLOR_WHITE)
    
    -- 边框
    p.L(18, 14, 988, 14, ink, 2)
    p.L(18, 14, 18, 1078, ink, 2)
    p.L(988, 14, 988, 1078, ink, 2)
    p.L(18, 1078, 988, 1078, ink, 2)
    
    -- 内边框
    p.L(38, 30, 968, 30, line, 1)
    p.L(38, 1062, 968, 1062, line, 1)
    p.L(38, 30, 38, 1062, line, 1)
    p.L(968, 30, 968, 1062, line, 1)
    
    -- 票根锯齿
    rl.rlPaintTicketNotches(bb, p.X(18), p.Y(14), p.X(988) - p.X(18), p.Y(1078) - p.Y(14), 
        math.max(12, math.floor(36 * p.s)), BB.COLOR_WHITE,
        { top = true, bottom = true, left = true, right = true })
    
    -- 标题
    p.T("阅读日票 · READING DAY PASS", 58, 67, 11, true, 420, ink)
    p.T("DAY TICKET", 58, 101, 42, true, 600, ink)
    p.T("今日阅读轨迹 / ONE DAY, FOUR BOARDINGS", 58, 177, 12, false, 560, muted)
    
    -- 分隔线
    p.DL(53, 235, 952, 235, line, 1)
    
    -- 日期信息
    p.T("日期 · DATE", 58, 246, 9, false, 120, muted)
    p.T(rl.rlDate(start_ts), 58, 266, 16, true, 150, ink)
    p.L(240, 243, 240, 282, line, 1)
    p.T("星期 · WEEKDAY", 270, 246, 9, false, 170, muted)
    p.T(cn_weekday .. " · " .. en_weekday, 270, 266, 16, true, 190, ink)
    p.L(500, 243, 500, 282, line, 1)
    p.T("有效日期 · VALID", 540, 246, 9, false, 160, muted)
    p.T("当日有效", 540, 266, 16, true, 180, ink)
    p.DL(53, 307, 952, 307, line, 1)
    p.DL(770, 31, 770, 235, line, 1)
    
    -- 检票口
    local gate_text = string.format("%02dA", weekday_index)
    local gate_width = p.M(gate_text, 28, ink)
    local a_width = p.M("A", 28, ink)
    local gate_right = p.X(796) + math.floor((130 * p.s + gate_width) / 2) + a_width
    
    local function RT(text, top, size, bold, color)
        local actual, fitted = p.M(text, size, color)
        rl.drawText(bb, tostring(text or ""), gate_right - actual, p.Y(top), fitted, bold, nil, color)
    end
    
    RT("NO. D" .. os.date("%Y%m%d", start_ts), 48, 10, false, muted)
    RT("检票口 · GATE", 75, 8, false, muted)
    RT(gate_text, 94, 28, true, ink)
    p.DL(795, 143, 952, 143, line, 1)
    RT("▼", 146, 10, true, ink)
    RT("日票", 169, 10, false, ink)
    RT("DAY PASS", 191, 10, false, muted)
    
    -- 乘车记录
    local top, bottom = 329, 630
    local line_x = 169
    p.L(line_x, top, line_x, bottom, ink, 2)
    
    local per_page = 7
    local total_boarding_pages = math.max(1, math.ceil(#boardings / per_page))
    local first_boarding = 1
    local last_boarding = math.min(#boardings, per_page)
    local max_rows = math.max(0, last_boarding - first_boarding + 1)
    
    if max_rows > 0 then
        for slot = 1, max_rows do
            local i = first_boarding + slot - 1
            local row = boardings[i]
            local cy = top + (slot - 1) * ((bottom - top) / math.max(1, max_rows - 1))
            
            if bb.paintCircle then
                if slot == max_rows then
                    local outer = math.max(8, math.floor(13 * p.s))
                    pcall(bb.paintCircle, bb, p.X(line_x), p.Y(cy), outer, ink)
                    pcall(bb.paintCircle, bb, p.X(line_x), p.Y(cy), math.max(3, math.floor(7 * p.s)), ink)
                else
                    local outer = math.max(7, math.floor(10 * p.s))
                    pcall(bb.paintCircle, bb, p.X(line_x), p.Y(cy), outer, ink)
                    pcall(bb.paintCircle, bb, p.X(line_x), p.Y(cy), math.max(2, math.floor(7 * p.s)), BB.COLOR_WHITE)
                end
            end
            
            p.T(os.date("%H:%M", row.time), 69, cy - 6, 10, false, 70, muted)
            p.T("上车", 206, cy - 8, 15, true, 64, ink)
            p.T("《" .. row.title .. "》", 294, cy - 11, 16, true, 430, ink)
            p.T("第 " .. tostring(row.first_page or 0) .. " 页 · 当前阅读", 294, cy + 15, 9, false, 380, muted)
            p.T(rl.rlTime(row.duration), 876, cy - 8, 14, false, 80, ink)
        end
    else
        p.T(ok and "当天没有阅读记录 · NO BOARDINGS" or "统计库暂不可用", 294, 505, 13, false, 400, muted)
    end
    
    -- 摘要
    p.L(53, 706, 952, 706, line, 1)
    p.T("今日摘要", 58, 737, 16, true, 130, ink)
    p.T("SUMMARY", 190, 742, 9, false, 100, muted)
    p.L(53, 774, 952, 774, line, 1)
    
    local longest = 0
    for _, row in ipairs(boardings) do
        longest = math.max(longest, row.duration or 0)
    end
    
    local summary = {
        { "READING TIME", "阅读时长", rl.rlTime(agg.seconds), "19-vintage-timetable.svg" },
        { "PAGES READ", "阅读页数", tostring(agg.pages) .. " 页", "18-vintage-ticket.svg" },
        { "WORDS READ", "阅读字数", rl.rlFormatWords(agg.words), "14-station-signboard.svg" },
        { "LONGEST READING", "最长阅读", rl.rlTime(longest), "03-train-front.svg" },
    }
    rl.rlReferenceMetrics(bb, p, summary, 789, 910)
    
    p.L(53, 910, 952, 910, line, 1)
    local caption = "阅读线路 · READING LINE · 日票 · DAY TICKET · D" .. os.date("%Y%m%d", start_ts)
    rl.rlReferenceFooter(bb, p, "D" .. tostring(start_ts), caption, true)
end

return { render = render }
