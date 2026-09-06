-- station.lua - 站台样式（阅读主页）
-- 完全移植自补丁 paintHomeStation，展示四个板块：正在阅读/最近停靠/本周线路/本月月台
-- 修复：移除所有未定义的 self:home* 方法调用，改为与补丁一致的独立实现

local BB = require("ffi/blitbuffer")
local Blitbuffer = BB
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local rl = require("lib.rl_reference")
local font_pref = require("lib.font_pref")

local LOG_TAG = "[BookReceipt.Station]"

-- ============================================================
-- 工具函数（移植自补丁）
-- ============================================================

-- 时间格式化（中文输出）
local function homeDuration(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local hours, minutes = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if hours > 0 then return string.format("%d小时%d分", hours, minutes) end
    if minutes > 0 then return string.format("%d分", minutes) end
    return "0分"
end

-- 文本截断（UTF-8安全）
local function homeShortText(value, limit)
    local str = tostring(value or "")
    local chars = rl.utf8Chars(str)
    if #chars <= limit then return table.concat(chars) end
    local result = {}
    for i = 1, math.max(1, limit - 1) do result[#result + 1] = chars[i] end
    return table.concat(result) .. "\226\128\166"
end

-- 居中绘制文本（测量版）
local function drawCenteredTextMeasured(bb, value, x, y, size, bold, width, color)
    value = tostring(value or "")
    size = math.max(6, math.floor(size or 12))
    local widget, measured
    for _ = 1, 2 do
        widget = TextWidget:new{
            text = value,
            face = rl.getFontFace(size),
            bold = bold,
            fgcolor = color or BB.COLOR_BLACK
        }
        measured = widget:getSize()
        if measured and measured.w and measured.w > width and size > 6 then
            widget:free()
            size = math.max(6, math.floor(size * width / measured.w))
            widget = nil
        else
            break
        end
    end
    if not widget then
        widget = TextWidget:new{
            text = value,
            face = rl.getFontFace(size),
            bold = bold,
            fgcolor = color or BB.COLOR_BLACK
        }
        measured = widget:getSize()
    end
    local actual_x = math.floor(x + (width - (measured and measured.w or 0)) / 2)
    rl.drawText(bb, value, actual_x, y, size, bold, nil, color)
    if widget then widget:free() end
end

-- 右对齐绘制文本（测量版：超宽缩字号，与原插件 drawRightAlignedTextMeasured 一致）
local function drawRightAlignedTextMeasured(bb, value, x, y, size, bold, width, color)
    value = tostring(value or "")
    size = math.max(6, math.floor(size or 12))
    local widget, measured
    for _ = 1, 2 do
        widget = TextWidget:new{
            text = value,
            face = rl.getFontFace(size),
            bold = bold,
            fgcolor = color or BB.COLOR_BLACK
        }
        measured = widget:getSize()
        if measured and measured.w and measured.w > width and size > 6 then
            widget:free()
            size = math.max(6, math.floor(size * width / measured.w))
            widget = nil
        else
            break
        end
    end
    if not widget then
        widget = TextWidget:new{
            text = value,
            face = rl.getFontFace(size),
            bold = bold,
            fgcolor = color or BB.COLOR_BLACK
        }
        measured = widget:getSize()
    end
    local actual_x = math.floor(x - (measured and measured.w or 0))
    rl.drawText(bb, value, actual_x, y, size, bold, nil, color)
    if widget then widget:free() end
end

-- 获取书籍封面（covers 缓存优先，缺失时从书文件提取，与原插件链路一致）
local function getBookCoverWidget(path, w, h)
    if not path or path == "" then return nil end
    local cover_path = DataStorage:getDataDir() .. "covers/" .. string.gsub(path, "[/\\:]", "_") .. ".jpg"
    if lfs.attributes(cover_path, "mode") then
        local ok, widget = pcall(function()
            return ImageWidget:new{file=cover_path, width=math.max(1, w), height=math.max(1, h), scale_factor=1}
        end)
        if ok and widget then return widget end
    end
    local ok, widget = pcall(rl.getBookCoverFromPath, path, w, h)
    if ok and widget then return widget end
    return nil
end

-- 获取书脊封面（用于最近停靠区，提取链路同上）
local function getBookSpineWidget(path, w, h)
    if not path or path == "" then return nil end
    local cover_path = DataStorage:getDataDir() .. "covers/" .. string.gsub(path, "[/\\:]", "_") .. ".jpg"
    if lfs.attributes(cover_path, "mode") then
        local ok, widget = pcall(function()
            return ImageWidget:new{file=cover_path, width=math.max(1, w), height=math.max(1, h), scale_factor=1}
        end)
        if ok and widget then return widget end
    end
    local ok, widget = pcall(rl.getBookCoverFromPath, path, w, h)
    if ok and widget then return widget end
    return nil
end

-- ============================================================
-- 数据获取（完全移植自补丁，书名从 SQL 直接获取）
-- ============================================================

-- 统计快照（从补丁移植，不依赖 DocumentRegistry）
local function computeHomeStatisticsSnapshot(day_ts)
    day_ts = day_ts or os.time()
    local today_start = rl.rlDayStart(day_ts)
    local week_start = rl.rlWeekStart(day_ts)
    local month_start = rl.rlMonthStart(day_ts)
    local month_end = os.time{year=os.date("*t", month_start + 30*86400).year, month=os.date("*t", month_start + 30*86400).month, day=1, hour=0, min=0, sec=0}
    
    local rows = rl.readReadingData(week_start, month_end)
    local stats = {pages=0, total_seconds=0, visits=0, authors="", week={}, month={}, today_seconds=0}
    
    for _, row in ipairs(rows or {}) do
        local seconds = math.max(0, tonumber(row.duration) or 0)
        local row_day = os.date("*t", row.time)
        
        -- 本周统计
        if row.time >= week_start and row.time < week_start + 7 * 86400 then
            local slot = math.floor((row.time - week_start) / 86400) + 1
            stats.week[slot] = (stats.week[slot] or 0) + seconds
        end
        
        -- 本月统计
        if row.time >= month_start and row.time < month_end then
            stats.month[row_day.day] = (stats.month[row_day.day] or 0) + seconds
        end
        
        -- 今日统计
        if row.time >= today_start and row.time < today_start + 86400 then
            stats.today_seconds = stats.today_seconds + seconds
        end
        
        stats.total_seconds = stats.total_seconds + seconds
        stats.visits = stats.visits + 1
    end
    
    return stats
end

-- 构建 书名→文件路径 映射（遍历阅读历史，用 CoverBrowser 书库信息反查书名）
-- 全程 pcall 保护，CoverBrowser 不存在时退化为文件名匹配
local function buildTitlePathMap()
    local map = {}
    local ok_rh, readhistory = pcall(require, "readhistory")
    if not ok_rh or not readhistory or not readhistory.hist then return map end
    local ok_bim, BIM = pcall(require, "bookinfomanager")
    if not ok_bim then ok_bim, BIM = pcall(require, "plugins/coverbrowser.koplugin/bookinfomanager") end
    for _, entry in ipairs(readhistory.hist or {}) do
        local file = entry and entry.file
        if file and file ~= "" then
            local title
            if ok_bim and BIM and BIM.getBookInfo then
                local ok_info, info = pcall(BIM.getBookInfo, BIM, file, true)
                if ok_info and info then title = info.title end
            end
            if not title or title == "" then
                local base = tostring(file):match("^.*/([^/]+)$") or tostring(file)
                title = base:match("^(.+)%.[^%.]+$") or base
            end
            if title and title ~= "" and not map[title] then map[title] = file end
        end
    end
    return map
end

-- 获取书籍列表（从 SQL 数据库直接取书名，避免 DocumentRegistry 的沉重开销）
-- 这是原补丁的正确实现方式：直接从 statistics.sqlite3 读取 title 字段
-- title_path_map（可选）：书名→文件路径映射，用于封面提取
local function getBookList(title_path_map)
    local books = {}
    -- 从 rl_reference 读取全部阅读记录，直接获取 title
    local ok, rows = pcall(rl.readReadingDataAll)
    if not ok or not rows then
        logger.warn(LOG_TAG, "无法读取阅读数据")
        return books
    end
    -- 按时间分组，取每本书最新一条
    local latest = {}
    for _, row in ipairs(rows) do
        local book_id = row.id
        local last_ts = (latest[book_id] and latest[book_id].time or 0)
        if row.time and row.time > last_ts then
            latest[book_id] = {
                path = title_path_map and title_path_map[row.title or ""] or nil,  -- 用于封面提取
                title = row.title or "",  -- 书名直接从 SQL 获取，保证正确显示
                authors = row.authors or "",
                percent = 0,
                last_read = row.time,
            }
        end
    end
    for __, info in pairs(latest) do
        books[#books + 1] = info
    end
    table.sort(books, function(a, b)
        return (tonumber(a.last_read) or 0) > (tonumber(b.last_read) or 0)
    end)
    return books
end

-- 获取当前正在阅读的书（最近阅读的那本）
local function getCurrentBook(books)
    if not books or #books == 0 then return nil end
    -- 按最后阅读时间排序，取第一本
    local sorted = {}
    for _, book in ipairs(books) do
        sorted[#sorted + 1] = book
    end
    table.sort(sorted, function(a, b)
        return (tonumber(a.last_read) or 0) > (tonumber(b.last_read) or 0)
    end)
    return sorted[1]
end

-- ============================================================
-- 站台样式主渲染函数（完全移植自补丁 paintHomeStation）
-- 关键修复：移除所有 self:home* 方法调用
-- ============================================================

local function paintHomeStation(bb, x, y, width, height, books, ref_date, current_path, current_title)
    ref_date = ref_date or os.time()
    local ref_w, ref_h = 1040, 1141
    local sx, sy = (width - 20) / ref_w, (height - 10) / ref_h
    local ox, oy = x + 10, y + 5
    local compact_home = width <= 1300 and height <= 1650
    local font_s = compact_home and math.min(1.10, sx, sy) or math.min(1, sx, sy)
    
    local function X(v) return math.floor(ox + v * sx) end
    local function Y(v) return math.floor(oy + v * sy) end
    local function W(v) return math.max(1, math.floor(v * sx)) end
    local function Ht(v) return math.max(1, math.floor(v * sy)) end
    local function F(v)
        local size = math.floor(v * font_s)
        if compact_home and v <= 9 then size = size + 1 end
        return math.max(6, size)
    end
    local function R(px,py,pw,ph,c) bb:paintRect(X(px),Y(py),W(pw),Ht(ph),c) end
    local function HR(px,py,pw,t,c) R(px,py,pw,t or 1,c or BB.COLOR_BLACK) end
    local function VR(px,py,ph,t,c) R(px,py,t or 1,ph,c or BB.COLOR_BLACK) end
    local function T(s,px,py,size,bold,maxw,c) rl.drawText(bb,tostring(s or ""),X(px),Y(py),F(size),bold,maxw and W(maxw) or nil,c or BB.COLOR_BLACK) end
    local function CT(s,px,py,pw,size,bold,c) drawCenteredTextMeasured(bb,tostring(s or ""),X(px),Y(py),F(size),bold,W(pw),c or BB.COLOR_BLACK) end
    local function RT(s,right,py,pw,size,bold,c) drawRightAlignedTextMeasured(bb,tostring(s or ""),X(right),Y(py),F(size),bold,W(pw),c or BB.COLOR_BLACK) end
    local function C(cx,cy,r,c)
        local rr=math.max(2,math.floor(r*math.min(sx,sy)))
        if bb.paintCircle then pcall(bb.paintCircle,bb,X(cx),Y(cy),rr,c) else R(cx-r,cy-r,r*2,r*2,c) end
    end
    local function L(x1,y1,x2,y2,t,c)
        local steps=math.max(1,math.floor(math.max(math.abs(x2-x1),math.abs(y2-y1))/2))
        for i=0,steps do local q=i/steps; R(x1+(x2-x1)*q,y1+(y2-y1)*q,t or 1.4,t or 1.4,c or BB.COLOR_BLACK) end
    end
    local function barcode(px,py,pw,ph)
        local at,n=px,1
        while at<px+pw do local bw=(n%7==0 and 4) or (n%3==0 and 2) or 1; R(at,py,bw,ph,BB.COLOR_BLACK); at=at+bw+(n%4==0 and 3 or 2); n=n+1 end
    end
    local function dashed(px,py,pw,ph,c)
        for n=0,math.floor(pw/10) do if n%2==0 then HR(px+n*10,py,8,1,c); HR(px+n*10,py+ph,8,1,c) end end
        for n=0,math.floor(ph/10) do if n%2==0 then VR(px,py+n*10,8,1,c); VR(px+pw,py+n*10,8,1,c) end end
    end
    local function calendarIcon(px,py)
        R(px,py+3,21,19,BB.COLOR_WHITE); HR(px,py+3,21,1,BB.COLOR_BLACK); HR(px,py+9,21,1,BB.COLOR_BLACK); HR(px,py+21,21,1,BB.COLOR_BLACK); VR(px,py+3,19,1,BB.COLOR_BLACK); VR(px+20,py+3,19,1,BB.COLOR_BLACK); VR(px+5,py,6,2,BB.COLOR_BLACK); VR(px+15,py,6,2,BB.COLOR_BLACK)
    end
    local function metricIcon(kind,px,py)
        if kind==1 then C(px+9,py+9,8,BB.COLOR_BLACK); C(px+9,py+9,5,BB.COLOR_WHITE); L(px+9,py+9,px+9,py+3,1,BB.COLOR_BLACK); L(px+9,py+9,px+14,py+12,1,BB.COLOR_BLACK)
        elseif kind==2 then HR(px+2,py,15,2,BB.COLOR_BLACK); HR(px+2,py+18,15,2,BB.COLOR_BLACK); L(px+4,py+2,px+15,py+17,1.5,BB.COLOR_BLACK); L(px+15,py+2,px+4,py+17,1.5,BB.COLOR_BLACK)
        elseif kind==3 then calendarIcon(px,py)
        else VR(px+2,py+2,18,2,BB.COLOR_BLACK); VR(px+16,py+2,18,2,BB.COLOR_BLACK); HR(px+4,py+3,12,1,BB.COLOR_BLACK); HR(px+4,py+19,12,1,BB.COLOR_BLACK); VR(px+9,py+2,18,1,BB.COLOR_GRAY_8) end
    end
    local ink,paper,pale,mid,dark=BB.COLOR_BLACK,BB.COLOR_WHITE,BB.COLOR_GRAY_E,BB.COLOR_GRAY_8,BB.COLOR_GRAY_3
    R(0,0,ref_w,ref_h,paper)

    -- 整理书籍列表（从 SQL 直接获取书名，避免乱码）
    local book_list = books
    if not book_list then
        local title_map = buildTitlePathMap()
        -- 当前书保底：阅读历史反查不到时，用调用方传入的当前书信息兜底
        if current_path and current_title and current_title ~= "" and not title_map[current_title] then
            title_map[current_title] = current_path
        end
        book_list = getBookList(title_map)
    end
    local recent = {}
    for _, book in ipairs(book_list) do
        recent[#recent + 1] = book
    end
    table.sort(recent, function(a,b) return (tonumber(a.last_read) or 0) > (tonumber(b.last_read) or 0) end)
    
    local current = getCurrentBook(recent)
    local stats = computeHomeStatisticsSnapshot(ref_date)
    
    -- 固定四个板块（不依赖 self:homeBoardSlots）
    local board_slots = {"current", "recent", "week", "month"}
    
    -- ============================================================
    -- 头部装饰区（完全移植自 readingline paintHomeV4）
    -- ============================================================
    R(0,0,54,ref_h,dark); R(993,0,47,ref_h,dark)
    for groove=0,4 do R(5+groove*10,0,5,ref_h,groove%2==0 and BB.COLOR_GRAY_6 or BB.COLOR_GRAY_2) end
    for groove=0,4 do R(995+groove*9,0,4,ref_h,groove%2==0 and BB.COLOR_GRAY_6 or BB.COLOR_GRAY_2) end
    for course=1,7 do HR(0,course*32,54,1,BB.COLOR_GRAY_6); HR(993,course*32,47,1,BB.COLOR_GRAY_6) end
    R(80,0,890,253,pale); HR(80,8,890,11,ink)
    local center=520
    for px=80,970,3 do local q=(px-center)/440; local outer=18+q*q*82; local inner=39+q*q*67; R(px,outer,4,math.max(4,inner-outer),ink); R(px,inner+3,4,4,BB.COLOR_GRAY_7) end
    for px=150,890,72 do local q=(px-center)/440; local ay=18+q*q*82; L(px,0,px+24,ay,2,ink); C(px+24,ay,3,ink) end
    for _,px in ipairs({96,125,886,915}) do R(px-5,66,23,8,ink); R(px,74,13,166,BB.COLOR_GRAY_2); R(px+4,74,5,166,BB.COLOR_GRAY_7); R(px-6,230,25,8,ink) end
    local function romanCornerColumn(cx)
        R(cx-20,88,40,5,ink); R(cx-16,93,32,5,BB.COLOR_GRAY_4); R(cx-12,98,24,7,ink)
        C(cx-15,98,6,ink); C(cx+15,98,6,ink); C(cx-15,98,3,pale); C(cx+15,98,3,pale)
        R(cx-10,105,20,119,BB.COLOR_GRAY_4); R(cx-7,105,3,119,BB.COLOR_GRAY_8); R(cx-1,105,3,119,BB.COLOR_GRAY_8); R(cx+5,105,3,119,BB.COLOR_GRAY_8)
        R(cx-13,224,26,6,ink); R(cx-18,230,36,6,BB.COLOR_GRAY_4); R(cx-22,236,44,7,ink)
    end
    romanCornerColumn(160); romanCornerColumn(948)
    HR(80,238,143,8,ink); HR(817,238,153,8,ink)
    VR(43,0,24,3,ink); VR(115,0,24,3,ink); VR(925,0,24,3,ink); VR(997,0,24,3,ink)
    R(13,19,132,131,ink); R(18,24,122,121,BB.COLOR_GRAY_2); R(895,19,132,131,ink); R(900,24,122,121,BB.COLOR_GRAY_2)
    HR(23,30,112,1,BB.COLOR_GRAY_8); HR(905,30,112,1,BB.COLOR_GRAY_8); HR(23,139,112,1,BB.COLOR_GRAY_8); HR(905,139,112,1,BB.COLOR_GRAY_8)
    for _,dot in ipairs({{25,31},{133,31},{25,137},{133,137},{907,31},{1015,31},{907,137},{1015,137}}) do C(dot[1],dot[2],2,paper) end
    CT("PLATFORM",18,48,122,10,false,paper); CT("01",18,79,122,30,true,paper); CT("PLATFORM",900,48,122,10,false,paper); CT("01",900,79,122,30,true,paper)
    VR(53,145,8,2,ink); VR(91,145,8,2,ink); VR(949,145,8,2,ink); VR(987,145,8,2,ink)
    R(29,146,86,82,ink); R(34,151,76,72,BB.COLOR_GRAY_2); R(925,146,86,82,ink); R(930,151,76,72,BB.COLOR_GRAY_2)
    HR(39,157,66,1,BB.COLOR_GRAY_8); HR(935,157,66,1,BB.COLOR_GRAY_8); CT("ENTRY",34,166,76,8,false,paper); CT("→",34,187,76,20,true,paper); CT("TO READ",930,166,76,7,false,paper); CT("→",930,187,76,20,true,paper)
    C(center,91,78,ink); C(center,91,69,paper); C(center,91,63,ink); C(center,91,59,paper)
    local romans={"XII","I","II","III","IV","V","VI","VII","VIII","IX","X","XI"}
    for i,label in ipairs(romans) do local a=(i-1)*math.pi/6-math.pi/2; CT(label,center+math.cos(a)*44-13,91+math.sin(a)*44-5,26,7,true) end
    local clock=os.date("*t"); local minute=(clock.min or 0)+(clock.sec or 0)/60; local hour=((clock.hour or 0)%12)+minute/60
    local minute_angle=minute*math.pi/30-math.pi/2; local hour_angle=hour*math.pi/6-math.pi/2
    L(center,91,center+math.cos(hour_angle)*31,91+math.sin(hour_angle)*31,2.4,ink)
    L(center,91,center+math.cos(minute_angle)*43,91+math.sin(minute_angle)*43,1.8,ink)
    C(center,91,6,ink); C(center,91,2,paper)
    CT("HOME STATION",270,158,500,29,true,ink); HR(165,215,286,1,mid); HR(589,215,286,1,mid); CT("阅读主页",452,205,136,13,true,ink)

    -- Header ticket
    local ty=253
    R(80,ty,890,99,pale); HR(80,ty,890,1,ink); HR(80,ty+98,890,1,ink); VR(280,ty,99,1,mid); VR(679,ty,99,1,mid); C(80,ty+50,7,paper); C(970,ty+50,7,paper)
    calendarIcon(109,ty+39); T("TODAY",140,ty+18,8,false); T(os.date("%m.%d", ref_date),140,ty+44,18,false); T("已阅读 "..homeDuration(stats.today_seconds),140,ty+72,8,false,nil,mid)
    rl.drawPluginIcon(bb,"03-train-front.svg",X(302),Y(ty+37),W(22)); T("DESTINATION",340,ty+20,8,false); T("阅读，是一场抵达内心的旅行。",340,ty+49,9,false,300)
    T("TICKET NO.",696,ty+17,8,false); T(os.date("%m%Y").."-"..os.date("%d", ref_date),696,ty+41,15,false); barcode(696,ty+70,186,15)
    local battery=0; pcall(function() battery=tonumber(Device:getPowerDevice():getCapacity()) or 0 end); R(894,ty+25,22,12,ink); R(897,ty+28,16,6,paper); R(916,ty+29,3,4,ink); T(tostring(battery).."%",924,ty+22,11,true,36)

    -- 本地化辅助函数
    local function twoLines(value,limit)
        local chars=rl.utf8Chars(tostring(value or "")); local first,second={},{}
        for i,ch in ipairs(chars) do if i<=limit then first[#first+1]=ch elseif i<=limit*2 then second[#second+1]=ch end end
        if #chars>limit*2 then second[#second+1]="…" end
        return table.concat(first),table.concat(second)
    end

    -- 收集可点击区域
    local hit_books = {}
    local action_hits = {}  -- 按钮点击区域（CONTINUE 等），参照原插件 home_action_hits 架构

    -- 注册动作区域的辅助函数（与原插件 addAction 一致）
    local function addAction(px, py, pw, ph, callback)
        action_hits[#action_hits + 1] = {x=X(px), y=Y(py), w=W(pw), h=Ht(ph), callback=callback}
    end

    -- 板块渲染函数
    local board_labels = {
        current={"正在阅读", "CURRENT READING"}, recent={"最近停靠", "RECENT STOPS"},
        week={"本周线路", "WEEKLY LINE"}, month={"本月月台", "MONTH PLATFORM"},
    }
    local function boardHeader(key, py)
        local labels=board_labels[key]
        rl.drawPluginIcon(bb,"03-train-front.svg",X(94),Y(py+6),W(22))
        T(labels[1],124,py+8,10,true)
        T("· "..labels[2],212,py+12,7,false)
        HR(94,py+31,862,1,mid)
    end

    local function renderCurrentPanel(py,ph)
        R(80,py,890,ph,pale); boardHeader("current",py)
        if not current then CT("还没有正在阅读的书",180,py+math.floor(ph*.48),680,12,false,mid); return end
        local growth=math.max(1,math.min(1.60,ph/265))
        local metrics_h=ph>=220 and math.floor(math.max(62,math.min(125,ph*.22))) or 0
        local bottom_pad=ph>=350 and math.floor(math.max(10,math.min(24,ph*.035))) or 5
        local metric_y=py+ph-bottom_pad-metrics_h
        local body_top=py+40; local body_bottom=metric_y-8
        local body_h=math.max(72,body_bottom-body_top)
        local cover_h=math.max(68,math.min(320,math.floor(body_h*.72))); local cover_w=math.floor(cover_h*.72)
        local cover_x=94; local cover_y=body_top+math.max(0,math.floor((body_h-cover_h)/2))
        local cw,ch=W(cover_w),Ht(cover_h)
        local cover=getBookCoverWidget(current.path,cw,ch,"center",true)
        if cover then cover:paintTo(bb,X(cover_x),Y(cover_y)); if cover.free then cover:free() end end
        local continue_w=ph>=145 and 132 or 0
        local text_x=cover_x+cover_w+20; local text_right=continue_w>0 and 805 or 950
        local title_size=math.floor((ph>=250 and 19 or (ph>=180 and 16 or 13))*math.min(1.32,growth))
        local title_y=cover_y+10
        T(homeShortText(current.title or "未命名书籍",20),text_x,title_y,title_size,true,text_right-text_x-12)
        local authors=tostring(current.authors or ""); if authors=="" then authors=stats.authors end
        local author_size=math.floor(9*math.min(1.18,growth))
        local author_y=title_y+math.floor(title_size*1.55)+7
        if body_h>=110 then T(homeShortText(authors,35),text_x,author_y,author_size,false,text_right-text_x-12) end
        local pct=math.max(0,math.min(100,math.floor((tonumber(current.percent) or 0)*100+.5)))
        local pages=stats.pages>0 and stats.pages or 0; local current_page=pages>0 and math.floor(pages*pct/100+.5) or 0
        local progress_y=cover_y+cover_h-8
        T("当前进度",text_x,progress_y-22,8,false); RT(tostring(pct).."%",text_right-4,progress_y-30,60,15,true)
        HR(text_x,progress_y,text_right-text_x,1,ink); HR(text_x,progress_y+7,text_right-text_x,1,ink)
        if pct>0 then R(text_x,progress_y+1,(text_right-text_x)*pct/100,6,ink) end
        if pages>0 then RT(tostring(current_page).." / "..tostring(pages).." 页",text_right,progress_y+10,110,7,false,mid) end
        if continue_w>0 then
            VR(810,body_top,body_h,1,mid); local box_h=math.min(96,body_h-22); local box_y=cover_y+math.max(4,math.floor((cover_h-box_h)/2))
            dashed(825,box_y,132,box_h,mid); CT("CONTINUE",825,box_y+12,132,8,false); CT("继续阅读",825,box_y+32,132,9,true); CT("▶",825,box_y+52,132,17,true)
            -- 注册 CONTINUE 按钮点击区域（参照原插件 addAction 架构）
            if current and current.path and current.path ~= "" then
                addAction(825, box_y, 132, box_h, function()
                    local Utils = require("frontend/ui/utils")
                    Utils.openBookThroughFileManager(nil, current.path)
                end)
            end
        end
        table.insert(hit_books, {x=X(cover_x),y=Y(cover_y),w=W(text_right-cover_x),h=Ht(cover_h),book=current})
        if metrics_h>0 then
            HR(94,py+ph-metrics_h,862,1,mid)
            local remaining=(pct>0 and pct<100) and stats.total_seconds*(100-pct)/pct or 0
            local metrics={{"已读时长",homeDuration(stats.total_seconds),"READING TIME"},{"预计剩余",homeDuration(remaining),"LEFT TIME"},{"阅读次数",tostring(stats.visits).." 次","VISITS"},{"总页数",pages>0 and tostring(pages).." 页" or "—","PAGES"}}
            local metric_value_size=metrics_h>=110 and 17 or (metrics_h>=80 and 14 or 12)
            local metric_label_size=metrics_h>=110 and 10 or (metrics_h>=80 and 9 or 8)
            local value_y=metric_y+math.floor(metrics_h*.22); local label_y=metric_y+math.floor(metrics_h*.58)
            for i,item in ipairs(metrics) do local mx=103+(i-1)*219; if i>1 then VR(mx-15,metric_y+10,metrics_h-20,1,mid) end; metricIcon(i,mx,value_y+2); T(item[2],mx+29,value_y,metric_value_size,true,140); T(item[3].." · "..item[1],mx+29,label_y,metric_label_size,false,170,mid) end
        end
    end

    local function renderRecentPanel(py,ph)
        R(80,py,890,ph,pale); boardHeader("recent",py); T("查看更多 →",888,py+12,8,false,68)
        local content_top=py+36; local content_bottom=py+ph-10
        local available_group_h=math.max(102,content_bottom-content_top)
        local group_h=math.min(230,available_group_h)
        local group_y=content_top+math.max(0,math.floor((available_group_h-group_h)/2))
        local card_h=math.max(82,group_h-20); local card_y=group_y
        local rail_y=card_y+card_h+6
        for i=1,math.min(5,#recent) do
            local book=recent[i]; local bx=111+(i-1)*168
            R(bx+4,card_y+5,158,card_h,BB.COLOR_GRAY_C); R(bx,card_y,158,card_h,paper)
            HR(bx,card_y,158,1,ink); HR(bx,card_y+card_h,158,1,ink); VR(bx,card_y,card_h,1,mid); VR(bx+157,card_y,card_h,1,mid)
            local image_h=math.max(34,card_h-75); local crop_w,crop_h=W(141),Ht(image_h)
            local cover=getBookSpineWidget(book.path,crop_w,crop_h,"center",true)
            if cover then cover:paintTo(bb,X(bx+8),Y(card_y+8)); if cover.free then cover:free() end end
            local pct=math.max(0,math.floor((tonumber(book.percent) or 0)*100+.5)); local info_y=card_y+card_h-35
            local title_y=info_y-20; CT(homeShortText(book.title or "",8),bx+9,title_y,140,8,true)
            T(tostring(pct).."%",bx+13,info_y,7,true); HR(bx+48,info_y+7,72,2,mid); if pct>0 then HR(bx+48,info_y+7,72*pct/100,2,ink) end
            if card_h>=112 and tonumber(book.last_read) and book.last_read>0 then CT("停靠 "..os.date("%m.%d",book.last_read),bx+23,card_y+card_h-17,112,6,false,mid) end
            C(bx+29,rail_y,7,ink); C(bx+29,rail_y,3,paper); C(bx+129,rail_y,7,ink); C(bx+129,rail_y,3,paper)
            table.insert(hit_books, {x=X(bx),y=Y(card_y),w=W(158),h=Ht(card_h+8),book=book})
        end
        HR(103,rail_y,850,2,ink); HR(103,rail_y+7,850,1,mid)
    end

    local function renderWeekPanel(py,ph)
        R(80,py,890,ph,pale); boardHeader("week",py)
        local total,maxv=0,1; for i=1,7 do total=total+(stats.week[i] or 0); maxv=math.max(maxv,stats.week[i] or 0) end
        T("本周时长 "..homeDuration(total).." →",851,py+11,9,false,105)
        local top_blank=math.max(42,math.min(66,math.floor(ph*.08)))
        local bottom_blank=math.max(30,math.min(105,math.floor(ph*.13)))
        local timeline_y=py+ph-bottom_blank
        local graph_top=py+top_blank
        local graph_bottom=math.max(graph_top+20,timeline_y-43)
        local pts={}; for i=1,7 do pts[i]={x=104+(i-1)*140,y=graph_bottom-(graph_bottom-graph_top)*(stats.week[i] or 0)/maxv} end
        for i=2,7 do local a,b=pts[i-1],pts[i]; for px=a.x,b.x,3 do local q=(px-a.x)/(b.x-a.x); local gy=a.y+(b.y-a.y)*q; R(px,gy,2,graph_bottom-gy,BB.COLOR_GRAY_C) end; L(a.x,a.y,b.x,b.y,1.4,BB.COLOR_GRAY_4) end
        HR(103,graph_bottom,854,1,mid); HR(132,timeline_y,784,1,ink)
        for i=1,7 do local px=159+(i-1)*122; CT(({"周一","周二","周三","周四","周五","周六","周日"})[i],px-34,timeline_y-28,68,8,true); C(px,timeline_y,8,ink); C(px,timeline_y,4,(stats.week[i] or 0)>0 and ink or paper); CT(homeDuration(stats.week[i] or 0),px-38,timeline_y+13,76,7,false,mid) end
    end

    local function renderMonthPanel(py,ph)
        R(80,py,890,ph,pale); boardHeader("month",py)
        local read_days=0; for d=1,31 do if (stats.month[d] or 0)>0 then read_days=read_days+1 end end
        T("阅读天数 "..tostring(read_days).." →",870,py+10,9,false,86)
        local grid_h=math.max(45,ph-39); local row_gap=math.max(27,math.min(48,math.floor(grid_h/2))); local first_y=py+42+math.max(0,math.floor((grid_h-row_gap*2)/2))
        for day=1,31 do local col=(day-1)%21; local row=math.floor((day-1)/21); local bx=103+col*40; local by=first_y+row*row_gap; CT(tostring(day),bx-2,by-12,23,6,false); local fill=(stats.month[day] or 0)>0 and ((stats.month[day] or 0)>1800 and ink or BB.COLOR_GRAY_7) or paper; R(bx,by,19,19,fill); HR(bx,by,19,1,mid); HR(bx,by+18,19,1,mid); VR(bx,by,19,1,mid); VR(bx+18,by,19,1,mid) end
    end

    -- 渲染四个固定板块
    local area_y,area_h,gap=365,776,5
    local minimum={current=155,recent=145,week=120,month=110}
    local min_total=0
    for _,key in ipairs(board_slots) do min_total=min_total+(minimum[key] or 105) end
    local remaining=math.max(0,area_h-min_total)
    local weight_total=#board_slots
    local at=area_y; local used=0
    for index,key in ipairs(board_slots) do
        local ph
        if index==#board_slots then ph=area_h-used-gap*(#board_slots-1)
        else ph=(minimum[key] or 105)+math.floor(remaining/weight_total) end
        if key=="current" then renderCurrentPanel(at,ph)
        elseif key=="recent" then renderRecentPanel(at,ph)
        elseif key=="week" then renderWeekPanel(at,ph)
        elseif key=="month" then renderMonthPanel(at,ph) end
        at=at+ph+gap; used=used+ph
    end
    
    -- 返回可点击区域（参照原插件架构：hit_books=书籍, action_hits=按钮）
    return hit_books, action_hits
end

-- ============================================================
-- 构建 Widget（完全移植自补丁 buildStationWidget）
-- ============================================================

local function buildStationWidget(ui, books, ref_date, on_close_callback)
    ref_date = ref_date or os.time()
    
    -- 创建 BlitBuffer 画布
    local bb = BB.new(Screen:getWidth(), Screen:getHeight(), Screen.bb:getType())
    if not bb then
        logger.warn(LOG_TAG, "无法创建画布")
        return nil
    end

    -- 调用站台渲染函数（完全移植自补丁）
    -- 传入当前书路径/书名，供封面提取与路径映射兜底
    local current_path = (ui and ui.document and ui.document.file) or nil
    local current_title = (ui and ui.doc_props and ui.doc_props.display_title) or nil
    local hit_books, action_hits
    local ok, err = pcall(function()
        hit_books, action_hits = paintHomeStation(bb, 0, 0, Screen:getWidth(), Screen:getHeight(), books, ref_date, current_path, current_title)
    end)
    if not ok then
        logger.err(LOG_TAG, "站台渲染失败:", tostring(err))
        return nil
    end
    
    -- 创建图片 Widget（完全移植自补丁）
    local widget = ImageWidget:new{
        image = bb,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        scale_factor = 1,
    }
    -- 附加点击区域信息（供 quicklookbox:onTap 使用）
    widget.hit_books = hit_books
    widget.action_hits = action_hits

    -- 小花按钮 ✿：与墨痕/胶片同款交互（关闭当前界面 + 延迟广播阅读洞察事件）
    local screen_size = Screen:getSize()
    local badge_size = Screen:scaleBySize(40)
    local badge_btn = Button:new{
        text = "✿",
        text_face = Font:getFace("cfont", Screen:scaleBySize(18)),
        fg_color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = badge_size,
        height = badge_size,
        callback = function()
            if on_close_callback then on_close_callback() end
            UIManager:setDirty(nil, "full")
            -- 延迟广播，确保当前界面先完成关闭，避免事件被当前 widget 拦截
            UIManager:scheduleIn(0.25, function()
                local Event = require("ui/event")
                local InfoMessage = require("ui/widget/infomessage")
                local ok2, err2 = pcall(function()
                    UIManager:broadcastEvent(Event:new("ShowReadingInsightsPopup"))
                end)
                if not ok2 then
                    UIManager:show(InfoMessage:new{ text = _("无法打开阅读洞察，请确认插件已正确安装") })
                    logger.warn(LOG_TAG, "open reading insights failed:", err2)
                end
            end)
        end,
    }
    -- 站台画布使用 1040×1141 的虚拟坐标系，需换算成屏幕坐标后定位
    -- 落点：内容区右下角内侧
    --   左右两侧各有贯穿全高的装饰带（左 0~54、右 993~1040），内容区右界 970
    --   → 按钮右缘贴 968、底缘贴 1133，既不压装饰带也不压板块边线
    local vw, vh = Screen:getWidth(), Screen:getHeight()
    local vsx, vsy = (vw - 20) / 1040, (vh - 10) / 1141
    local content_right  = 10 + 968 * vsx
    local content_bottom = 5 + 1133 * vsy
    badge_btn.overlap_offset = {
        math.floor(content_right - badge_size - 4),
        math.floor(content_bottom - badge_size - 4),
    }

    local overlap = OverlapGroup:new{
        dimen = screen_size,
        widget,
        badge_btn,
    }
    -- 点击区域信息挂到最外层，供 main.lua quicklookbox:onTap 使用
    overlap.hit_books = hit_books
    overlap.action_hits = action_hits

    -- 关闭时释放资源
    if on_close_callback then
        local orig_close = overlap.close
        overlap.close = function(self)
            if orig_close then orig_close(self) end
            if bb and bb.free then pcall(bb.free, bb) end
            on_close_callback()
        end
    else
        if bb and bb.free then pcall(bb.free, bb) end
    end

    return overlap
end

return {
    buildStationWidget = buildStationWidget,
    paintHomeStation = paintHomeStation,
}
