-- book.lua - 单书行程票渲染（移植自补丁 paintReadingBook）

local BB = require("ffi/blitbuffer")
local rl = require("lib.rl_reference")

local function render(bb, x, y, w, h, book_title, ref_date)
    ref_date = ref_date or os.time()
    local rows, ok = rl.readReadingDataAll()
    if not ok or not rows then
        local p = rl.rlReferencePainter(bb, y, h)
        rl.rlReferenceFrame(bb, p, { radius = 36 })
        p.T("统计库暂不可用", 300, 500, 18, true, 400, BB.COLOR_BLACK)
        return
    end

    -- 尝试用 md5 匹配（更可靠），回退到标题匹配
    local selected = {}
    if book_title and book_title ~= "" then
        -- 先尝试精确匹配
        for _, row in ipairs(rows) do
            if row.title == book_title then
                selected[#selected + 1] = row
            end
        end
        -- 如果精确匹配没结果，尝试子串匹配（处理编码差异）
        if #selected == 0 then
            for _, row in ipairs(rows) do
                local rtitle = row.title or ""
                local btitle = book_title or ""
                if rtitle ~= "" and btitle ~= "" then
                    -- 去除标点空格后比较
                    local rnorm = rtitle:gsub("[%s%p]", ""):lower()
                    local bnorm = btitle:gsub("[%s%p]", ""):lower()
                    if rnorm == bnorm or rnorm:find(bnorm) or bnorm:find(rnorm) then
                        selected[#selected + 1] = row
                    end
                end
            end
        end
    end

    -- 如果还是没匹配到，取最新一条
    if #selected == 0 then
        local latest = rows[#rows]
        if latest then
            selected[#selected + 1] = latest
            book_title = latest.title or "暂无阅读记录"
        end
    end

    local first, last = selected[1], selected[#selected]
    if not first then
        local p = rl.rlReferencePainter(bb, y, h)
        rl.rlReferenceFrame(bb, p, { radius = 36 })
        p.T("暂无阅读记录", 300, 500, 18, true, 400, BB.COLOR_BLACK)
        return
    end

    local journeys = rl.rlBoardings(selected)
    local aggregate = rl.rlAggregate(selected)
    local seconds = aggregate.seconds
    local longest_pause = 0
    for i = 2, #journeys do
        local previous_end = (journeys[i - 1].last_time or journeys[i - 1].time or 0) + (journeys[i - 1].duration or 0)
        longest_pause = math.max(longest_pause, math.max(0, (journeys[i].time or 0) - previous_end))
    end
    local average = #journeys > 0 and seconds / #journeys or 0
    local total_pages = 0
    for _, row in ipairs(selected) do
        total_pages = math.max(total_pages, tonumber(row.pages) or 0)
    end
    local current_page = tonumber(last and (last.display_page or last.page)) or 0
    local progress = total_pages > 0 and math.max(0, math.min(100, math.floor(current_page * 100 / total_pages + .5))) or 0
    local author = tostring(first and first.authors or "")
    if author == "" then author = "作者信息未记录" end
    local first_date = first and os.date("%m.%d", first.time) or "--.--"
    local stamp_date = first and os.date("*t", first.time) or os.date("*t", os.time())
    local month_names = { "一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月" }

    local p = rl.rlReferencePainter(bb, y, h)
    rl.rlReferenceFrame(bb, p, { radius = 36 })

    p.T("TICKET NO.", 68, 52, 9, false, 160, BB.COLOR_GRAY_3)
    p.T(string.format("%02d%04d-%d", stamp_date.month, stamp_date.year, tonumber(first and first.id) or 1), 68, 72, 17, true, 220, BB.COLOR_BLACK)
    p.CT(string.format("%04d / %s", stamp_date.year, month_names[stamp_date.month]), 724, 52, 220, 11, true, BB.COLOR_BLACK)
    p.CT("BOOK JOURNEY", 205, 94, 600, 40, true, BB.COLOR_BLACK)
    p.L(212, 184, 330, 184, BB.COLOR_GRAY_3, 1)
    p.L(676, 184, 794, 184, BB.COLOR_GRAY_3, 1)
    p.CT("单 书 行 程 票", 340, 169, 326, 16, true, BB.COLOR_BLACK)
    p.DL(68, 198, 938, 198, BB.COLOR_GRAY_B, 1)

    -- 主卡片区域
    p.R(68, 207, 870, 229, BB.COLOR_WHITE)
    p.L(68, 207, 938, 207, BB.COLOR_GRAY_3, 1)
    p.L(68, 436, 938, 436, BB.COLOR_GRAY_3, 1)
    p.L(68, 207, 68, 436, BB.COLOR_GRAY_B, 1)
    p.L(938, 207, 938, 436, BB.COLOR_GRAY_B, 1)
    p.R(91, 231, 148, 125, BB.COLOR_GRAY_E)
    p.L(91, 231, 239, 231, BB.COLOR_GRAY_3, 1)
    p.L(91, 356, 239, 356, BB.COLOR_GRAY_3, 1)
    p.L(91, 231, 91, 356, BB.COLOR_GRAY_3, 1)
    p.L(239, 231, 239, 356, BB.COLOR_GRAY_3, 1)

    -- 书名
    local cover_chars = rl.utf8Chars(book_title)
    for i = 1, math.min(5, #cover_chars) do
        p.T(cover_chars[i], 108, 239 + (i - 1) * 20, 12, true, 34, BB.COLOR_BLACK)
    end
    p.T("《" .. book_title .. "》", 271, 244, 21, true, 445, BB.COLOR_BLACK)
    p.T(author .. " · BOARDING DATE " .. first_date, 271, 282, 10, false, 445, BB.COLOR_GRAY_3)
    p.T("当前进度", 776, 238, 9, false, 125, BB.COLOR_GRAY_3)
    p.T(tostring(progress) .. "%", 776, 263, 29, true, 125, BB.COLOR_BLACK)
    p.R(776, 311, 118, 7, BB.COLOR_GRAY_E)
    if progress > 0 then p.R(776, 311, math.max(2, 118 * progress / 100), 7, BB.COLOR_GRAY_4) end
    p.T(tostring(current_page) .. " / " .. tostring(total_pages > 0 and total_pages or "—") .. " 页", 776, 326, 9, false, 125, BB.COLOR_GRAY_3)

    local facts = {
        { "BOARDING DATE", "出发日期", first_date },
        { "READING TIME", "阅读时长", rl.rlTime(seconds) },
        { "VISITS", "阅读次数", tostring(#journeys) },
        { "AVG. VISIT", "平均单次", rl.rlTime(average) },
    }
    for i, item in ipairs(facts) do
        local cx = 91 + (i - 1) * 201
        if i > 1 then p.L(cx - 13, 368, cx - 13, 425, BB.COLOR_GRAY_B, 1) end
        p.T(item[1], cx, 368, 7, false, 170, BB.COLOR_GRAY_3)
        p.T(item[2], cx, 383, 8, false, 170, BB.COLOR_GRAY_3)
        p.T(item[3], cx, 404, 15, true, 170, BB.COLOR_BLACK)
        if i == 2 then p.T("↗", cx + 157, 370, 8, true, 18, BB.COLOR_GRAY_3) end
    end

    -- 进度标尺
    p.T("0%", 68, 463, 10, true, 55, BB.COLOR_BLACK)
    p.CT(tostring(progress) .. "%", 770, 463, 90, 10, true, BB.COLOR_BLACK)
    p.T("100%", 884, 463, 10, true, 65, BB.COLOR_BLACK)
    p.L(87, 490, 918, 490, BB.COLOR_GRAY_3, 1)
    if progress > 0 then
        local progress_x = 87 + 831 * progress / 100
        p.Circle(progress_x, 490, 5, BB.COLOR_GRAY_4)
    end

    -- 里程碑
    local milestone_count = math.min(7, #journeys)
    local milestones = {}
    if milestone_count == 1 then
        milestones[1] = journeys[1]
    elseif milestone_count > 1 then
        local used = {}
        for i = 1, milestone_count do
            local index = math.floor(1 + (i - 1) * (#journeys - 1) / (milestone_count - 1) + .5)
            if not used[index] then used[index] = true; milestones[#milestones + 1] = journeys[index] end
        end
    end

    local line_x, route_top, route_bottom = 88, 530, 865
    p.L(line_x, route_top, line_x, route_bottom, BB.COLOR_BLACK, 2)

    if #milestones == 0 then
        p.Circle(line_x, 595, 8, BB.COLOR_WHITE)
        p.Circle(line_x, 595, 4, BB.COLOR_GRAY_3)
        p.T("尚未开始阅读 · NO JOURNEY YET", 132, 584, 13, false, 650, BB.COLOR_GRAY_3)
    else
        for i, journey in ipairs(milestones) do
            local cy = route_top + (i - 1) * (route_bottom - route_top) / math.max(1, #milestones - 1)
            local is_last = i == #milestones
            p.Circle(line_x, cy, is_last and 9 or 8, is_last and BB.COLOR_BLACK or BB.COLOR_WHITE)
            if not is_last then p.Circle(line_x, cy, 4, BB.COLOR_GRAY_3) end
            local row_page = tonumber(journey.last_page or journey.first_page) or 0
            local row_progress = total_pages > 0 and math.max(0, math.min(100, math.floor(row_page * 100 / total_pages + .5))) or 0
            p.T(os.date("%m.%d", journey.time), 128, cy - 10, 10, true, 72, BB.COLOR_BLACK)
            p.T(tostring(row_progress) .. "%", 225, cy - 10, 10, false, 62, BB.COLOR_GRAY_3)
            local label
            if i == 1 then
                label = "起点 · 首次登车"
            elseif is_last then
                label = "当前位置 · 第 " .. tostring(row_page) .. " 页"
            else
                label = "阅读打卡 · 第 " .. tostring(row_page) .. " 页"
            end
            p.T(label, 310, cy - 11, 12, is_last, 410, BB.COLOR_BLACK)
            p.T(rl.rlTime(journey.duration), 724, cy - 9, 9, false, 80, BB.COLOR_GRAY_3)
            local badge = i == 1 and "首次登车" or (is_last and "当前停留" or "打卡")
            p.R(824, cy - 14, 92, 27, is_last and BB.COLOR_GRAY_4 or BB.COLOR_WHITE)
            p.L(824, cy - 14, 916, cy - 14, BB.COLOR_GRAY_3, 1)
            p.L(824, cy + 13, 916, cy + 13, BB.COLOR_GRAY_3, 1)
            p.L(824, cy - 14, 824, cy + 13, BB.COLOR_GRAY_3, 1)
            p.L(916, cy - 14, 916, cy + 13, BB.COLOR_GRAY_3, 1)
            p.CT(badge, 824, cy - 9, 92, 8, false, is_last and BB.COLOR_WHITE or BB.COLOR_BLACK)
        end
    end

    p.L(68, 902, 938, 902, BB.COLOR_GRAY_3, 1)
    p.T("最长搁置 " .. rl.rlTime(longest_pause) .. " · 累计 " .. rl.rlFormatWords(aggregate.words), 70, 918, 10, false, 490, BB.COLOR_GRAY_3)
    p.T("阅读不是终点，思考才是抵达。", 70, 953, 11, true, 420, BB.COLOR_BLACK)
    p.T("KEEP READING, KEEP GOING.  →", 684, 953, 10, false, 255, BB.COLOR_GRAY_3)
end

return { render = render }
