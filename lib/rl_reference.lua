-- rl_reference.lua - 从补丁 2-book-receipt-shortcut-and-lockscreen.lua 移植
-- 提供阅读小票渲染所需的全部工具和统计函数
-- 包含：drawText, 时间/日期工具, 阅读数据统计, 渲染坐标系, 锯齿边缘等

local BB = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local FontList = require("fontlist")
local font_pref = require("lib.font_pref")
local TextWidget = require("ui/widget/textwidget")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local LOG_TAG = "[BookReceipt.Lib]"

-- 插件目录路径（用于加载 SVG 图标等资源）
local PLUGIN_DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or "."

-- ImageWidget 延迟加载
local ImageWidget = nil
local function getImageWidget()
    if not ImageWidget then
        ImageWidget = require("ui/widget/imagewidget")
    end
    return ImageWidget
end

-- ============================================================
-- 字体和工具函数
-- ============================================================

local PLUGIN_FONT_NAME = "cfont"

local function simpleUIFontFace()
    return "cfont"
end

local function utf8Chars(str)
    str = tostring(str or "")
    local chars = {}
    if not str or str == "" then return chars end
    -- 注意：必须用 while 循环。Lua 的数值 for 循环会忽略循环体内对 i 的修改，
    -- 导致多字节汉字被拆成孤立续字节，渲染成乱码豆腐块
    local i, n = 1, #str
    while i <= n do
        local byte = string.byte(str, i)
        local clen = 1
        if byte >= 0xF0 then clen = 4
        elseif byte >= 0xE0 then clen = 3
        elseif byte >= 0xC0 then clen = 2
        end
        table.insert(chars, str:sub(i, i + clen - 1))
        i = i + clen
    end
    return chars
end

local function getFontFace(size)
    -- 优先用户当前字体（阅读/UI），其次回退 KOReader 系统 cfont（Noto Sans CJK）
    return font_pref.getPreferredFontFace(size, PLUGIN_FONT_NAME)
end

-- ============================================================
-- 文本绘制
-- ============================================================

-- 智能识别参数：兼容 7/8/9 参数调用
local function drawText(bb, text, x, y, size, bold, max_width, color, align)
    local actual_color, actual_align
    if type(color) == "string" then
        actual_color = BB.COLOR_BLACK
        actual_align = color
    else
        actual_color = color or BB.COLOR_BLACK
        actual_align = align or "left"
    end

    text = tostring(text or "")
    size = math.max(6, math.floor(size or 12))

    -- 原插件 readingline 语义：max_width 超限时缩小字号保证完整显示，而非截断加省略号
    if max_width then
        local probe = TextWidget:new{
            text = text,
            face = getFontFace(size),
            bold = bold and true or false,
            fgcolor = actual_color,
        }
        local measured = probe:getSize()
        probe:free()
        if measured and measured.w and measured.w > max_width then
            size = math.max(6, math.floor(size * max_width / measured.w))
        end
    end

    local face = getFontFace(size)

    local widget = TextWidget:new{
        text = text,
        face = face,
        bold = bold and true or false,
        fgcolor = actual_color,
    }
    widget:updateSize()

    local draw_x = math.floor(x)
    if actual_align == "right" then
        draw_x = math.floor(x - widget:getSize().w)
    elseif actual_align == "center" then
        draw_x = math.floor(x - widget:getSize().w / 2)
    end

    widget:paintTo(bb, draw_x, math.floor(y))
    local widget_size = widget:getSize()
    if widget.free then widget:free() end
    return widget_size
end

local function measureText(text, size, bold)
    local widget = TextWidget:new{
        text = tostring(text or ""),
        face = getFontFace(size),
        bold = bold and true or false,
    }
    widget:updateSize()
    local widget_size = widget:getSize()
    if widget.free then widget:free() end
    return widget_size.w
end

local function measureTextH(text, size, bold, max_width)
    local widget = TextWidget:new{
        text = tostring(text or ""),
        face = getFontFace(size),
        bold = bold and true or false,
        max_width = max_width,
    }
    widget:updateSize()
    local widget_size = widget:getSize()
    if widget.free then widget:free() end
    return widget_size.h
end

