-- lastread.lua - 「最近阅读的书」公共数据源
--
-- 背景：插件里有三处都要回答"最后读的是哪本书"——
--   ① 胶片样式 styles/film.lua   ：原先完全没有兜底，没打开书就放弃渲染（锁屏回退默认屏保）
--   ② 单书票   tickets/book.lua  ：原先不放弃但数据双空，退化成空白票
--   ③ 站台样式 styles/station.lua：自己实现了一份"最近阅读"兜底
-- 三份实现会各自漂移，故抽出本模块统一供给。胶片与单书票本次接入；
-- 站台的主逻辑（当前书优先）特殊性较强暂时保留，但其 md5 反查与本模块同源。
--
-- 数据来源：statistics.sqlite3（经 lib/rl_reference 读取），文件路径靠 md5 反查。
-- 所有外部调用一律 pcall 保护，任何一步失败都退化成 nil，由调用方自行降级。

local rl = require("lib.rl_reference")
local logger = require("logger")

local LOG_TAG = "[BookReceipt.LastRead]"

local M = {}

-- md5 → 文件路径 映射
-- statistics 的 book.md5 与 DocSettings 的 partial_md5_checksum 同源，
-- 比"书名字符串比对"可靠得多（两边标题来源不同，经常对不上）。
-- 两级策略（同 statistics.koplugin 官方做法）：先读 sidecar（快），
-- 没有再调 util.partialMD5 现算（慢）。进程内缓存，只在确实需要时才建表。
local _md5_path_cache = nil

function M.md5PathMap()
    if _md5_path_cache then return _md5_path_cache end
    _md5_path_cache = {}
    local ok_rh, readhistory = pcall(require, "readhistory")
    if not ok_rh or not readhistory or not readhistory.hist then return _md5_path_cache end
    local ok_ds, DocSettings = pcall(require, "docsettings")
    local ok_u, util = pcall(require, "util")
    for _, entry in ipairs(readhistory.hist or {}) do
        local file = entry and entry.file
        if file and file ~= "" then
            local sum
            if ok_ds and DocSettings.hasSidecarFile and DocSettings:hasSidecarFile(file) then
                local ok_open, ds = pcall(DocSettings.open, DocSettings, file)
                if ok_open and ds and ds.readSetting then
                    sum = ds:readSetting("partial_md5_checksum")
                end
            end
            if (not sum or sum == "") and ok_u and util and util.partialMD5 then
                local ok_md5, computed = pcall(util.partialMD5, file)
                if ok_md5 then sum = computed end
            end
            if sum and sum ~= "" and not _md5_path_cache[sum] then
                _md5_path_cache[sum] = file
            end
        end
    end
    return _md5_path_cache
end

-- 取「最近阅读的书」
-- opts.title_path_map（可选）：书名→路径映射，命中优先于 md5 反查
-- 返回表字段：
--   title      书名
--   md5        书号（与 DocSettings 的 partial_md5_checksum 同源）
--   path       文件路径（可能为空：历史里查不到时封面取不到，其余字段仍可用）
--   pages      全书总页数
--   page       最后读到的页码
--   percent    进度百分比
--   total_time 全书累计阅读秒数
--   total_read_pages 累计已读页数（用于推算每页均速）
--   avg_time   每页平均秒数（数据不足时为 nil）
--   last_read  最后阅读时间戳
-- 取不到返回 nil
function M.resolve(opts)
    opts = opts or {}
    local ok_r, rows = pcall(rl.readReadingDataAll)
    if not ok_r or not rows or #rows == 0 then
        logger.dbg(LOG_TAG, "统计库无阅读记录，无法兜底")
        return nil
    end

    -- 取时间最新的一条
    local latest
    for _, row in ipairs(rows) do
        local t = tonumber(row and row.time) or 0
        if not latest or t > (tonumber(latest.time) or 0) then latest = row end
    end
    if not latest then return nil end

    -- 路径反查：书名映射优先（调用方可传），其次 md5
    local path = opts.title_path_map and opts.title_path_map[latest.title or ""] or nil
    if (not path or path == "") and (latest.md5 or "") ~= "" then
        local ok_map, map = pcall(M.md5PathMap)
        if ok_map and map then path = map[latest.md5] end
    end

    local total_time = tonumber(latest.total_time) or 0
    local read_pages = tonumber(latest.total_pages) or 0
    local avg_time
    if read_pages > 0 and total_time > 0 then
        avg_time = total_time / read_pages
    end

    return {
        title = latest.title or "",
        md5 = latest.md5 or "",
        path = path or "",
        authors = latest.authors or "",
        pages = tonumber(latest.pages) or 0,
        page = tonumber(latest.display_page or latest.page) or 0,
        percent = tonumber(latest.percent) or 0,
        total_time = total_time,
        total_read_pages = read_pages,
        avg_time = avg_time,
        last_read = tonumber(latest.time) or 0,
    }
end

-- 当前是否"确实打开了书"。兜底逻辑的唯一触发条件：
-- 只有完全没有活动文档时才允许用最近阅读兜底，
-- 绝不覆盖"有书但统计库还没落库"的情形（否则会退回上一本书，v0.2.3 的旧 bug）。
function M.hasActiveDocument(ui)
    return ui ~= nil and ui.document ~= nil
end

return M
