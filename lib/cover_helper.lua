-- cover_helper.lua - 书籍封面获取（供各票型共用）
--
-- 2026-09-07 从 tickets/book.lua 抽出，单书行程票与月票日历共用同一套取封面链路。
--
-- 优先级：
--   ① 书籍元数据封面（CoverBrowser/BookInfoManager 缓存 → DocumentRegistry 提取）
--   ② Kindle 原生侧车缩略图（documents/xxx.sdr/xxx-thumbnail_te.png 等）
--   ③ 均无时返回 nil，由调用方回退为书名占位牌
--
-- 说明：rl.getBookCoverFromPath 会把封面拉伸到给定宽高，因此调用方必须传入
--       符合书封比例（约 0.72）的像素尺寸，否则封面会变形。

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local rl = require("lib.rl_reference")

local CoverHelper = {}
local LOG_TAG = "[BookReceipt]"

-- ============================================================
-- 书名 → 文件路径 映射
-- ============================================================

-- 遍历阅读历史，用 CoverBrowser 书库信息反查书名；未装 CoverBrowser 时退化为文件名匹配
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

-- 模块级缓存：映射构建含 readhistory 遍历 + BIM 查询，60 秒内复用
local _title_map_cache, _title_map_at = nil, 0
local function getTitlePathMap()
    local now = os.time()
    if _title_map_cache and now - _title_map_at < 60 then return _title_map_cache end
    local ok, map = pcall(buildTitlePathMap)
    _title_map_cache = (ok and map) or {}
    _title_map_at = now
    return _title_map_cache
end

-- 按标题查找书籍文件路径：精确匹配 → 去标点空格后的模糊匹配
function CoverHelper.findBookFile(title)
    if not title or title == "" then return nil end
    local map = getTitlePathMap()
    if map[title] then return map[title] end
    local norm = tostring(title):gsub("[%s%p]", ""):lower()
    if norm ~= "" then
        for t, f in pairs(map) do
            local tnorm = tostring(t):gsub("[%s%p]", ""):lower()
            if tnorm ~= "" and (tnorm == norm or tnorm:find(norm, 1, true) or norm:find(tnorm, 1, true)) then
                return f
            end
        end
    end
    return nil
end

-- ============================================================
-- Kindle 原生侧车缩略图
-- ============================================================

function CoverHelper.findKindleThumbnail(path)
    if not path or path == "" then return nil end
    local dir, name = tostring(path):match("^(.*)/([^/]+)$")
    if not dir or not name or name == "" then return nil end
    local base = name:match("^(.+)%.[^%.]+$") or name
    local sdr = dir .. "/" .. base .. ".sdr"
    if lfs.attributes(sdr, "mode") ~= "directory" then return nil end
    local candidates = {
        sdr .. "/" .. base .. "-thumbnail_te.png",
        sdr .. "/" .. base .. "-thumbnail_te.jpg",
        sdr .. "/" .. base .. "-thumbnail.png",
        sdr .. "/" .. base .. "-thumbnail.jpg",
    }
    for _, c in ipairs(candidates) do
        if lfs.attributes(c, "mode") == "file" then return c end
    end
    return nil
end

-- ============================================================
-- 封面控件获取
-- ============================================================

-- ============================================================
-- 按需抽取封面
-- rl.getBookCoverFromPath 只读 CoverBrowser 缓存，缓存里没有的书会直接返回 nil。
-- 实测本机 460 本缓存书目中仅 59 本有封面，若不按需抽取，月票会大量回退书名占位牌。
-- 这里对未命中缓存的书触发一次 BIM.extractBookInfo（子进程执行，结果持久化到 BIM 库），
-- 之后该书即可秒出封面。为防首次渲染卡顿，每轮渲染最多抽取 MAX_EXTRACT_PER_RENDER 本，
-- 且同一本书一个会话内只尝试一次（cover_fetched 标记过的书不再重试）。
-- ============================================================
local MAX_EXTRACT_PER_RENDER = 3
local _extract_tried = {}   -- 会话级：path → true
local _extract_budget = 0   -- 每轮预算，newCoverCache() 时重置