-- 按像素宽度截断文本
local function truncateToWidth(text, max_width, size, bold)
    text = tostring(text or "")
    if text == "" or not max_width or max_width <= 0 then return text end
    if measureText(text, size, bold) <= max_width then return text end
    local ellipsis = "…"
    local ellipsis_w = measureText(ellipsis, size, bold)
    local budget = max_width - ellipsis_w
    if budget <= 0 then return ellipsis end
    local out = {}
    local w = 0
    local i = 1
    local len = #text
    while i <= len do
        local byte = string.byte(text, i)
        local clen = 1
        if byte >= 0xF0 then clen = 4
        elseif byte >= 0xE0 then clen = 3
        elseif byte >= 0xC0 then clen = 2
        end
        local ch = text:sub(i, i + clen - 1)
        local cw = measureText(ch, size, bold)
        if w + cw > budget then break end
        table.insert(out, ch)
        w = w + cw
        i = i + clen
    end
    if #out == 0 then return ellipsis end
    return table.concat(out) .. ellipsis
end

-- ============================================================
-- 时间/日期工具
-- ============================================================

local function rlTime(seconds)
    -- 统一换算为「小时」单位（2026-09-07）：避免「18小时49分」这类长文本
    -- 与右侧字段（如 ACTIVE DAYS「15 天」）挤压重叠
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds < 60 then
        return "0小时"
    end
    local hours = seconds / 3600
    if hours < 24 then
        -- 不足 24 小时保留 1 位小数（如 18.8小时），去掉尾随 .0
        local txt = string.format("%.1f", math.floor(hours * 10 + 0.5) / 10)
        txt = txt:gsub("%.0$", "")
        return txt .. "小时"
    end
    return string.format("%d小时", math.floor(hours + 0.5))
end

local function rlDate(ts)
    return os.date("%Y.%m.%d", ts)
end

local RL_CN_WEEKDAYS = {"周一", "周二", "周三", "周四", "周五", "周六", "周日"}
local RL_EN_WEEKDAYS = {"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"}

local function rlWeekday(ts)
    local wday = tonumber(os.date("%w", ts or os.time())) or 0
    local index = wday == 0 and 7 or wday
    return RL_CN_WEEKDAYS[index], RL_EN_WEEKDAYS[index], index
end

local function rlDayStart(ts)
    local d = os.date("*t", ts or os.time())
    return os.time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end

local function rlWeekStart(ts)
    local day_start = rlDayStart(ts)
    local wday = tonumber(os.date("%w", day_start)) or 0
    return day_start - (wday == 0 and 6 or wday - 1) * 86400
end

local function rlMonthStart(ts)
    local d = os.date("*t", ts or os.time())
    return os.time({ year = d.year, month = d.month, day = 1, hour = 0, min = 0, sec = 0 })
end

