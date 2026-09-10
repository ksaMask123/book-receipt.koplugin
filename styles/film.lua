-- film.lua - 胶片票根样式（移植自补丁 buildFilmReceipt）
-- 完整复刻原补丁的所有视觉元素

local BB = require("ffi/blitbuffer")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local TextWidget = require("ui/widget/textwidget")
local ProgressWidget = require("ui/widget/progresswidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local Geom = require("ui/geometry")
local datetime = require("datetime")
local _ = require("gettext")
local RenderImage = require("ui/renderimage")
local util = require("util")
local ffiUtil = require("ffi/util")
local rl = require("lib.rl_reference")
local font_pref = require("lib.font_pref")
local lastread = require("lib.lastread")
local logger = require("logger")

local LOG_TAG = "[BookReceipt.Film]"

local K = {
    BG_SETTING = "book_receipt_screensaver_background",
    CONTENT_MODE_SETTING = "book_receipt_content_mode",
    COVER_SCALE_SETTING = "book_receipt_cover_scale",
    STYLE_FILM = "film",
    CONTENT_MODE_BOOK_RECEIPT = "book_receipt",
    CONTENT_MODE_HIGHLIGHT_PROGRESS = "highlight_progress",
    CONTENT_MODE_RANDOM = "random",
    SLEEP_TEXT = "book_receipt_sleep_text",
}

local MAX_HIGHLIGHT_SIZE = 60

local function getLocalizedDayName(timestamp)
    local day_key = timestamp and os.date("%A", timestamp)
    if not day_key then return "" end
    if datetime and datetime.longDayTranslation and datetime.longDayTranslation[day_key] then
        return datetime.longDayTranslation[day_key]
    end
    return _(day_key)
end

local function secs_to_timestring(secs)
    if not secs then return "正在计算时间" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h == 0 and m > 0 then return string.format("%i分钟", m)
    elseif h > 0 and m == 0 then return string.format("%i小时", h)
    elseif h > 0 and m > 0 then return string.format("%i小时 %i分钟", h, m)
    elseif h == 0 and m == 0 then return "少于一分钟" end
    return "正在计算时间"
end

-- 加权截断：防止超长文件名挤爆排版
local function utf8TrimToLength(str, max_chars)
    str = tostring(str or "")
    if #str <= max_chars then return str, #str, false end
    local chars = {}
    local count = 0
    for i = 1, #str do
        local byte = string.byte(str, i)
        local clen = 1
        if byte >= 0xF0 then clen = 4
        elseif byte >= 0xE0 then clen = 3
        elseif byte >= 0xC0 then clen = 2
        end
        count = count + 1
        if count > max_chars - 3 then break end
        table.insert(chars, str:sub(i, i + clen - 1))
        i = i + clen - 1
    end
    table.insert(chars, "...")
    return table.concat(chars), count, true
end

-- 加权截断字符串（按权重字符数）
local function getWeightedTruncatedString(str, max_weight)
    str = tostring(str or "")
    if str == "" then return str, 0, false end
    local weight = 0
    local chars = rl.utf8Chars(str)
    local result = {}
    for _, ch in ipairs(chars) do
        local b = string.byte(ch, 1)
        local cw = (b >= 0x80) and 2 or 1
        if weight + cw > max_weight then break end
        weight = weight + cw
        table.insert(result, ch)
    end
    local truncated = weight > #chars * 2  -- 粗略判断是否截断
    return table.concat(result), weight, truncated
end

local function build(ui, state, on_close_callback)
    -- 没有打开书籍时不再直接放弃渲染，改用「最近阅读的书」兜底。
    -- 原写法 `if not ui or not ui.document then return nil end` 会导致：
    --   锁屏 → main.lua 回退系统默认屏保；手势 → 弹出「无法显示阅读摘要」
    -- 也就是用户看到的"胶片唤不出"。
    -- 兜底只在"确实没有活动文档"时启用，绝不覆盖"有书但统计库尚未落库"的情形
    -- （后者若被覆盖，会退回上一本书，即 v0.2.3 已修掉的旧 bug）。
    if not ui then return nil end

    local has_document = ui.document ~= nil
    local last_read = nil
    if not has_document then
        local ok_lr, lr = pcall(lastread.resolve)
        if ok_lr then last_read = lr end
        if not last_read then
            logger.dbg(LOG_TAG, "无活动文档且无最近阅读记录，胶片放弃渲染")
            return nil
        end
    end

    local doc_props = ui.doc_props or {}
    local book_title = doc_props.display_title or ""
    local doc_settings = ui.doc_settings and ui.doc_settings.data or {}
    local doc_page_no, doc_page_total
    -- 页数是否可信：无活动文档且统计库没给页数时，票面显示占位符，不编造 1/1
    local has_page_data = true
    if has_document then
        doc_page_no = (state and state.page) or 1
        doc_page_total = doc_settings.doc_pages or 1
    else
        if book_title == "" then book_title = last_read.title or "" end
        doc_page_no = last_read.page or 0
        doc_page_total = last_read.pages or 0
        if doc_page_total <= 0 or doc_page_no <= 0 then has_page_data = false end
    end
    if doc_page_total <= 0 then doc_page_total = 1 end
    if doc_page_no < 1 then doc_page_no = 1 end
    if doc_page_no > doc_page_total then doc_page_no = doc_page_total end

    local page_left = has_page_data and math.max(doc_page_total - doc_page_no, 0) or 0
    local toc = has_document and ui.toc or nil
    local chapter_title = ""
    local chapter_total = doc_page_total
    local chapter_left = 0
    local chapter_done = 0
    if toc then
        chapter_title = toc:getTocTitleByPage(doc_page_no) or ""
        chapter_total = toc:getChapterPageCount(doc_page_no) or chapter_total
        chapter_left = toc:getChapterPagesLeft(doc_page_no) or 0
        chapter_done = toc:getChapterPagesDone(doc_page_no) or 0
    end
    chapter_total = chapter_total > 0 and chapter_total or doc_page_total
    chapter_done = math.max(chapter_done + 1, 1)

    local statistics = ui.statistics
    local avg_time_per_page = statistics and statistics.avg_time
    -- 无活动文档时没有 ui.statistics，改用统计库累计值反推每页均速
    if (not avg_time_per_page) and last_read then
        avg_time_per_page = last_read.avg_time
    end
    local book_time_left = secs_to_timestring(avg_time_per_page and avg_time_per_page * page_left)
    local chapter_time_left = secs_to_timestring(avg_time_per_page and avg_time_per_page * chapter_left)
    local current_time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) or ""
    local battery = ""
    if Device:hasBattery() then
        local power_dev = Device:getPowerDevice()
        local batt_lvl = power_dev:getCapacity() or 0
        local is_charging = power_dev:isCharging() or false
        local batt_prefix = power_dev:getBatterySymbol(power_dev:isCharged(), is_charging, batt_lvl) or ""
        battery = batt_prefix .. batt_lvl .. "%"
    end

    local widget_width = math.floor(Screen:getWidth() * 0.68)
    local db_font_color = BB.COLOR_BLACK
    local db_font_color_lighter = BB.COLOR_GRAY_3
    local db_font_color_lightest = BB.COLOR_GRAY_9
    local db_font_face = "NotoSans-Regular.ttf"
    local db_font_face_italics = "NotoSans-Italic.ttf"
    local db_font_size_huge = 64
    local db_font_size_big = 28
    local db_font_size_mid = 21
    local db_font_size_small = 16
    local db_padding = 20
    local db_padding_internal = 8

    local function databox(typename, itemname, pages_done, pages_total, time_left_text, pages_done_display, pages_total_display, options)
        options = options or {}
        local pages_done_num = tonumber(pages_done) or 0
        local pages_total_num = tonumber(pages_total) or 0
        local denom = pages_total_num > 0 and pages_total_num or 1
        local percentage_value = math.max(math.min(pages_done_num / denom, 1), 0)
        local display_done = pages_done_display or pages_done
        local display_total = pages_total_display or pages_total
        local elements = {}
        local progress_side_padding = Screen:scaleBySize(30)
        local progressbarwidth = widget_width - (progress_side_padding * 2)

        -- 1. 顶部标题
        if not options.hide_title then
            local MAX_WEIGHT = 28
            local safe_text, was_truncated = getWeightedTruncatedString(itemname, MAX_WEIGHT)
            local adaptive_size = db_font_size_mid
            if was_truncated then adaptive_size = math.floor(db_font_size_mid * 0.9) end
            local title_widget = TextWidget:new{
                face = font_pref.getPreferredFontFace(adaptive_size, db_font_face),
                text = safe_text,
                fgcolor = db_font_color,
                align = "left",
            }
            local title_right_w = widget_width - progress_side_padding - title_widget:getSize().w
            if title_right_w < 0 then title_right_w = 0 end
            table.insert(elements, HorizontalGroup:new{
                HorizontalSpan:new{ width = progress_side_padding },
                title_widget,
                HorizontalSpan:new{ width = title_right_w },
            })
            table.insert(elements, VerticalSpan:new{ width = Screen:scaleBySize(4) })
        end

        -- 2. 剩余时间
        if not options.hide_time and time_left_text then
            local time_text_widget = TextWidget:new{
                text = string.format("%s还需 %s", typename, time_left_text),
                face = font_pref.getPreferredFontFace(db_font_size_small, db_font_face_italics),
                bold = false,
                fgcolor = db_font_color_lighter,
                padding = 0,
                align = "left",
            }
            local right_space_w = widget_width - progress_side_padding - time_text_widget:getSize().w
            if right_space_w < 0 then right_space_w = 0 end
            table.insert(elements, HorizontalGroup:new{
                HorizontalSpan:new{ width = progress_side_padding },
                time_text_widget,
                HorizontalSpan:new{ width = right_space_w },
            })
            table.insert(elements, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        end

        -- 3. 进度条主体
        local progress_bar = ProgressWidget:new{
            width = progressbarwidth, height = Screen:scaleBySize(6),
            percentage = percentage_value, margin_v = 0, margin_h = 0,
            radius = 20, bordersize = 0,
            bgcolor = db_font_color_lightest, fillcolor = db_font_color,
        }
        table.insert(elements, HorizontalGroup:new{
            HorizontalSpan:new{ width = progress_side_padding },
            progress_bar,
            HorizontalSpan:new{ width = progress_side_padding },
        })
        table.insert(elements, VerticalSpan:new{ width = Screen:scaleBySize(6) })

        -- 4. 页数 / 百分比
        local page_progress = TextWidget:new{
            text = string.format("第 %s 页 / 共 %s 页", display_done, display_total),
            face = rl.getFontFace(db_font_size_small),
            bold = false, fgcolor = db_font_color_lighter, padding = 0, align = "left",
        }
        local percentage_display = TextWidget:new{
            text = string.format("%i%%", math.floor(percentage_value * 100 + 0.5)),
            face = rl.getFontFace(db_font_size_small),
            bold = false, fgcolor = db_font_color_lighter, padding = 0, align = "right",
        }
        table.insert(elements, HorizontalGroup:new{
            HorizontalSpan:new{ width = progress_side_padding },
            page_progress,
            HorizontalSpan:new{ width = math.max(0, progressbarwidth - page_progress:getSize().w - percentage_display:getSize().w) },
            percentage_display,
            HorizontalSpan:new{ width = progress_side_padding },
        })
        table.insert(elements, VerticalSpan:new{ width = db_padding_internal })
        return VerticalGroup:new(elements)
    end

    local batt_pct_box = TextWidget:new{ text = battery, face = rl.getFontFace(db_font_size_small), bold = false, fgcolor = db_font_color, padding = 0 }
    local glyph_clock = "⌚"
    local time_box = TextWidget:new{ text = string.format("%s%s", glyph_clock, current_time), face = rl.getFontFace(db_font_size_small), bold = false, fgcolor = db_font_color, padding = 0 }
    local bottom_bar_inner = HorizontalGroup:new{ batt_pct_box, HorizontalSpan:new{ width = db_padding }, time_box }
    local bottom_bar = CenterContainer:new{ dimen = Geom:new{ w = widget_width, h = bottom_bar_inner:getSize().h }, bottom_bar_inner }

    local bookboxtitle = "总进度"

    local content_mode_setting = G_reader_settings:readSetting(K.CONTENT_MODE_SETTING) or K.CONTENT_MODE_BOOK_RECEIPT
    local content_mode = content_mode_setting
    if content_mode_setting == K.CONTENT_MODE_RANDOM then
        local candidates = { K.CONTENT_MODE_BOOK_RECEIPT, K.CONTENT_MODE_HIGHLIGHT_PROGRESS }
        content_mode = candidates[math.random(#candidates)]
    end

    local book_total_time_text
    local book_today_time_text
    -- statistics 对象不一定有 book_read_time 字段，安全访问
    if statistics then
        local brt = statistics.book_read_time
        if brt then
            book_total_time_text = string.format("全书已阅读：%s", secs_to_timestring(tonumber(brt) or 0))
        end
    end
    -- 无活动文档时用统计库累计时长补上
    if (not book_total_time_text) and last_read and (last_read.total_time or 0) > 0 then
        book_total_time_text = string.format("全书已阅读：%s", secs_to_timestring(last_read.total_time))
    end

    local bookbox = databox("全书", bookboxtitle, doc_page_no, doc_page_total, book_time_left,
        has_page_data and doc_page_no or "--",
        has_page_data and doc_page_total or "--", {
        hide_title = content_mode == K.CONTENT_MODE_HIGHLIGHT_PROGRESS,
        hide_time = content_mode == K.CONTENT_MODE_HIGHLIGHT_PROGRESS,
    })
    -- 本章进度：目录只有真正打开文档才存在，无书时必然取不到。
    -- 按用户要求保留等高占位块（结构与正常"本章"一致，数字换成占位符），
    -- 既不让票面塌陷，也不显示编造出来的 1/1 假进度。
    local chapterbox
    if content_mode ~= K.CONTENT_MODE_HIGHLIGHT_PROGRESS then
        if toc then
            chapterbox = databox("本章", chapter_title, chapter_done, chapter_total, chapter_time_left)
        else
            chapterbox = databox("本章", "暂无本章信息", 0, 0, "--", "--", "--")
        end
    end

    local bg_choice = G_reader_settings:readSetting(K.BG_SETTING)
    local show_cover = not (Device.screen_saver_mode and bg_choice == "book_cover")
    local top_split_widget = nil

    -- 构建卡片顶部的封面、日期区域
    local cover_scale = G_reader_settings:readSetting(K.COVER_SCALE_SETTING) or 1
    local max_cover_width = math.max(1, math.floor(widget_width * 0.25 * cover_scale))
    local max_cover_height = math.max(1, math.floor(Screen:getHeight() / 5 * cover_scale))
    local cover_image_widget = nil
    if show_cover then
        if has_document and ui.bookinfo then
            -- 原路径：从文档实例取封面，再按目标尺寸等比缩放
            local ok_cover, cover_bb = pcall(function()
                return ui.bookinfo:getCoverImage(ui.document)
            end)
            if not ok_cover then cover_bb = nil end
            if cover_bb then
                local cover_width = cover_bb:getWidth()
                local cover_height = cover_bb:getHeight()
                local scale = math.min(1, max_cover_width / cover_width, max_cover_height / cover_height)
                if scale < 1 then
                    local scaled_w = math.max(1, math.floor(cover_width * scale))
                    local scaled_h = math.max(1, math.floor(cover_height * scale))
                    cover_bb = RenderImage:scaleBlitBuffer(cover_bb, scaled_w, scaled_h, true)
                    cover_width = scaled_w
                    cover_height = scaled_h
                end
                cover_image_widget = ImageWidget:new{ image = cover_bb, width = cover_width, height = cover_height }
            end
        elseif last_read and last_read.path ~= "" then
            -- 无活动文档：按文件路径取封面（CoverBrowser 缓存优先，不打开文档，避免阻塞锁屏）
            local ok_cover, cover_widget = pcall(rl.getBookCoverFromPath, last_read.path, max_cover_width, max_cover_height)
            if ok_cover and cover_widget then
                cover_image_widget = cover_widget
            else
                logger.dbg(LOG_TAG, "无书封面提取失败:", tostring(cover_widget))
            end
        end
    end
    if show_cover and cover_image_widget then
        do
            local framed_cover = FrameContainer:new{ radius = 15, bordersize = 2, padding = 0, background = BB.COLOR_WHITE, cover_image_widget }
            local now_t = os.time()
            local cal_day = os.date("%d", now_t)
            local cal_year_month = os.date("%Y.%m", now_t)
            local cal_weekday = getLocalizedDayName(now_t)
            local font_scale = (cover_scale and cover_scale > 0.1) and cover_scale or 1
            local f_size_small = math.floor(db_font_size_small * font_scale)
            local f_size_huge = math.floor(28 * font_scale)
            local f_size_mid = math.floor(db_font_size_mid * font_scale)
            local gap_size = 0
            if Device.screen_saver_mode then
                cal_year_month = os.date("%m.%d", now_t)
                cal_day = G_reader_settings:readSetting(K.SLEEP_TEXT) or "休眠中"
                f_size_huge = math.floor(28 * font_scale)
                gap_size = math.floor(30 * font_scale)
            end
            local f_size_deco = math.floor(10 * font_scale)
            local span_deco_h = math.floor(4 * font_scale)
            local calendar_group = VerticalGroup:new{
                align = "center",
                TextWidget:new{ text = cal_year_month, face = Font:getFace("cfont", f_size_small), fgcolor = db_font_color_lighter },
                VerticalSpan:new{ width = gap_size },
                TextWidget:new{ text = cal_day, face = Font:getFace("cfont", f_size_huge), bold = true, fgcolor = db_font_color, padding = 0 },
                VerticalSpan:new{ width = gap_size },
                TextWidget:new{ text = cal_weekday, face = Font:getFace("cfont", f_size_mid), fgcolor = db_font_color },
            }
            local deco_group = nil
            local deco_w = 0
            if cover_scale < 2 then
                local deco_elements = {}
                local deco_count = 8
                for i = 1, deco_count do
                    table.insert(deco_elements, TextWidget:new{ text = "|", face = Font:getFace("cfont", f_size_deco), fgcolor = db_font_color_lighter, padding = 0 })
                    if i < deco_count then table.insert(deco_elements, VerticalSpan:new{ width = span_deco_h }) end
                end
                deco_group = VerticalGroup:new(deco_elements)
                deco_w = deco_group:getSize().w
            end
            local available_side_width = math.floor((widget_width - deco_w) / 2)
            local section_height = math.max(framed_cover:getSize().h, calendar_group:getSize().h)
            local left_area = CenterContainer:new{ dimen = Geom:new{ w = available_side_width, h = section_height }, framed_cover }
            local right_area = CenterContainer:new{ dimen = Geom:new{ w = available_side_width, h = section_height }, calendar_group }
            local top_group_elements = { left_area }
            if deco_group then
                local center_area = CenterContainer:new{ dimen = Geom:new{ w = deco_w, h = section_height }, deco_group }
                table.insert(top_group_elements, center_area)
            end
            table.insert(top_group_elements, right_area)
            top_split_widget = HorizontalGroup:new(top_group_elements)
        end
    end

    local content_children = {}
    local full_ticket_width = widget_width + (db_padding * 2)
    table.insert(content_children, HorizontalSpan:new{ width = full_ticket_width })

    local highlight_widgets
    local highlight_length = 0
    if content_mode == K.CONTENT_MODE_HIGHLIGHT_PROGRESS then
        -- 高亮模式暂不支持，回退到普通模式
        content_mode = K.CONTENT_MODE_BOOK_RECEIPT
    end

    if content_mode == K.CONTENT_MODE_BOOK_RECEIPT then
        show_cover = not (Device.screen_saver_mode and bg_choice == "book_cover")
    else
        if bg_choice == "book_cover" then show_cover = false end
    end

    if top_split_widget and show_cover then
        table.insert(content_children, top_split_widget)
        table.insert(content_children, VerticalSpan:new{ width = db_padding_internal })
        -- 模拟虚线撕口
        table.insert(content_children, TextWidget:new{
            text = "- - - - - - - - - - - - - - - - - - - - - - - -",
            face = rl.getFontFace(db_font_size_small),
            fgcolor = db_font_color_lighter,
            align = "center"
        })
        table.insert(content_children, VerticalSpan:new{ width = db_padding })

        -- 获取文件名作为胶片标题（原补丁逻辑）
        -- 无活动文档时用最近阅读书的文件名，保证胶片标题栏不是空的
        local file_path = (ui.document and ui.document.file) or (last_read and last_read.path) or ""
        local raw_file_name = file_path ~= "" and ffiUtil.basename(file_path) or book_title
        local name_no_ext = raw_file_name:match("^(.+)%.[^%.]+$")
        if name_no_ext then raw_file_name = name_no_ext end
        if raw_file_name == "" then raw_file_name = "READING TICKET" end
        local display_file_name = getWeightedTruncatedString(raw_file_name, 24)

        -- 插入胶片标题栏
        local FilmStripTitle = FrameContainer:extend{
            background = BB.COLOR_BLACK,
            bordersize = 0,
            padding = 0,
            margin = 0,
            title_text = display_file_name,
            title_font_size = math.floor(db_font_size_huge * 0.45),
        }
        function FilmStripTitle:init()
            local w = self.width
            local hole_size = Screen:scaleBySize(5)
            local hole_gap = Screen:scaleBySize(5)
            local available_w = w - (hole_gap * 2)
            local num_holes = math.floor((available_w + hole_gap) / (hole_size + hole_gap))
            if num_holes < 1 then num_holes = 1 end
            local function createHole()
                return FrameContainer:new{
                    bordersize = 0,
                    padding_left = hole_size,
                    padding_top = hole_size,
                    padding_right = 0,
                    padding_bottom = 0,
                    background = BB.COLOR_WHITE,
                    HorizontalSpan:new{ width = 0 }
                }
            end
            local top_holes = {}
            local bottom_holes = {}
            table.insert(top_holes, HorizontalSpan:new{ width = hole_gap })
            table.insert(bottom_holes, HorizontalSpan:new{ width = hole_gap })
            for i = 1, num_holes do
                table.insert(top_holes, createHole())
                table.insert(bottom_holes, createHole())
                if i < num_holes then
                    table.insert(top_holes, HorizontalSpan:new{ width = hole_gap })
                    table.insert(bottom_holes, HorizontalSpan:new{ width = hole_gap })
                end
            end
            table.insert(top_holes, HorizontalSpan:new{ width = hole_gap })
            table.insert(bottom_holes, HorizontalSpan:new{ width = hole_gap })
            local top_row = CenterContainer:new{ dimen = Geom:new{ w = w, h = hole_size }, HorizontalGroup:new(top_holes) }
            local bottom_row = CenterContainer:new{ dimen = Geom:new{ w = w, h = hole_size }, HorizontalGroup:new(bottom_holes) }
            local title_widget = TextWidget:new{
                text = self.title_text,
                face = font_pref.getPreferredFontFace(self.title_font_size, "cfont"),
                bold = true,
                fgcolor = BB.COLOR_WHITE,
                align = "center"
            }
            self[1] = VerticalGroup:new{
                VerticalSpan:new{ width = hole_gap },
                top_row,
                VerticalSpan:new{ width = Screen:scaleBySize(10) },
                title_widget,
                VerticalSpan:new{ width = Screen:scaleBySize(10) },
                bottom_row,
                VerticalSpan:new{ width = hole_gap },
            }
        end
        table.insert(content_children, FilmStripTitle:new{ width = full_ticket_width })
        table.insert(content_children, VerticalSpan:new{ width = db_padding })
    end

    if content_mode ~= K.CONTENT_MODE_HIGHLIGHT_PROGRESS and chapterbox then
        table.insert(content_children, chapterbox)
        table.insert(content_children, VerticalSpan:new{ width = db_padding })
    end
    table.insert(content_children, bookbox)

    if content_mode ~= K.CONTENT_MODE_HIGHLIGHT_PROGRESS then
        table.insert(content_children, VerticalSpan:new{ width = db_padding })

        -- 阅读洞察按钮
        local badge_size = Screen:scaleBySize(35)
        local badge_btn = require("ui/widget/button"):new{
            text = "✿", text_face = rl.getFontFace(db_font_size_mid),
            fg_color = db_font_color, background = BB.COLOR_WHITE,
            bordersize = 0, padding = 0, width = badge_size, height = badge_size,
            callback = function()
                if on_close_callback then on_close_callback() end
                UIManager:setDirty(nil, "full")
                UIManager:scheduleIn(0.25, function()
                    local Event = require("ui/event")
                    local InfoMessage = require("ui/widget/infomessage")
                    local ok, err = pcall(function()
                        UIManager:broadcastEvent(Event:new("ShowReadingInsightsPopup"))
                    end)
                    if not ok then
                        UIManager:show(InfoMessage:new{
                            text = "无法打开阅读洞察，请确认插件已正确安装"
                        })
                    end
                end)
            end,
        }
        local separator_row = HorizontalGroup:new{
            align = "center",
            TextWidget:new{ text = "- - - - - - -", face = rl.getFontFace(db_font_size_small), fgcolor = db_font_color_lighter, padding = 0, align = "right" },
            HorizontalSpan:new{ width = db_padding_internal },
            badge_btn,
            HorizontalSpan:new{ width = db_padding_internal },
            TextWidget:new{ text = "- - - - - - -", face = rl.getFontFace(db_font_size_small), fgcolor = db_font_color_lighter, padding = 0, align = "left" },
        }
        table.insert(content_children, separator_row)
        table.insert(content_children, VerticalSpan:new{ width = db_padding_internal })

        if not Device.screen_saver_mode then
            table.insert(content_children, bottom_bar)
            table.insert(content_children, VerticalSpan:new{ width = db_padding_internal })
        end

        local stats_elements = {}
        if book_total_time_text then
            table.insert(stats_elements, TextWidget:new{
                text = book_total_time_text,
                face = font_pref.getPreferredFontFace(db_font_size_small, db_font_face_italics),
                fgcolor = db_font_color,
                align = "center"
            })
        end
        if book_total_time_text and book_today_time_text then
            table.insert(stats_elements, VerticalSpan:new{ width = db_padding_internal })
        end
        if book_today_time_text then
            table.insert(stats_elements, TextWidget:new{
                text = book_today_time_text,
                face = font_pref.getPreferredFontFace(db_font_size_small, db_font_face_italics),
                fgcolor = db_font_color,
                align = "center"
            })
        end
        if #stats_elements > 0 then
            table.insert(content_children, VerticalGroup:new(stats_elements))
        end
    end

    content_children.align = "center"
    local inner_ticket = FrameContainer:new{
        radius = 25,
        bordersize = 1,
        padding_top = db_padding,
        padding_right = 0,
        padding_bottom = db_padding,
        padding_left = 0,
        background = BB.COLOR_WHITE,
        VerticalGroup:new(content_children)
    }

    local ticket_size = inner_ticket:getSize()
    local shadow_width_offset = Screen:scaleBySize(10)
    local shadow_shrink_offset = Screen:scaleBySize(20)
    local shadow_rect_w = math.max(1, math.floor(ticket_size.w + shadow_width_offset - shadow_shrink_offset))
    local shadow_rect_h = math.max(1, math.floor(ticket_size.h + shadow_width_offset - shadow_shrink_offset))
    local shadow_rect = FrameContainer:new{
        background = BB.COLOR_GRAY_B,
        bordersize = 0,
        radius = 25,
        padding = 0,
        margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = shadow_rect_w, h = shadow_rect_h },
            HorizontalSpan:new{ width = 0 }
        }
    }
    local shadow_layer = FrameContainer:new{
        bordersize = 0,
        padding_top = shadow_shrink_offset,
        padding_left = shadow_shrink_offset + shadow_width_offset,
        padding_right = 0,
        padding_bottom = 0,
        shadow_rect
    }
    local ticket_layer = FrameContainer:new{
        bordersize = 0,
        padding_top = 0,
        padding_left = shadow_width_offset,
        padding_right = shadow_width_offset,
        padding_bottom = shadow_width_offset,
        inner_ticket
    }
    local overlap = OverlapGroup:new{
        dimen = Geom:new{ w = math.floor(ticket_size.w + shadow_width_offset * 2), h = math.floor(ticket_size.h + shadow_width_offset) },
        shadow_layer,
        ticket_layer
    }
    return CenterContainer:new{ dimen = Screen:getSize(), overlap }
end

return {
    build = build,
    hasActiveDocument = function(ui) return ui and ui.document ~= nil end,
}
