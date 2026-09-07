-- month.lua - 月票渲染（对齐源插件 paintReadingMonth）

local BB = require("ffi/blitbuffer")
local logger = require("logger")
local rl = require("lib.rl_reference")
local cover_helper = require("lib.cover_helper")

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
    -- 逐日书目：per_day["YYYY-MM-DD"] = { {id, title}, ... }
    -- SQL 已按「当天阅读时长降序」排序，故 books[1] 即当天读得最多的书
    local per_day, calendar_ok = rl.readingCalendarBooks(current.year, current.month)
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

    -- 日期数字（有阅读的日期改由封面左上角的白底数字牌绘制，此处跳过）
    local first_wday = tonumber(os.date("%w", month_start)) or 0
    first_wday = (first_wday + 6) % 7  -- 转为周一为0
    local function dayBooks(day)
        if not calendar_ok or not per_day then return nil end
        return per_day[string.format("%04d-%02d-%02d", current.year, current.month, day)]
    end
    for day = 1, days_in_month do
        local books = dayBooks(day)
        if not books or #books == 0 then
            local slot = first_wday + day - 1
            local col, row = slot % 7, math.floor(slot / 7)
            local cx, cy = gx + col * cell_w, gy + 28 + row * cell_h
            p.T(tostring(day), cx + 6, cy + 5, 11, true, cell_w - 12, BB.COLOR_BLACK)
        end
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

    -- ============================================================
    -- 日历格封面（2026-09-07 重构，借鉴 covercalendar.koplugin「封面即格子」）
    --   1 本 → 单张大图；2 本 → 左右并排；3 本及以上 → 扇形叠放（封顶 3 张）
    --   超出部分右下角 +N 角标；跨天连读的书每天各放同一张封面（原跨度条已取消）
    --   取不到封面 → 浅灰书名占位牌（最多两行，超出省略号）
    -- ============================================================
    if calendar_ok then
        local COVER_ASPECT = 0.72   -- 常见书封宽高比（rl.getBookCoverFromPath 会拉伸，须按比例给尺寸）
        local CELL_PAD     = 3      -- 格子内边距（虚拟坐标）
        local GAP          = 4      -- 两本并排时的间距
        local MAX_STACK    = 3      -- 扇形叠放最多张数
        -- 顶部日期条预留高度：封面整体下移，避免压住左上角日期数字
        -- 说明：单本时封面会垂直占满格子、双书时顶边也贴着数字，都会遮住数字下半截
        local DAY_BAR_H    = 16     -- 日期牌高度（虚拟坐标），封面从该高度下方开始画
        local cache = cover_helper.newCoverCache()
        local hit, tried = 0, 0

        -- 在虚拟坐标盒子内居中画一张封面（保持书封比例）；成功返回 true
        local function paintCoverIn(title, box_x, box_y, box_w, box_h)
            local ok_path, path = pcall(cover_helper.findBookFile, title)
            if not ok_path or not path then return false end
            local rw, rh = box_w * p.s, box_h * p.sy
            local cw = math.min(rw, rh * COVER_ASPECT)
            local ch = cw / COVER_ASPECT
            if ch > rh then ch = rh; cw = ch * COVER_ASPECT end
            cw = math.max(1, math.floor(cw))
            ch = math.max(1, math.floor(ch))
            local wd = cache:get(path, cw, ch)
            if not wd then return false end
            local vx = box_x + (box_w - cw / p.s) / 2
            local vy = box_y + (box_h - ch / p.sy) / 2
            local ok_paint = pcall(wd.paintTo, wd, bb, p.X(vx), p.Y(vy))
            return ok_paint == true
        end

        -- 按真实渲染宽度切行（用 painter.M 实测，规避「全角字宽=字号」在用户字体下偏小）
        local function splitByWidth(title, max_w, size)
            local chars = rl.utf8Chars(tostring(title or ""))
            local lines, cur = {}, ""
            for i = 1, #chars do
                local candidate = cur .. chars[i]
                if cur ~= "" and (p.M(candidate, size) > max_w) then
                    if #lines == 0 then
                        lines[1] = cur
                        cur = chars[i]
                    else
                        local last = rl.utf8Chars(cur)
                        if #last > 1 then table.remove(last) end
                        last[#last + 1] = "…"
                        cur = table.concat(last)
                        break
                    end
                else
                    cur = candidate
                end
            end
            if cur ~= "" then lines[#lines + 1] = cur end
            return lines
        end

        -- 取不到封面时的占位牌：浅灰底 + 居中书名（最多两行）
        local function paintTitleChip(title, box_x, box_y, box_w, box_h)
            p.R(box_x, box_y, box_w, box_h, BB.COLOR_LIGHT_GRAY)
            local size = 9
            local lines = splitByWidth(title, box_w * p.s - 4, size)
            local max_lines = math.max(1, math.floor((box_h * p.sy - 4) / (size * p.font_s * 1.3)))
            if #lines > max_lines then lines[max_lines] = lines[max_lines] .. "…" end
            local lh = size * 1.3
            local shown = math.min(#lines, max_lines)
            local ty = box_y + (box_h - shown * lh) / 2
            for i = 1, shown do
                p.CT(lines[i], box_x, ty + (i - 1) * lh, box_w, size, false, BB.COLOR_BLACK)
            end
        end

        local function paintCoverOrChip(title, box_x, box_y, box_w, box_h)
            if paintCoverIn(title, box_x, box_y, box_w, box_h) then return true end
            paintTitleChip(title, box_x, box_y, box_w, box_h)
            return false
        end

        for day = 1, days_in_month do
            local books = dayBooks(day)
            if books and #books > 0 then
                local n = #books
                local slot = first_wday + day - 1
                local col, row = slot % 7, math.floor(slot / 7)
                local cx, cy = gx + col * cell_w, gy + 28 + row * cell_h
                -- 仅 2 本及以上才让出顶部日期条（封面整体下移）；单本保持占满格子
                -- 说明：单本时封面垂直铺满整格，视觉上更饱满；日期白牌在封面之后绘制，仍覆盖于其上
                local bar = (n >= 2) and DAY_BAR_H or 0
                local bx, by = cx + CELL_PAD, cy + CELL_PAD + bar
                local bw, bh = cell_w - CELL_PAD * 2, cell_h - CELL_PAD * 2 - bar
                local painted = 0

                if n == 1 then
                    if paintCoverOrChip(books[1].title, bx, by, bw, bh) then painted = 1 end
                elseif n == 2 then
                    local half = (bw - GAP) / 2
                    if paintCoverOrChip(books[1].title, bx, by, half, bh) then painted = painted + 1 end
                    if paintCoverOrChip(books[2].title, bx + half + GAP, by, half, bh) then painted = painted + 1 end
                else
                    local fan_x = math.max(3, math.floor(bw * 0.10))
                    local fan_y = math.max(2, math.floor(fan_x * 0.5))
                    local stack_w = bw - fan_x * (MAX_STACK - 1)
                    local stack_h = bh - fan_y * (MAX_STACK - 1)
                    -- 倒序绘制：后画的压在上层，books[1]（读得最多）最终完整可见
                    for i = math.min(n, MAX_STACK), 1, -1 do
                        local ok = paintCoverOrChip(books[i].title,
                            bx + (i - 1) * fan_x, by + (i - 1) * fan_y, stack_w, stack_h)
                        if ok then painted = painted + 1 end
                    end
                end
                tried = tried + n
                hit = hit + painted

                -- 右下角 +N 角标（3 本以上时的超出部分）
                if n > MAX_STACK then
                    local badge_w, badge_h = 24, 14
                    local bxx = cx + cell_w - CELL_PAD - badge_w
                    local byy = cy + cell_h - CELL_PAD - badge_h
                    p.R(bxx, byy, badge_w, badge_h, BB.COLOR_DARK_GRAY)
                    p.CT("+" .. (n - MAX_STACK), bxx, byy + 2, badge_w, 9, true, BB.COLOR_WHITE)
                end

                -- 日期数字：白底小牌位于格子顶部（封面已下移 DAY_BAR_H，数字完整露出）
                -- 牌宽随位数自适应：两位数加宽，保证白底完整衬住数字
                local day_str = tostring(day)
                local badge_w = (#day_str > 1) and 25 or 19
                p.R(cx + 3, cy + 2, badge_w, DAY_BAR_H, BB.COLOR_WHITE)
                p.T(day_str, cx + 6, cy + 5, 11, true, badge_w - 6, BB.COLOR_BLACK)
            end
        end

        cache:freeAll()
        logger.info(string.format("[BookReceipt] 月票封面命中 %d/%d", hit, tried))
    end
end

return { render = render }