local function rlYearStart(ts)
    local d = os.date("*t", ts or os.time())
    return os.time({ year = d.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
end

-- ============================================================
-- 阅读数据统计
-- ============================================================

local _reading_rows_cache = { order = {} }

local function readReadingData(from_ts, to_ts)
    local db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local db_mtime = tonumber(lfs.attributes(db_path, "modification")) or 0
    local cache_key = tostring(from_ts) .. ":" .. tostring(to_ts) .. ":" .. tostring(db_mtime)

    local cached = _reading_rows_cache[cache_key]
    if cached and os.time() - cached.saved_at <= 15 then
        return cached.rows, cached.ok
    end

    local rows = {}
    local ok, err = pcall(function()
        local conn = SQ3.open(db_path)
        local stmt = conn:prepare([[
            SELECT psd.rowid, psd.start_time, psd.duration, psd.page,
                b.id, b.title, psd.total_pages, b.pages,
                b.total_read_time, b.total_read_pages, b.authors, b.md5
            FROM page_stat_data psd JOIN book b ON b.id = psd.id_book
            WHERE psd.start_time >= ? AND psd.start_time < ?
            ORDER BY psd.start_time ASC;
        ]])
        local row = stmt:reset():bind(from_ts, to_ts):step()
        while row do
            local row_time, remaining = tonumber(row[2]) or 0, math.max(0, tonumber(row[3]) or 0)
            local page = tonumber(row[4]) or 0
            local source_pages = tonumber(row[7]) or 0
            local local_pages = tonumber(row[8]) or 0
            local display_page = page
            if source_pages > 0 and local_pages > 0 then
                display_page = math.max(0, math.floor(page * local_pages / source_pages + .5))
            end
            repeat
                local local_date = os.date("*t", row_time)
                local next_midnight = os.time({ year = local_date.year, month = local_date.month, day = local_date.day + 1, hour = 0, min = 0, sec = 0 })
                local local_day = os.date("%Y-%m-%d", row_time)
                local local_next_day = os.date("%Y-%m-%d", row_time + 86400)
                local segment = remaining
                if local_day ~= local_next_day then
                    segment = math.min(remaining, math.max(1, next_midnight - row_time))
                end
                rows[#rows + 1] = {
                    rowid = tonumber(row[1]) or 0, time = row_time,
                    source_time = tonumber(row[2]) or row_time,
                    duration = segment, page = page, display_page = display_page,
                    id = tonumber(row[5]) or 0, title = tostring(row[6] or "未知书籍"),
                    source_pages = source_pages, local_pages = local_pages, pages = local_pages,
                    total_time = tonumber(row[9]) or 0,
                    total_pages = tonumber(row[10]) or 0, authors = tostring(row[11] or ""),
                    md5 = tostring(row[12] or ""),
                }
                if segment >= remaining or remaining <= 0 then break end
                remaining = remaining - segment
                row_time = next_midnight
            until false
            row = stmt:step()
        end
        stmt:close()

        -- 数据校正
        local canonical = {}
        local cstmt = conn:prepare([[
            SELECT b.id,
                   strftime('%Y-%m-%d', ps.start_time, 'unixepoch', 'localtime') AS day,
                   sum(ps.duration)
            FROM page_stat ps JOIN book b ON b.id = ps.id_book
            WHERE ps.start_time >= ? AND ps.start_time < ?
            GROUP BY b.id, day;
        ]])
        local crow = cstmt:reset():bind(from_ts, to_ts):step()
        while crow do
            canonical[tostring(crow[1]) .. "\0" .. tostring(crow[2])] = math.max(0, tonumber(crow[3]) or 0)
            crow = cstmt:step()
        end
        cstmt:close()

        local raw_totals = {}
        for _, item in ipairs(rows) do
            local day = os.date("%Y-%m-%d", item.source_time or item.time)
            local key = tostring(item.id) .. "\0" .. day
            raw_totals[key] = (raw_totals[key] or 0) + (tonumber(item.duration) or 0)
        end
        for _, item in ipairs(rows) do
            local day = os.date("%Y-%m-%d", item.source_time or item.time)
            local key = tostring(item.id) .. "\0" .. day
            local raw_total, canonical_total = raw_totals[key] or 0, canonical[key]
            item.raw_duration = item.duration
            if canonical_total and raw_total > 0 then
                item.duration = (tonumber(item.duration) or 0) * canonical_total / raw_total
            end
        end
        conn:close()
    end)
    if not ok then
        logger.warn(LOG_TAG, "readReadingData query failed:", err)
    end

    _reading_rows_cache[cache_key] = { rows = rows, ok = ok, saved_at = os.time() }
    _reading_rows_cache.order[#_reading_rows_cache.order + 1] = cache_key
    while #_reading_rows_cache.order > 8 do
        local old = table.remove(_reading_rows_cache.order, 1)
        _reading_rows_cache[old] = nil
    end

    return rows, ok
end

local function readReadingDataForDay(day_ts)
    local start = rlDayStart(day_ts)
    return readReadingData(start, start + 86400)
end

local function readReadingDataForWeek(week_ts)
    local monday = rlWeekStart(week_ts)
    return readReadingData(monday, monday + 7 * 86400)
end

local function readReadingDataForMonth(month_ts)
    local month_start = rlMonthStart(month_ts)
    local d = os.date("*t", month_ts)
    local next_month_start = os.time({ year = d.year, month = d.month + 1, day = 1, hour = 0, min = 0, sec = 0 })
    return readReadingData(month_start, next_month_start)
end

local function readReadingDataForYear(year_ts)
    local year_start = rlYearStart(year_ts)
    return readReadingData(year_start, year_start + 365 * 86400)
end

local function readReadingDataAll()
    return readReadingData(0, os.time() + 1)
end

local function rlBoardings(rows)
    local result = {}
    local current
    for _, row in ipairs(rows or {}) do
        local gap = current and (row.time - current.last_time) or math.huge
        if not current or current.id ~= row.id or gap > 20 * 60 then
            current = {
                id = row.id, title = row.title, time = row.time, last_time = row.time,
                duration = tonumber(row.duration) or 0,
                first_page = row.display_page or row.page,
                last_page = row.display_page or row.page,
                rows = 1, source_rows = { row },
            }
            result[#result + 1] = current
        else
            current.last_time = row.time
            current.duration = current.duration + (tonumber(row.duration) or 0)
            current.last_page = row.display_page or row.page
            current.rows = current.rows + 1
            current.source_rows[#current.source_rows + 1] = row
        end
    end
    return result
end

local function rlAggregate(rows)
    local result = { seconds = 0, pages = 0, words = 0, sessions = 0, books = {}, days = {} }
    local seen = {}
    local readingWordsPerPage = 260

    for _, row in ipairs(rows or {}) do
        result.seconds = result.seconds + (row.duration or 0)
        result.sessions = result.sessions + 1
        local book_key = tostring(row.title or "") .. "\0" .. tostring(row.authors or "")
        local raw_page = math.max(0, tonumber(row.page) or 0)
        local source_total = math.max(0, tonumber(row.source_pages) or 0)
        local local_total = math.max(0, tonumber(row.local_pages) or tonumber(row.pages) or 0)
        if source_total <= 0 then source_total = local_total end
        if local_total <= 0 then local_total = source_total end
        local page_delta = 0
        local word_delta
        local signature = book_key .. "\0" .. tostring(row.time or 0) .. "\0" .. tostring(raw_page)
        if not seen[signature] then
            page_delta = raw_page > 0 and 1 or 0
            seen[signature] = true
        end
        word_delta = page_delta * readingWordsPerPage

        local book_entry = result.books[book_key] or { title = row.title, seconds = 0, pages = 0, words = 0, sessions = 0 }
        result.pages = result.pages + page_delta
        result.words = result.words + word_delta
        result.books[book_key] = book_entry
        book_entry.seconds = book_entry.seconds + (row.duration or 0)
        book_entry.pages = book_entry.pages + page_delta
        book_entry.words = book_entry.words + word_delta
        book_entry.sessions = book_entry.sessions + 1

        local day = os.date("%Y-%m-%d", row.time)
        result.days[day] = result.days[day] or { seconds = 0, pages = 0, words = 0, books = {} }
        result.days[day].seconds = result.days[day].seconds + (row.duration or 0)
        result.days[day].pages = result.days[day].pages + page_delta
        result.days[day].words = result.days[day].words + word_delta
        result.days[day].books[book_key] = row.title
    end
    result.pages = math.floor(result.pages + .5)
    result.words = math.floor(result.words + .5)
    for _, book in pairs(result.books) do
        book.pages = math.floor(book.pages + .5)
        book.words = math.floor(book.words + .5)
    end
    for _, day in pairs(result.days) do
        day.pages = math.floor(day.pages + .5)
        day.words = math.floor(day.words + .5)
    end
    return result
end

local function rlFinishedCount(rows)
    local books = {}
    for _, row in ipairs(rows or {}) do
        local source_total = math.max(0, tonumber(row.source_pages) or tonumber(row.local_pages) or tonumber(row.pages) or 0)
        local progress = source_total > 0 and (tonumber(row.page) or 0) / source_total or 0
        local book = books[row.id] or { max_progress = 0 }
        book.max_progress = math.max(book.max_progress, progress)
        books[row.id] = book
    end
    local count = 0
    for _, book in pairs(books) do
        if book.max_progress >= .995 and book.max_progress <= 1.05 then count = count + 1 end
    end
    return count
end

-- ============================================================
-- 渲染工具函数
-- ============================================================

local function rlPaintTicketNotches(bb, x, y, w, h, radius, paper_color, sides)
    radius = math.max(5, math.floor(radius or 12))
    sides = sides or {}
    local top = sides.top ~= false
    local bottom = sides.bottom ~= false
    local left = sides.left ~= false
    local right = sides.right ~= false
    local black = BB.COLOR_BLACK
    local mid_x = sides.notch_x or (x + math.floor(w / 2))
    local mid_y = sides.notch_y or (y + math.floor(h / 2))

    for row = 0, radius do
        local span = math.max(0, math.floor(math.sqrt(radius * radius - row * row)))
        if top then bb:paintRect(mid_x - span, y + row, span * 2 + 1, 1, black) end
        if bottom then bb:paintRect(mid_x - span, y + h - row - 1, span * 2 + 1, 1, black) end
        if left then bb:paintRect(x + row, mid_y - span, 1, span * 2 + 1, black) end
        if right then bb:paintRect(x + w - row - 1, mid_y - span, 1, span * 2 + 1, black) end
    end
end

local function rlReferencePainter(bb, y, h)
    local viewport_w = Screen:getWidth()
    local s = math.min((viewport_w - 36) / 1006, (h - 24) / 1093)
    local sy = math.max(s, (h - 8) / 1093)
    local ox, oy = (viewport_w - 1006 * s) / 2, y + 4
    local font_s = math.min(s, 1)
    local ui_s = math.min(s, 1.15)

    local function X(v) return math.floor(ox + v * s) end
    local function Y(v) return math.floor(oy + v * sy) end

    local function L(x1, y1, x2, y2, color, thick)
        if x1 == x2 then
            bb:paintRect(X(x1), Y(y1), math.max(1, math.floor((thick or 1) * s)), math.max(1, Y(y2) - Y(y1)), color)
        else
            bb:paintRect(X(x1), Y(y1), math.max(1, X(x2) - X(x1)), math.max(1, math.floor((thick or 1) * s)), color)
        end
    end

    local function DL(x1, y1, x2, y2, color, thick)
        local dash, gap = 7, 5
        if y1 == y2 then
            local cursor = x1
            while cursor < x2 do
                L(cursor, y1, math.min(x2, cursor + dash), y2, color, thick)
                cursor = cursor + dash + gap
            end
        else
            local cursor = y1
            while cursor < y2 do
                L(x1, cursor, x2, math.min(y2, cursor + dash), color, thick)
                cursor = cursor + dash + gap
            end
        end
    end

    local function R(rx, ry, rw, rh, color)
        bb:paintRect(X(rx), Y(ry), math.max(1, math.floor(rw * s)), math.max(1, math.floor(rh * sy)), color)
    end

    local function T(text, px, py, size, bold, maxw, color)
        text = tostring(text or "")
        local fitted = math.max(6, math.floor(size * font_s))
        if maxw then
            local estimated = 0
            for _, ch in ipairs(utf8Chars(text)) do
                estimated = estimated + (ch:byte(1) >= 128 and fitted or fitted * 0.58)
            end
            local limit = math.max(10, math.floor(maxw * s))
            if estimated > limit and estimated > 0 then
                fitted = math.max(6, math.floor(fitted * limit / estimated))
            end
        end
        drawText(bb, text, X(px), Y(py), fitted, bold, nil, color)
    end

    local function CT(text, left, top, width_ref, size, bold, color)
        local fitted = math.max(6, math.floor(size * font_s))
        local widget = TextWidget:new{
            text = tostring(text or ""),
            face = getFontFace(fitted),
            bold = bold and true or false,
            fgcolor = color or BB.COLOR_BLACK,
        }
        widget:updateSize()
        local actual = widget:getSize().w
        widget:free()
        drawText(bb, text, X(left) + math.floor((width_ref * s - actual) / 2), Y(top), fitted, bold, nil, color)
    end

    local function M(text, size, color)
        local fitted = math.max(6, math.floor(size * font_s))
        local widget = TextWidget:new{
            text = tostring(text or ""),
            face = getFontFace(fitted),
            bold = false,
            fgcolor = color or BB.COLOR_BLACK,
        }
        widget:updateSize()
        local actual = widget:getSize().w
        widget:free()
        return actual, fitted
    end

    local function Circle(cx, cy, radius, color)
        local r = math.max(2, math.floor(radius * ui_s))
        if bb.paintCircle then
            pcall(bb.paintCircle, bb, X(cx), Y(cy), r, color)
        else
            bb:paintRect(X(cx) - r, Y(cy) - r, r * 2, r * 2, color)
        end
    end

    return {
        X = X, Y = Y, L = L, DL = DL, R = R,
        T = T, CT = CT, M = M, Circle = Circle,
        s = s, sy = sy, ui_s = ui_s, font_s = font_s
    }
end

local function rlReferenceFrame(bb, p, notch_spec)
    notch_spec = notch_spec or {}
    p.R(12, 8, 982, 1070, BB.COLOR_BLACK)
    p.R(18, 14, 970, 1064, BB.COLOR_WHITE)
    p.L(18, 14, 988, 14, BB.COLOR_BLACK, 2)
    p.L(18, 14, 18, 1078, BB.COLOR_BLACK, 2)
    p.L(988, 14, 988, 1078, BB.COLOR_BLACK, 2)
    p.L(18, 1078, 988, 1078, BB.COLOR_BLACK, 2)
    p.L(38, 30, 968, 30, BB.COLOR_GRAY_B, 1)
    p.L(38, 1062, 968, 1062, BB.COLOR_GRAY_B, 1)
    p.L(38, 30, 38, 1062, BB.COLOR_GRAY_B, 1)
    p.L(968, 30, 968, 1062, BB.COLOR_GRAY_B, 1)

    local spec = {}
    for key, value in pairs(notch_spec) do spec[key] = value end
    spec.radius = nil
    if spec.notch_x then spec.notch_x = p.X(spec.notch_x) end
    if spec.notch_y then spec.notch_y = p.Y(spec.notch_y) end
    rlPaintTicketNotches(bb, p.X(18), p.Y(14), p.X(988) - p.X(18), p.Y(1078) - p.Y(14),
        math.max(18, math.floor((notch_spec.radius or 36) * p.s)), BB.COLOR_WHITE, spec)
end

-- 渲染指标图标（SVG 图标，移植自 readingline Utils.drawPluginIcon）
local function rlMetricIcon(bb, filename, x, y, size)
    local path = PLUGIN_DIR .. "/../assets/train-icons-svg/" .. filename
    if not lfs.attributes(path, "mode") then return end
    local ok, widget = pcall(function()
        return getImageWidget():new{file=path, width=size, height=size, alpha=true}
    end)
    if ok and widget then
        pcall(widget.paintTo, widget, bb, x, y)
        if widget.free then widget:free() end
    end
end

-- 从书籍文件路径提取封面（与 readingline 同链路：CoverBrowser 缓存优先，DocumentRegistry 兜底）
-- 返回按 w×h 缩放好的 ImageWidget；提取失败返回 nil
local function getBookCoverFromPath(path, w, h)
    if not path or path == "" then return nil end
    if lfs.attributes(path, "mode") ~= "file" then return nil end
    w = math.max(1, math.floor(w or 100))
    h = math.max(1, math.floor(h or 140))
    local ImageWidget = getImageWidget()
    -- 快路径：CoverBrowser bookinfo 缓存中的封面 blitbuffer（仅读缓存，不打开文档）
    local ok_bim, BIM = pcall(require, "bookinfomanager")
    if not ok_bim then ok_bim, BIM = pcall(require, "plugins/coverbrowser.koplugin/bookinfomanager") end
    if ok_bim and BIM and BIM.getBookInfo then
        local ok_info, info = pcall(BIM.getBookInfo, BIM, path, true)
        local source_bb = ok_info and info and info.cover_bb
        if source_bb then
            local target_bb
            local ok_target = pcall(function()
                target_bb = BB.new(w, h, source_bb:getType())
                target_bb:fill(BB.COLOR_WHITE)
                local scaler = ImageWidget:new{
                    image = source_bb, image_disposable = false,
                    width = w, height = h,
                }
                scaler:paintTo(target_bb, 0, 0)
                if scaler.free then scaler:free() end
            end)
            if source_bb.free then pcall(source_bb.free, source_bb) end
            if ok_target and target_bb then
                return ImageWidget:new{ image = target_bb, width = w, height = h, scale_factor = 1 }
            end
        end
        return nil -- quick 模式无缓存时不打开文档，避免阻塞渲染
    end
    -- 兜底：打开文档提取封面（较慢）
    local ok_registry, DocumentRegistry = pcall(require, "document/documentregistry")
    if not ok_registry or not DocumentRegistry then return nil end
    local ok_doc, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, path)
    if not ok_doc or not doc then return nil end
    local ok_load = true
    if doc.loadDocument then ok_load = pcall(doc.loadDocument, doc, false) end
    local ok_cover, cover_bb = false, nil
    if ok_load and doc.getCoverPageImage then
        ok_cover, cover_bb = pcall(doc.getCoverPageImage, doc)
    end
    if not ok_cover or not cover_bb then
        if doc.close then pcall(doc.close, doc) end
        return nil
    end
    local target_bb
    local ok_target = pcall(function()
        target_bb = BB.new(w, h, cover_bb:getType())
        target_bb:fill(BB.COLOR_WHITE)
        local scaler = ImageWidget:new{
            image = cover_bb, image_disposable = false,
            width = w, height = h,
        }
        scaler:paintTo(target_bb, 0, 0)
        if scaler.free then scaler:free() end
    end)
    if doc.close then pcall(doc.close, doc) end
    if cover_bb.free then pcall(cover_bb.free, cover_bb) end
    if not ok_target or not target_bb then return nil end
    return ImageWidget:new{ image = target_bb, width = w, height = h, scale_factor = 1 }
end

local function rlReferenceMetrics(bb, p, items, top, bottom)
    top = top or 789
    bottom = bottom or 910
    local cell = 222
    for i, item in ipairs(items) do
        local cx = 62 + (i - 1) * cell
        if i > 1 then p.L(cx - 12, top + 8, cx - 12, bottom - 8, BB.COLOR_GRAY_B, 1) end
        rlMetricIcon(bb, item[4], p.X(cx), p.Y(top + 14), math.max(28, math.floor(48 * p.ui_s)))
        p.T(item[1], cx + 47, top + 11, 8, false, 135, BB.COLOR_BLACK)
        p.T(item[2], cx + 47, top + 31, 10, false, 135, BB.COLOR_DARK_GRAY)
        p.T(item[3], cx + 3, top + 68, 25, true, 184, BB.COLOR_BLACK)
        if i == 1 then p.T("↗", cx + 176, top + 12, 8, true, 20, BB.COLOR_DARK_GRAY) end
    end
end

local function rlReferenceFooter(bb, p, seed, caption, period_nav)
    local barcode_x, barcode_y = p.X(145), p.Y(920)
    local barcode_w = math.floor(716 * p.s)
    local barcode_h = math.max(12, math.floor(58 * p.ui_s))

    if period_nav then
        bb:paintRect(barcode_x, barcode_y, barcode_w, barcode_h, BB.COLOR_WHITE)
        local code = 0
        for i = 1, #seed do
            code = (code + seed:byte(i) * i) % 17
        end
        local cursor = barcode_x + 2
        while cursor < barcode_x + barcode_w - 2 do
            code = (code * 13 + 7) % 17
            local bar_sizes = { 2, 4, 7, 3, 11, 5, 8, 2, 13, 6 }
            local gap_sizes = { 6, 11, 7, 15, 9, 5, 13 }
            local bar = bar_sizes[(code % #bar_sizes) + 1]
            local gap = gap_sizes[((code * 3) % #gap_sizes) + 1]
            bb:paintRect(cursor, barcode_y + 2, bar, barcode_h - 4, BB.COLOR_BLACK)
            cursor = cursor + bar + gap
        end
        p.CT(caption or "READING LINE", 145, 988, 716, 9, false, BB.COLOR_DARK_GRAY)
    end
end

local function rlEllipsize(text, max_chars)
    text = tostring(text or "")
    local chars = utf8Chars(text)
    max_chars = math.max(2, tonumber(max_chars) or 8)
    if #chars <= max_chars then return table.concat(chars) end
    local out = {}
    for i = 1, max_chars - 1 do out[#out + 1] = chars[i] end
    return table.concat(out) .. "…"
end

local function rlFormatWords(words)
    words = math.max(0, math.floor((tonumber(words) or 0) + .5))
    if words >= 10000 then
        local value = string.format("%.1f", words / 10000):gsub("%.0$", "")
        return value .. " 万字"
    end
    return tostring(words) .. " 字"
end

-- 日历周计算（用于月票书籍跨度条）
local function rlCalendarWeeks(year, month, days, first_wday, per_day, lane_count)
    lane_count = lane_count or 3
    local weeks = {}
    for week_index = 1, 6 do
        local week = {days_books = {}}
        local previous_day_books
        for col = 1, 7 do
            local slot = (week_index - 1) * 7 + col - 1
            local day_num = slot - first_wday + 1
            local read_books = {}
            if day_num >= 1 and day_num <= days then
                local key = string.format("%04d-%02d-%02d", year, month, day_num)
                read_books = per_day[key] or {}
            end
            local this_day_books = {}
            week.days_books[col] = this_day_books
            for lane = 1, lane_count do
                local source = read_books[lane]
                if source then
                    this_day_books[lane] = { id = source.id, title = source.title, span_days = 1, start_day = col, fixed = false }
                else
                    this_day_books[lane] = false
                end
            end
            if previous_day_books then
                for previous_lane = 1, lane_count do
                    local previous_book = previous_day_books[previous_lane]
                    if previous_book then
                        for this_lane = 1, lane_count do
                            local this_book = this_day_books[this_lane]
                            if this_book and this_book.id == previous_book.id then
                                this_book.start_day = previous_book.start_day
                                this_book.fixed = true
                                this_book.span_days = previous_book.span_days + 1
                                for back = 1, previous_book.span_days do
                                    local older = week.days_books[col - back][previous_lane]
                                    if older then older.span_days = this_book.span_days end
                                end
                                if this_lane ~= previous_lane then
                                    this_day_books[this_lane], this_day_books[previous_lane] = this_day_books[previous_lane], this_day_books[this_lane]
                                end
                                break
                            end
                        end
                    end
                end
            end
            previous_day_books = this_day_books
        end
        weeks[week_index] = week
    end
    return weeks
end

-- 书籍日历数据查询（月票跨度条用）
local function readingCalendarBooks(year, month)
    local per_day = {}
    local ok, err = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
        local stmt = conn:prepare([[
            SELECT
                strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
                sum(duration) durations,
                id_book book_id,
                title book_title
            FROM (
                SELECT start_time, duration, page_stat.id_book, book.title
                FROM page_stat
                JOIN book ON book.id = page_stat.id_book
                WHERE start_time BETWEEN strftime('%s', ?, 'utc')
                                     AND strftime('%s', ?, 'utc', '+33 days', 'start of month', '-1 second')
            )
            GROUP BY
                strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
                id_book,
                title
            ORDER BY day, durations DESC, book_id, book_title;
        ]])
        local month_key = string.format("%04d-%02d-01", year, month)
        local res, count = stmt:reset():bind(month_key, month_key):resultset("i")
        stmt:close()
        conn:close()
        for i = 1, count do
            local day, book_id, book_title = res[1][i], res[3][i], res[4][i]
            if day then
                per_day[day] = per_day[day] or {}
                per_day[day][#per_day[day] + 1] = { id = tonumber(book_id) or 0, title = tostring(book_title or "未知书籍") }
            end
        end
    end)
    if not ok then logger.err(LOG_TAG, "calendar query failed:", tostring(err)) end
    return per_day, ok
end

-- ============================================================
-- 导出
-- ============================================================

-- 字体自动复制（历史逻辑，保留无害）：若 assets 自带字体则复制到 fonts/；当前 assets 无字体文件，自动跳过
do
    local font_src = PLUGIN_DIR .. "/../assets/" .. PLUGIN_FONT_NAME
    local font_dest = FontList.fontdir .. "/" .. PLUGIN_FONT_NAME
    if lfs.attributes(font_src, "mode") == "file" and not lfs.attributes(font_dest, "mode") then
        local src_f = io.open(font_src, "rb")
        if src_f then
            local content = src_f:read("*a")
            src_f:close()
            local dest_f = io.open(font_dest, "wb")
            if dest_f then
                dest_f:write(content)
                dest_f:close()
                logger.info(LOG_TAG, "已复制字体到", font_dest)
            else
                logger.warn(LOG_TAG, "字体写入失败：", font_dest)
            end
        end
    end
end

return {
    -- 字体工具
    getFontFace = getFontFace,
    simpleUIFontFace = simpleUIFontFace,
    utf8Chars = utf8Chars,

    -- 文本绘制
    drawText = drawText,
    measureText = measureText,
    measureTextH = measureTextH,
    truncateToWidth = truncateToWidth,
    drawPluginIcon = rlMetricIcon,
    getBookCoverFromPath = getBookCoverFromPath,

    -- 时间/日期
    rlTime = rlTime,
    rlDate = rlDate,
    rlWeekday = rlWeekday,
    rlDayStart = rlDayStart,
    rlWeekStart = rlWeekStart,
    rlMonthStart = rlMonthStart,
    rlYearStart = rlYearStart,

    -- 数据读取
    readReadingData = readReadingData,
    readReadingDataForDay = readReadingDataForDay,
    readReadingDataForWeek = readReadingDataForWeek,
    readReadingDataForMonth = readReadingDataForMonth,
    readReadingDataForYear = readReadingDataForYear,
    readReadingDataAll = readReadingDataAll,

    -- 数据统计
    rlBoardings = rlBoardings,
    rlAggregate = rlAggregate,
    rlFinishedCount = rlFinishedCount,

    -- 渲染工具
    rlPaintTicketNotches = rlPaintTicketNotches,
    rlReferencePainter = rlReferencePainter,
    rlReferenceFrame = rlReferenceFrame,
    rlReferenceMetrics = rlReferenceMetrics,
    rlReferenceFooter = rlReferenceFooter,
    rlEllipsize = rlEllipsize,
    rlFormatWords = rlFormatWords,

    -- 日历工具
    rlCalendarWeeks = rlCalendarWeeks,
    readingCalendarBooks = readingCalendarBooks,
}
