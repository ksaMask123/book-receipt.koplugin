-- open_book.lua - 站台样式的开书出口（插件私有工具）
-- 背景：移植母插件 readingline 时把它的私有函数 openBookThroughFileManager
--       误当成 KOReader 前端通用工具，写成 require("frontend/ui/utils")，
--       而真机并不存在该模块，导致 CONTINUE / 书籍卡片点击全部静默失效。
-- 本模块改用官方 API 实现：FileManager 实例优先，否则 ReaderUI:showReader。
-- 机制参照母插件 rl_shelf_utils.lua L205（先关界面 → nextTick → 打开），
-- 并补一条母插件没有的短路：目标就是当前正在读的书时不再重复加载。

local UIManager = require("ui/uimanager")
local logger = require("logger")

local LOG_TAG = "[BookReceipt]"

local M = {}

-- 取当前活着的 FileManager 实例（母插件 liveFileManager 同款写法）
local function liveFileManager()
    local FM = package.loaded["apps/filemanager/filemanager"]
    return FM and FM.instance or nil
end

-- 失败要出声，不再静默吞错
local function notify(text)
    local ok, InfoMessage = pcall(require, "ui/widget/infomessage")
    if ok and InfoMessage then
        UIManager:show(InfoMessage:new{ text = text, timeout = 3 })
    end
end

-- 打开 target_path
--   current_path：当前正在读的书（可为 nil，例如屏保 / 无阅读界面场景）
--   target_path ：要打开的书
-- 返回 true = 已受理（可能延后到下一 tick），false = 无法处理
function M.openBook(current_path, target_path)
    if not target_path or target_path == "" then
        logger.warn(LOG_TAG, "openBook: 目标路径为空，忽略")
        return false
    end

    -- 目标就是当前正在读的书：只需关闭小票即可回到书里。
    -- 重复 showReader 会触发无谓重载，甚至打断阅读位置。
    if current_path and current_path ~= "" and current_path == target_path then
        logger.info(LOG_TAG, "openBook: 目标即当前书，跳过重载")
        return true
    end

    -- 延后到下一 tick：等小票真正退出 UIManager 栈再开书，
    -- 否则旧 widget 的延迟关闭会把新开的 reader 一起掀掉（母插件踩过的坑）
    UIManager:nextTick(function()
        local ok, err = pcall(function()
            local fm = liveFileManager()
            if fm and fm.openFile then
                fm:openFile(target_path)
            else
                require("apps/reader/readerui"):showReader(target_path)
            end
        end)
        if not ok then
            logger.warn(LOG_TAG, "openBook 失败:", tostring(err))
            notify("无法打开该书：" .. tostring(err))
        end
    end)
    return true
end

return M
