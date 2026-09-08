# Book Receipt / 阅读小票

> KOReader 墨水屏插件 —— 为每一段阅读留下凭证。

![Version](https://img.shields.io/badge/version-0.2.4-blue)
![Release](https://img.shields.io/badge/release-v0.2.4-brightgreen)
![KOReader](https://img.shields.io/badge/KOReader-插件-red)
![License](https://img.shields.io/badge/license-MIT-green)

## 简介

Book Receipt（阅读小票）把你的阅读数据变成一张可以收藏的「小票」。

插件内置 **十种样式**，**全部放进同一个轮换池** —— 不分主样式与票型，十种地位平等，
可以在固定 / 随机 / 轮流三种模式下自由展示。

## 十种样式（轮换池）

| 样式 | 说明 |
|------|------|
| 🎞️ 胶片票根 | 复古胶片风格，展示封面、阅读进度、累计时间 |
| 🖋️ 墨痕壁纸 | 全屏阅读统计，含折线图、书单、诗句点缀 |
| 🍽️ 菜单留台单 | 餐厅点菜风格，随机抽取菜谱、名言、诗词 |
| 🚉 站台 | 车站站台风格，展示书单与阅读轨迹 |
| 📅 日票 | 当日阅读轨迹，检票口设计 |
| 🗓️ 周票 | 七日活动日历，按天展示阅读记录 |
| 📆 月票 | 月度日历，**阅读日直接以书籍封面填充格子** |
| 📊 年票 | 年度阅读数据，12 月热力网格 |
| 📖 单书行程票 | 单本书的阅读旅程与时间线 |
| 🔒 阅读屏保票 | 全屏阅读历史摘要 |

## 展示模式

- **固定**：始终展示指定样式
- **随机**：每次从轮换池中随机抽取
- **轮流**：按顺序循环展示全部十种

## 触发方式

- **手势调出**：长按右上角（QuickLook 手势）
- **锁屏展示**：设置 → 屏保类型 → 选择「Book Receipt」

## 菜单设置

屏保菜单中新增「阅读摘要设置」：可分别配置手势调出与锁屏壁纸的展示模式。

## 下载与安装

### 直接下载（推荐）

前往 [Releases 页面](https://github.com/ksaMask123/book-receipt.koplugin/releases) 下载
`book-receipt.koplugin-v0.2.4.tar.gz`，解压后把 `book-receipt.koplugin` 整个目录
复制到 KOReader 的 `plugins/` 目录下，重启 KOReader 即可。

### 从源码安装

```bash
cp -r book-receipt.koplugin /path/to/koreader/plugins/
# 或
rsync -av book-receipt.koplugin/ /path/to/koreader/plugins/
```

## 版本记录

### v0.2.4（2026-09-08）

- 修复单书行程票「显示成上一本书」的问题：改为 md5 优先匹配（书名匹配作回退），
  匹配不到时显示当前书名 +「本书暂无阅读记录」，不再回退成别人的书
- 修复站台样式按钮点了没反应：原先调用了一个 KOReader 里根本不存在的前端模块，
  错误又被静默吞掉；现改为插件自带的开书模块
- 站台「继续阅读」和「正在阅读」改为跟随真实当前在读的书，不再受统计库落库时机影响
  （统计插件要攒满 50 次翻页才写库，刚换书时会误判成上一本）
- 新增书名→路径的 md5 兜底反查，解决书名对不上导致拿不到文件路径的问题
- 开书失败不再无声无息：会写入日志（标签 `[BookReceipt]`）并弹出提示

### v0.2.3（2026-09-07）

- 修复月票日期数字被书籍封面遮挡的问题
- 一天读 2 本及以上时，封面整体下移让出顶部日期条；单本仍保持铺满格子
- 日期白底小牌加大并随位数自适应，数字位置与无阅读日完全一致

### v0.2.2（2026-09-07）

- 月票日历改为「封面即格子」：1 本铺满、2 本左右并排、3 本及以上扇形叠放并带 `+N` 角标
- 取消原跨天跨度条，连读的书在每一天各放一张同封面
- 新增共享封面模块 `lib/cover_helper.lua`：元数据封面 → Kindle 侧车缩略图 → 书名占位牌三级回退
- 封面按需抽取（每轮限 3 本，结果持久化，避免首次渲染卡顿）

### v0.2.1（2026-09-07）

- 单书行程票超长书名改为最多两行显示（按真实渲染宽度切行，不再与右侧元素重叠）
- 单书行程票封面改为从书籍元数据获取，缺失时回退 Kindle 自生成封面
- 阅读时长统一改为以小时为单位（如「18.8小时」），修复多位数挤占右方文本的问题
- 字体优先级：优先使用用户当前阅读/UI 字体，系统字体仅作兜底

## 设计要点

- **墨水屏友好**：全部使用 Blitbuffer 矢量绘制，无位图依赖，刷新快
- **字体自适应**：优先用户阅读字体，逐级回退到系统字体，不会因缺字体而报错
- **封面三级回退**：元数据封面 → Kindle 原生缩略图 → 书名占位牌，全程 `pcall` 保护
- **内置文本库**：诗词、名言、菜谱随插件附带，无需联网即可随机抽取
- **扩展接口**：其他插件可通过 `BookReceiptRegistry` 注册自定义样式

## 文件结构

```
book-receipt.koplugin/
├── _meta.lua               # 插件元数据
├── main.lua                # 主入口：模式管理、菜单注入
├── README.md
├── CHANGELOG 见 audit/book-receipt-plugin_changelog.html
├── lib/
│   ├── rl_reference.lua    # 渲染工具与统计读取
│   ├── font_pref.lua       # 字体优先级（用户字体 > 系统字体）
│   ├── cover_helper.lua    # 封面获取（元数据/Kindle缩略图/占位，三级回退）
│   ├── poem_data.lua       # 诗词数据
│   ├── recipe_data.lua     # 菜谱数据
│   └── quotation_data.lua  # 名言数据
├── tickets/
│   ├── day.lua             # 日票
│   ├── week.lua            # 周票
│   ├── month.lua           # 月票（封面日历）
│   ├── year.lua            # 年票
│   ├── book.lua            # 单书行程票
│   └── screen.lua          # 阅读屏保票
├── styles/
│   ├── film.lua            # 胶片票根
│   ├── inkstain.lua        # 墨痕壁纸
│   ├── station.lua         # 站台
│   └── menu.lua            # 菜单留台单
└── assets/                 # 图标与二维码资源
```

## 更新日志

完整的逐次修改时间线（含根因分析、几何验算、验证结果）见：
[`audit/book-receipt-plugin_changelog.html`](audit/book-receipt-plugin_changelog.html)

## 许可证

MIT License

## 致谢

本插件由 [2-book-receipt-shortcut-and-lockscreen.lua](https://github.com/ksaMask123/Koreader.patches)
补丁整合改进而来，月票「封面即格子」的视觉思路参考了 covercalendar.koplugin。
感谢 KOReader 开放的插件架构与社区贡献者。
