-- font_pref.lua — 用户字体优先辅助（2026-09-06 优化）
-- 所有样式统一：优先使用用户当前字体（阅读字体 / UI 字体），
-- 其次回退到 KOReader 系统 cfont（Noto Sans CJK，系统 CJK 兜底字体）。
-- 依据用户要求：本插件不自带字体，优先使用用户当前字体，其次系统 cfont。

local Font = require("ui/font")

-- 安全尝试取得某个字体家族名的 face（pcall 包裹，避免未知字体名导致崩溃）
local function tryFace(name, sz)
    if type(name) ~= "string" or name == "" then return nil end
    local ok, face = pcall(Font.getFace, Font, name, sz)
    if ok and face then return face end
    return nil
end

-- 取得用户当前字体家族名（字符串），无则返回 nil
-- 优先级：阅读中当前文档字体 > 全局 UI 字体 > 阅读字体持久化键(cre_font)
local function getUserPreferredFont()
    -- 1) 阅读中当前文档字体（最贴合「我的阅读字体」）
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok and ReaderUI and ReaderUI.instance then
        local doc = ReaderUI.instance.document
        if doc and doc.configurable and type(doc.configurable.font_face) == "string" and doc.configurable.font_face ~= "" then
            return doc.configurable.font_face
        end
    end
    -- 2) 全局 UI 字体（「我的 UI 字体」）
    if G_reader_settings then
        local ui = G_reader_settings:readSetting("ui_font_family")
        if type(ui) == "string" and ui ~= "" then return ui end
        local ui2 = G_reader_settings:readSetting("ui_font")
        if type(ui2) == "string" and ui2 ~= "" then return ui2 end
        -- 3) 阅读字体持久化键（锁屏 / 无运行实例时回退）
        local cre = G_reader_settings:readSetting("cre_font")
        if type(cre) == "string" and cre ~= "" then return cre end
    end
    return nil
end

-- 取得最终渲染用的字体 face
-- size: 字号；fallback_font: 插件/样式默认字体（如 "cfont" / "NotoSans-Regular.ttf"）
-- 优先级：用户字体 > fallback_font > cfont
local function getPreferredFontFace(size, fallback_font)
    local sz = math.max(8, math.floor(size))
    local user_font = getUserPreferredFont()
    local face = tryFace(user_font, sz)
    if face then return face end
    face = tryFace(fallback_font, sz)
    if face then return face end
    return Font:getFace("cfont", sz)
end

return {
    getUserPreferredFont = getUserPreferredFont,
    getPreferredFontFace = getPreferredFontFace,
}