function CoverHelper.tryExtractCover(path)
    if not path or path == "" then return false end
    if _extract_tried[path] then return false end
    _extract_tried[path] = true
    if _extract_budget <= 0 then return false end

    local ok_bim, BIM = pcall(require, "bookinfomanager")
    if not ok_bim then ok_bim, BIM = pcall(require, "plugins/coverbrowser.koplugin/bookinfomanager") end
    if not (ok_bim and BIM and BIM.extractBookInfo and BIM.getBookInfo) then return false end

    -- 已经尝试过（无论成败）的书不再重试，避免每轮都白抽
    local ok_i, info = pcall(BIM.getBookInfo, BIM, path, true)
    if ok_i and info and info.cover_fetched then return false end

    _extract_budget = _extract_budget - 1
    local ok_e, err = pcall(BIM.extractBookInfo, BIM, path, {
        sizetag = "bookreceipt",
        max_cover_w = 240,
        max_cover_h = 360,
    })
    if not ok_e then
        logger.info(LOG_TAG, "封面抽取失败：", tostring(err))
        return false
    end
    logger.info(LOG_TAG, "已按需抽取封面：", path)
    return true
end

-- w/h 为真实像素；返回 ImageWidget（调用方负责 free），取不到返回 nil
function CoverHelper.getCoverWidget(path, w, h)
    if not path or path == "" then return nil end
    w = math.max(1, math.floor(w or 60))
    h = math.max(1, math.floor(h or 84))
    -- ① 书籍元数据封面（缓存命中）
    local ok1, widget = pcall(rl.getBookCoverFromPath, path, w, h)
    if ok1 and widget then return widget end
    -- ①b 缓存未命中：按需抽取一次后重试（每轮有限额）
    if CoverHelper.tryExtractCover(path) then
        local ok2, w2 = pcall(rl.getBookCoverFromPath, path, w, h)
        if ok2 and w2 then return w2 end
    end
    -- ② Kindle 原生侧车缩略图兜底
    local ok_k, kpath = pcall(CoverHelper.findKindleThumbnail, path)
    if ok_k and kpath then
        local ok_iw, ImageWidget = pcall(require, "ui/widget/imagewidget")
        if ok_iw and ImageWidget then
            local ok_w, kw = pcall(ImageWidget.new, ImageWidget, {
                file = kpath, width = w, height = h,
            })
            if ok_w and kw then return kw end
        end
    end
    return nil
end

-- ============================================================
-- 单次渲染内的封面缓存
-- 同一本书跨多个日期格出现时只解码一次；同一路径取不到封面也只尝试一次。
-- 用法：local cache = CoverHelper.newCoverCache() ... cache:get(path,w,h) ... cache:freeAll()
-- ============================================================

function CoverHelper.newCoverCache()
    local widgets, missed = {}, {}
    local api = {}
    _extract_budget = MAX_EXTRACT_PER_RENDER   -- 每轮渲染重置抽取限额
    function api:get(path, w, h)
        if not path or path == "" then return nil end
        local key = tostring(path) .. "|" .. tostring(w) .. "|" .. tostring(h)
        if widgets[key] then return widgets[key] end
        if missed[key] then return nil end
        local wd = CoverHelper.getCoverWidget(path, w, h)
        if wd then
            widgets[key] = wd
        else
            missed[key] = true
        end
        return wd
    end
    function api:freeAll()
        for _, wd in pairs(widgets) do
            if wd.free then pcall(wd.free, wd) end
        end
        widgets = {}
    end
    function api:count()
        local n = 0
        for _ in pairs(widgets) do n = n + 1 end
        return n
    end
    return api
end

return CoverHelper
