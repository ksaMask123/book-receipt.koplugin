-- Book Receipt Plugin - Main Entry Point
-- 阅读小票插件：支持固定/随机/轮流三种模式
-- 手势调出 + 锁屏展示多种票型

local PLUGIN_DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or "."
package.path = package.path .. ";" .. PLUGIN_DIR .. "/?.lua;" .. PLUGIN_DIR .. "/lib/?.lua;" .. PLUGIN_DIR .. "/tickets/?.lua;" .. PLUGIN_DIR .. "/styles/?.lua"

-- KOReader核心依赖
local BB = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Button = require("ui/widget/button")
local ReaderUI = require("apps/reader/readerui")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local CenterContainer = require("ui/widget/container/centercontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- 汉化支持
local _ = require("gettext")
do
    local zh_translations = {
        ["Gesture style"] = "手势调出样式",
        ["Lockscreen style"] = "锁屏壁纸样式",
        ["Film strip (fixed style)"] = "胶片票根（固定风格）",
        ["Ink stain"] = "墨痕壁纸",
        ["Order Slip"] = "留台单",
        ["Station style"] = "站台样式（阅读主页）",
        ["Day ticket"] = "日票",
        ["Week ticket"] = "周票",
        ["Month ticket"] = "月票",
        ["Year ticket"] = "年票",
        ["Book ticket"] = "书籍票",
        ["Screen ticket"] = "屏保票",
        ["Randomize style each time"] = "随机出现",
        ["Alternate style each time"] = "轮流出现",
        ["Book receipt"] = "阅读摘要",
        ["Receipt unavailable"] = "无法显示阅读摘要",
        ["Show book receipt on sleep screen"] = "在休眠屏幕显示阅读摘要",
        ["Book receipt settings"] = "阅读摘要设置",
    }
    local orig__ = _
    _ = function(s)
        if type(s) == "string" and zh_translations[s] then return zh_translations[s] end
        return orig__(s)
    end
    _G._ = _
end

local LOG_TAG = "[BookReceipt]"

-- 常量定义（必须先于其他函数）
local K = {
    BG_SETTING = "book_receipt_screensaver_background",
    CONTENT_MODE_SETTING = "book_receipt_content_mode",
    COVER_SCALE_SETTING = "book_receipt_cover_scale",
    STYLE_SETTING = "book_receipt_style",
    RANDOM_STYLE = "book_receipt_random_style",
    STYLE_MODE_SETTING = "book_receipt_style_mode",
    STYLE_TOGGLE_STATE = "book_receipt_style_toggle_state",
    LOCKSCREEN_MODE_SETTING = "book_receipt_lockscreen_mode",
    LOCKSCREEN_STYLE_SETTING = "book_receipt_lockscreen_style",
    LOCKSCREEN_TOGGLE_STATE = "book_receipt_lockscreen_toggle_state",
    STYLE_FILM = "film",
    STYLE_INKSTAIN = "inkstain",
    STYLE_MENU = "menu",
    STYLE_STATION = "station",
}

local STYLE_KEYS = { K.STYLE_FILM, K.STYLE_INKSTAIN, K.STYLE_MENU, K.STYLE_STATION }
local TICKET_KEYS = { "day", "week", "month", "year", "book", "screen" }

local TICKET_LABELS = {
    day = _("Day ticket"),
    week = _("Week ticket"),
    month = _("Month ticket"),
    year = _("Year ticket"),
    book = _("Book ticket"),
    screen = _("Screen ticket"),
}

-- 前向声明：buildTicketWidget 将在后面定义
local buildTicketWidget

-- 工具函数
local function normalizeStyleMode(mode, legacy_random_flag)
    if mode == "random" or mode == "alternate" or mode == "fixed" then return mode end
    if legacy_random_flag then return "random" end
    return "fixed"
end

local function normalizeReceiptStyle(value)
    if value == K.STYLE_FILM or value == K.STYLE_INKSTAIN or value == K.STYLE_MENU or value == K.STYLE_STATION then return value end
    if value == "day" or value == "week" or value == "month" or value == "year" or value == "book" or value == "screen" then return value end
    return K.STYLE_FILM
end

local function isTicketKey(key)
    for __, k in ipairs(TICKET_KEYS) do if key == k then return true end end
    return false
end

-- 模式获取函数
local function getStyleMode()
    return normalizeStyleMode(G_reader_settings:readSetting(K.STYLE_MODE_SETTING), G_reader_settings:isTrue(K.RANDOM_STYLE))
end

local function getLockscreenMode()
    return normalizeStyleMode(G_reader_settings:readSetting(K.LOCKSCREEN_MODE_SETTING), false)
end

local function migrateLockscreenStyle()
    if G_reader_settings:has(K.LOCKSCREEN_MODE_SETTING) then return end
    local global_mode = getStyleMode()
    G_reader_settings:saveSetting(K.LOCKSCREEN_MODE_SETTING, global_mode)
    if global_mode == "fixed" then
        G_reader_settings:saveSetting(K.LOCKSCREEN_STYLE_SETTING, normalizeReceiptStyle(G_reader_settings:readSetting(K.STYLE_SETTING)))
    end
end

-- 旋转池（必须在所有引用它的函数之前定义）
local function getRotationPool()
    local pool = {}
    for __, s in ipairs(STYLE_KEYS) do pool[#pool + 1] = s end
    for __, k in ipairs(TICKET_KEYS) do pool[#pool + 1] = k end
    return pool
end

-- 轮流模式：切换到下一个
local function getAlternateStyleAndAdvance(toggle_key)
    local styles = getRotationPool()
    local cur = G_reader_settings:readSetting(toggle_key)
    local idx = 1
    for i, s in ipairs(styles) do
        if s == cur then idx = i; break end
    end
    if styles[idx] ~= cur then idx = 1; cur = styles[1] end
    local next_style = styles[(idx % #styles) + 1]
    G_reader_settings:saveSetting(toggle_key, next_style)
    return cur
end

-- 手势调出时：根据模式返回当前样式
local function getEffectiveStyle()
    local mode = getStyleMode()
    if mode == "random" then
        local pool = getRotationPool()
        return pool[math.random(#pool)]
    end
    if mode == "alternate" then return getAlternateStyleAndAdvance(K.STYLE_TOGGLE_STATE) end
    return normalizeReceiptStyle(G_reader_settings:readSetting(K.STYLE_SETTING))
end

-- 锁屏时：根据锁屏模式返回当前样式
local function getLockscreenEffectiveStyle()
    migrateLockscreenStyle()
    local mode = getLockscreenMode()
    if mode == "random" then
        local pool = getRotationPool()
        return pool[math.random(#pool)]
    end
    if mode == "alternate" then return getAlternateStyleAndAdvance(K.LOCKSCREEN_TOGGLE_STATE) end
    return normalizeReceiptStyle(G_reader_settings:readSetting(K.LOCKSCREEN_STYLE_SETTING))
end

-- 加载票型模块（使用 pcall 保护）
local ticket_modules = {}
for __, key in ipairs(TICKET_KEYS) do
    local ok, mod = pcall(require, "tickets." .. key)
    if ok and mod and mod.render then
        ticket_modules[key] = mod
        logger.info(LOG_TAG, "已加载票型模块:", key)
    else
        logger.warn(LOG_TAG, "加载票型模块失败:", key, tostring(mod))
    end
end

-- 加载样式模块（使用 pcall 保护，延迟加载避免初始化时崩溃）
local film_mod = nil
local inkstain_mod = nil
local menu_mod = nil
local station_mod = nil

local function loadStyleModules()
    if not film_mod then
        local ok, mod = pcall(require, "styles.film")
        if ok and mod then
            film_mod = mod
            logger.info(LOG_TAG, "已加载胶片样式模块")
        else
            logger.err(LOG_TAG, "加载胶片样式模块失败:", mod)
        end
    end
    if not inkstain_mod then
        local ok, mod = pcall(require, "styles.inkstain")
        if ok and mod then
            inkstain_mod = mod
            logger.info(LOG_TAG, "已加载墨痕样式模块")
        else
            logger.err(LOG_TAG, "加载墨痕样式模块失败:", mod)
        end
    end
    if not menu_mod then
        local ok, mod = pcall(require, "styles.menu")
        if ok and mod then
            menu_mod = mod
            logger.info(LOG_TAG, "已加载菜单样式模块")
        else
            logger.err(LOG_TAG, "加载菜单样式模块失败:", mod)
        end
    end
    if not station_mod then
        local ok, mod = pcall(require, "styles.station")
        if ok and mod then
            station_mod = mod
            logger.info(LOG_TAG, "已加载站台样式模块")
        else
            logger.err(LOG_TAG, "加载站台样式模块失败:", mod)
        end
    end
end

-- buildTicketWidget：构建票型widget
buildTicketWidget = function(ui, ticket_key, ref_date, on_close_callback)
    ref_date = ref_date or os.time()
    local mod = ticket_modules[ticket_key]
    if not mod then
        logger.warn(LOG_TAG, "票型模块未就绪，降级为胶片:", ticket_key)
        ticket_key = K.STYLE_FILM
        mod = film_mod
        if not mod then return nil end
    end
    if isTicketKey(ticket_key) then
        -- 获取当前活动书籍标题
        local book_title = ""
        if ui and ui.doc_props and ui.doc_props.display_title then
            book_title = ui.doc_props.display_title
        end
        local bb = BB.new(Screen:getWidth(), Screen:getHeight(), Screen.bb:getType())
        if not bb then return nil end
        -- ticket render 函数签名: (bb, x, y, w, h, ref_date)
        -- book.lua 特殊: (bb, x, y, w, h, book_title, ref_date)
        local ok, err
        if ticket_key == "book" then
            ok, err = pcall(mod.render, bb, 0, 0, Screen:getWidth(), Screen:getHeight(), book_title, ref_date)
        else
            ok, err = pcall(mod.render, bb, 0, 0, Screen:getWidth(), Screen:getHeight(), ref_date)
        end
        if ok and bb then
            local widget = ImageWidget:new{ image = bb, dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } }
            if on_close_callback then widget.close_callback = on_close_callback end

            -- 小花按钮 ✿：与墨痕/胶片/站台同款交互（关闭当前界面 + 延迟广播阅读洞察事件）
            -- 票型（日/周/月/年/书/屏）共用此处出口，一次覆盖全部票型
            local screen_size = Screen:getSize()
            local badge_size = Screen:scaleBySize(40)
                    local badge_btn = Button:new{
                text = "✿",
                text_face = Font:getFace("cfont", Screen:scaleBySize(18)),
                fg_color = BB.COLOR_BLACK,
                background = BB.COLOR_WHITE,
                bordersize = 0,
                padding = 0,
                width = badge_size,
                height = badge_size,
                callback = function()
                    if on_close_callback then on_close_callback() end
                    UIManager:setDirty(nil, "full")
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
            -- 票型画布使用 1006×1093 的虚拟坐标系，需换算成屏幕坐标后定位
            -- 落点：内边框（虚拟 968, 1062）内侧的右下角
            --   外框 18~988 / 内框 38~968，页脚文字只到 X 861、Y 988
            --   → 右下角 X 860~968、Y 990~1060 是空白区，既不压边线也不压文字
            local vw, vh = Screen:getWidth(), Screen:getHeight()
            local vs  = math.min((vw - 36) / 1006, (vh - 24) / 1093)
            local vsy = math.max(vs, (vh - 8) / 1093)
            local vox, voy = (vw - 1006 * vs) / 2, 4
            local inner_right  = vox + 968 * vs      -- 内边框右线
            local inner_bottom = voy + 1062 * vsy    -- 内边框底线
            badge_btn.overlap_offset = {
                math.floor(inner_right - badge_size - 6),
                math.floor(inner_bottom - badge_size - 6),
            }
            local overlap = OverlapGroup:new{
                dimen = screen_size,
                widget,
                badge_btn,
            }
            if on_close_callback then overlap.close_callback = on_close_callback end
            return overlap
        else
            logger.warn(LOG_TAG, "票型渲染失败:", ticket_key, tostring(err))
            return nil
        end
    else
        -- 非票型时尝试调用build
        if mod.build then
            return mod.build(ui, nil, on_close_callback)
        end
        return nil
    end
end

-- buildReceipt：根据样式分发到对应构建函数
-- 与原补丁保持一致：
--   - film: mod.build(ui, state, on_close_callback)
--   - inkstain/menu: mod.buildInkStainWidget(ui, on_close_callback, style)
--   - ticket: buildTicketWidget(ui, ticket_key, nil, on_close_callback)
local function buildReceipt(ui, state, on_close_callback, style)
    loadStyleModules()  -- 确保样式模块已加载
    if style == nil then style = getEffectiveStyle() end
    logger.dbg(LOG_TAG, "buildReceipt: style =", tostring(style))
    if style == K.STYLE_INKSTAIN or style == K.STYLE_MENU then
        local mod = inkstain_mod
        if style == K.STYLE_MENU then mod = menu_mod or inkstain_mod end
        if mod and mod.buildInkStainWidget then
            return mod.buildInkStainWidget(ui, on_close_callback, style)
        end
        logger.warn(LOG_TAG, style, "模块缺少buildInkStainWidget")
        return nil
    end
    if style == K.STYLE_STATION then
        if station_mod and station_mod.buildStationWidget then
            return station_mod.buildStationWidget(ui, nil, nil, on_close_callback)
        end
        logger.warn(LOG_TAG, "站台样式模块不可用")
        return nil
    end
    if isTicketKey(style) then
        return buildTicketWidget(ui, style, nil, on_close_callback)
    end
    -- film 或未知样式
    if film_mod and film_mod.build then
        return film_mod.build(ui, state, on_close_callback)
    end
    logger.warn(LOG_TAG, "胶片模块不可用，无法构建小票")
    return nil
end

-- quicklookbox：手势调出弹窗
local quicklookbox = InputContainer:extend{ modal = true, name = "quick_look_box", covers_fullscreen = true }

function quicklookbox:init()
    local style = getEffectiveStyle()
    local receipt_widget = buildReceipt(self.ui, self.state, function()
        UIManager:close(self)
    end, style)
    if receipt_widget then
        self[1] = receipt_widget
    else
        self[1] = CenterContainer:new{
            dimen = Screen:getSize(),
            TextWidget:new{ text = _("Receipt unavailable"), face = Font:getFace("cfont", 20) },
        }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } }
        self.ges_events.MultiSwipe = { GestureRange:new{ ges = "multiswipe", range = function() return self.dimen end } }
    end
end

-- onTap：先检查按钮/书籍点击区域，再决定关闭（参照原插件 Shelf:onTapBook 架构）
function quicklookbox:onTap(_, ges_ev)
    if not ges_ev or not ges_ev.pos then return self:onClose() end
    local pos = ges_ev.pos
    local widget = self[1]

    -- 1. 检查按钮点击区域（CONTINUE 等，来自 station.lua action_hits）
    if widget and widget.action_hits then
        for _, hit in ipairs(widget.action_hits) do
            if pos.x >= hit.x and pos.x <= hit.x + hit.w
               and pos.y >= hit.y and pos.y <= hit.y + hit.h then
                -- 命中按钮 → 执行回调后关闭
                if hit.callback then
                    self:onClose()
                    pcall(hit.callback)
                else
                    self:onClose()
                end
                return true
            end
        end
    end

    -- 2. 检查书籍点击区域（来自 station.lua hit_books）
    if widget and widget.hit_books then
        for _, hit in ipairs(widget.hit_books) do
            if pos.x >= hit.x and pos.x <= hit.x + hit.w
               and pos.y >= hit.y and pos.y <= hit.y + hit.h then
                -- 命中书籍 → 打开后关闭
                if hit.book and hit.book.path and hit.book.path ~= "" then
                    self:onClose()
                    local Utils = require("frontend/ui/utils")
                    pcall(Utils.openBookThroughFileManager, nil, hit.book.path)
                else
                    self:onClose()
                end
                return true
            end
        end
    end

    -- 3. 未命中任何区域 → 关闭弹窗
    return self:onClose()
end
function quicklookbox:onSwipe(arg, ges_ev) return self:onClose() end
function quicklookbox:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end
quicklookbox.onAnyKeyPressed = quicklookbox.onClose
quicklookbox.onMultiSwipe = quicklookbox.onClose

-- 事件处理：确保 propagateEvent 能正常调用 handleEvent
function quicklookbox:handleEvent(event)
    return InputContainer.handleEvent(self, event)
end

-- ReaderUI.onQuickLook：手势触发入口
-- 与原补丁一致：使用 quicklookbox.new（构造函数），不用 :new()
function ReaderUI:onQuickLook()
    local ui = self
    UIManager:nextTick(function()
        if not ui then return end
        local ok, widget = pcall(quicklookbox.new, quicklookbox, {
            ui = ui,
            document = ui.document,
            state = ui.view and ui.view.state,
        })
        if not ok or not widget then
            logger.warn(LOG_TAG, "QuickLook构建失败:", tostring(widget))
            return
        end
        UIManager:show(widget)
    end)
end

-- 注册手势动作
if Dispatcher and Dispatcher.registerAction then
    Dispatcher:registerAction("quicklookbox_action", {
        category = "none",
        event = "QuickLook",
        title = _("Book receipt"),
        reader = true,
    })
    logger.info(LOG_TAG, "已注册 quicklookbox_action 到 Dispatcher")
else
    logger.warn(LOG_TAG, "Dispatcher不可用，手势注册跳过")
end

-- 覆写Screensaver.show：锁屏时展示阅读小票
local Screensaver = require("ui/screensaver")
local orig_screensaver_show = Screensaver.show
if not Screensaver._book_receipt_patched then
    Screensaver._book_receipt_patched = true
    Screensaver.show = function(self)
        local user_wants_book_receipt = G_reader_settings:readSetting("screensaver_type") == "book_receipt"
        if not user_wants_book_receipt and self.screensaver_type ~= "book_receipt" then
            return orig_screensaver_show(self)
        end
        if user_wants_book_receipt then self.screensaver_type = "book_receipt" end
        local ui = self.ui or ReaderUI.instance
        local style = getLockscreenEffectiveStyle()
        if self.screensaver_widget then
            UIManager:close(self.screensaver_widget)
            self.screensaver_widget = nil
        end
        local receipt_widget = buildReceipt(ui, nil, function()
            if self.close then self:close() end
            UIManager:setDirty(nil, "full")
        end, style)
        if receipt_widget then
            self.screensaver_widget = ScreenSaverWidget:new{
                widget = receipt_widget,
                background = BB.COLOR_WHITE,
                covers_fullscreen = true,
            }
            self.screensaver_widget.modal = true
            self.screensaver_widget.dithered = true
            UIManager:show(self.screensaver_widget, "full")
        else
            logger.warn(LOG_TAG, "构建阅读小票失败，回退默认屏保")
            return orig_screensaver_show(self)
        end
    end
end

-- 劫持dofile以注入菜单
local orig_dofile = dofile
_G.dofile = function(filepath)
    local ok, result = pcall(orig_dofile, filepath)
    if not ok then return nil end
    if filepath and filepath:match("screensaver_menu%.lua$") then
        logger.info(LOG_TAG, "拦截到 screensaver_menu.lua 加载，开始注入菜单")
        local ok_inject, err_inject = pcall(function()
            if not result or type(result) ~= "table" then return end
            local target_submenu = nil
            for idx, item in ipairs(result) do
                if item.text and (item.text == "Wallpaper" or item.text:find("壁纸")) and item.sub_item_table then
                    target_submenu = item.sub_item_table
                    break
                end
            end
            target_submenu = target_submenu or (result[1] and result[1].sub_item_table) or result
            local br_marker = _("Show book receipt on sleep screen")
            for __, item in ipairs(target_submenu) do
                if item.text and item.text:find(br_marker) then
                    logger.info(LOG_TAG, "菜单项已存在，跳过注入")
                    return
                end
            end
            -- 生成统一风格的单选菜单项（样式+票型全部同级）
            local function genStyleOrTicketItem(key, label, setting, mode_key)
                return {
                    text = label,
                    checked_func = function()
                        local cur = G_reader_settings:readSetting(setting)
                        local mode = G_reader_settings:readSetting(mode_key)
                        -- 如果处于随机/轮流模式，不显示任何具体项为选中
                        if mode == "random" or mode == "alternate" then return false end
                        return normalizeReceiptStyle(cur) == key
                    end,
                    callback = function()
                        -- 选中具体项时，强制切回固定模式
                        G_reader_settings:saveSetting(setting, key)
                        G_reader_settings:saveSetting(mode_key, "fixed")
                    end,
                    radio = true,
                }
            end
            local function genModeItem(text, mode, setting, random_flag)
                return {
                    text = text,
                    checked_func = function() return getStyleMode() == mode end,
                    callback = function()
                        -- 选中随机/轮流时，不保存具体样式（让模式决定显示什么）
                        G_reader_settings:saveSetting(setting, mode)
                        G_reader_settings:saveSetting(random_flag, mode == "random")
                    end,
                    radio = true,
                }
            end
            local function genLockscreenModeItem(text, mode, setting)
                return {
                    text = text,
                    checked_func = function()
                        if G_reader_settings:has(setting) then
                            return G_reader_settings:readSetting(setting) == mode
                        end
                        return getStyleMode() == mode
                    end,
                    callback = function()
                        G_reader_settings:saveSetting(setting, mode)
                    end,
                    radio = true,
                }
            end
            -- 手势调出菜单项列表：3种样式 + 6种票型 + 2种模式
            local gesture_items = {}
            for __, s in ipairs(STYLE_KEYS) do
                local label
                if s == K.STYLE_FILM then
                    label = _("Film strip (fixed style)")
                elseif s == K.STYLE_INKSTAIN then
                    label = _("Ink stain")
                elseif s == K.STYLE_MENU then
                    label = _("Order Slip")
                else
                    label = _("Station style")
                end
                gesture_items[#gesture_items + 1] = genStyleOrTicketItem(s, label, K.STYLE_SETTING, K.STYLE_MODE_SETTING)
            end
            for __, key in ipairs(TICKET_KEYS) do
                gesture_items[#gesture_items + 1] = genStyleOrTicketItem(
                    key, TICKET_LABELS[key] or key, K.STYLE_SETTING, K.STYLE_MODE_SETTING)
            end
            gesture_items[#gesture_items + 1] = genModeItem(
                _("Randomize style each time"), "random", K.STYLE_MODE_SETTING, K.RANDOM_STYLE)
            gesture_items[#gesture_items + 1] = genModeItem(
                _("Alternate style each time"), "alternate", K.STYLE_MODE_SETTING, K.RANDOM_STYLE)
            local style_menu = {
                text = _("Gesture style"),
                sub_item_table = gesture_items,
            }
            -- 锁屏菜单项列表：同结构
            local lockscreen_items = {}
            for __, s in ipairs(STYLE_KEYS) do
                local label
                if s == K.STYLE_FILM then
                    label = _("Film strip (fixed style)")
                elseif s == K.STYLE_INKSTAIN then
                    label = _("Ink stain")
                elseif s == K.STYLE_MENU then
                    label = _("Order Slip")
                else
                    label = _("Station style")
                end
                lockscreen_items[#lockscreen_items + 1] = {
                    text = label,
                    checked_func = function()
                        migrateLockscreenStyle()
                        local cur = G_reader_settings:has(K.LOCKSCREEN_STYLE_SETTING)
                            and G_reader_settings:readSetting(K.LOCKSCREEN_STYLE_SETTING)
                            or G_reader_settings:readSetting(K.STYLE_SETTING)
                        local mode = G_reader_settings:readSetting(K.LOCKSCREEN_MODE_SETTING)
                            or getStyleMode()
                        if mode == "random" or mode == "alternate" then return false end
                        return normalizeReceiptStyle(cur) == s
                    end,
                    callback = function()
                        G_reader_settings:saveSetting(K.LOCKSCREEN_STYLE_SETTING, s)
                        G_reader_settings:saveSetting(K.LOCKSCREEN_MODE_SETTING, "fixed")
                    end,
                    radio = true,
                }
            end
            for __, key in ipairs(TICKET_KEYS) do
                lockscreen_items[#lockscreen_items + 1] = {
                    text = TICKET_LABELS[key] or key,
                    checked_func = function()
                        migrateLockscreenStyle()
                        local cur = G_reader_settings:has(K.LOCKSCREEN_STYLE_SETTING)
                            and G_reader_settings:readSetting(K.LOCKSCREEN_STYLE_SETTING)
                            or G_reader_settings:readSetting(K.STYLE_SETTING)
                        local mode = G_reader_settings:readSetting(K.LOCKSCREEN_MODE_SETTING)
                            or getStyleMode()
                        if mode == "random" or mode == "alternate" then return false end
                        return cur == key
                    end,
                    callback = function()
                        G_reader_settings:saveSetting(K.LOCKSCREEN_STYLE_SETTING, key)
                        G_reader_settings:saveSetting(K.LOCKSCREEN_MODE_SETTING, "fixed")
                    end,
                    radio = true,
                }
            end
            lockscreen_items[#lockscreen_items + 1] = genLockscreenModeItem(
                _("Randomize style each time"), "random", K.LOCKSCREEN_MODE_SETTING)
            lockscreen_items[#lockscreen_items + 1] = genLockscreenModeItem(
                _("Alternate style each time"), "alternate", K.LOCKSCREEN_MODE_SETTING)
            local lockscreen_style_menu = {
                text = _("Lockscreen style"),
                sub_item_table = lockscreen_items,
            }
            table.insert(target_submenu, 7, {
                text = _("Show book receipt on sleep screen"),
                checked_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "book_receipt"
                end,
                callback = function()
                    local cur = G_reader_settings:readSetting("screensaver_type")
                    G_reader_settings:saveSetting("screensaver_type",
                        cur == "book_receipt" and "" or "book_receipt")
                end,
                radio = true,
            })
            table.insert(target_submenu, 8, {
                text = _("Book receipt settings"),
                enabled_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "book_receipt"
                end,
                sub_item_table = { style_menu, lockscreen_style_menu },
            })
            logger.info(LOG_TAG, "成功注入阅读摘要菜单")
        end)
        if not ok_inject then
            logger.warn(LOG_TAG, "菜单注入失败：", err_inject)
        end
    end
    return result
end

-- KOReader 插件框架要求 main.lua 返回带有 :new() 方法的表
local BookReceiptPlugin = {}

-- 让 FileManager 的 propagateEvent 不会在此插件实例上崩溃
function BookReceiptPlugin:handleEvent(event)
    return false
end

function BookReceiptPlugin:new(attr)
    local instance = {}
    setmetatable(instance, {__index = BookReceiptPlugin})
    instance:init(attr)
    return instance
end

function BookReceiptPlugin:init(attr)
    -- 插件初始化：加载样式模块
    -- 菜单注入通过劫持 dofile 实现，无需额外调用
    local ok, err = pcall(function()
        loadStyleModules()
    end)
    if not ok then
        logger.warn(LOG_TAG, "初始化失败:", err)
    end
end

return {
    new = BookReceiptPlugin.new,
    buildReceipt = buildReceipt,
    buildTicketWidget = buildTicketWidget,
    getEffectiveStyle = getEffectiveStyle,
    getLockscreenEffectiveStyle = getLockscreenEffectiveStyle,
    getRotationPool = getRotationPool,
    K = K,
    quicklookbox = quicklookbox,
}
