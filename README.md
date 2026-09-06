# Book Receipt / 阅读小票

> KOReader 墨水屏阅读小票插件 — 为每一段阅读留下凭证。

![Version](https://img.shields.io/badge/version-0.2.0-blue)
[![GitHub](https://img.shields.io/badge/GitHub-%E4%BB%93%E5%BA%93-brightgreen)](https://github.com/ksaMask123/book-receipt.koplugin)
[![KOReader](https://img.shields.io/badge/KOReader-%E5%8D%A0%E7%94%A8%E6%8F%92%E4%BB%B6-red)](https://github.com/koreader/koreader)

---

## 📋 简介

Book Receipt（阅读小票）是一款面向 KOReader 的墨水屏插件，将你的阅读数据化作一张可收藏的「阅读小票」。

提供 **十种样式**，全部纳入轮换池，可通过手势或锁屏唤出。

---

## ✨ 功能特性

### 十种样式（轮换池）

| 样式 | 描述 |
|------|------|
| 🎞️ **胶片票根** | 经典复古风格，展示书籍封面、阅读进度、累计时间 |
| 🖋️ **墨痕壁纸** | 全屏阅读统计，含折线图、书单、诗句点缀 |
| 📜 **菜单留台单** | 餐厅点菜风格，随机抽取菜谱、名言、诗词组合 |
| 🚉 **站台样式** | 阅读主页风格，展示阅读统计概览 |
| 📅 **日票** | 当日阅读轨迹，检票口设计 |
| 🗓️ **周票** | 七日活动日历，按天展示阅读记录 |
| 📆 **月票** | 月度统计汇总，热力图概览 |
| 📊 **年票** | 年度阅读数据，12 月热力网格 |
| 📖 **单书行程票** | 单本书的阅读旅程和时间线 |
| 🔒 **阅读屏保票** | 全屏阅读历史摘要 |

### 三种展示模式

- **固定**：始终展示指定样式
- **随机**：每次随机从池中抽取
- **轮流**：按顺序循环展示所有样式

---

## 🚀 触发方式

### 手势调出
长按右上角（QuickLook 手势）呼出阅读小票

### 锁屏展示
设置 → 屏保类型 → 选择「Book Receipt」

---

## ⚙️ 菜单设置

屏保菜单中新增「阅读摘要设置」：
- 手势调出样式：固定 / 随机 / 轮流
- 锁屏壁纸样式：独立配置
- 所有样式统一纳入轮换池

---

## 📦 安装

### 方法一：直接复制

```bash
# 复制插件到 KOReader plugins 目录
cp -r book-receipt.koplugin /path/to/koreader/plugins/

# 或使用 rsync
rsync -av book-receipt.koplugin/ /path/to/koreader/plugins/
```

### 方法二：从 appstore 安装

如果已安装 [appstore.koplugin](https://github.com/ksaMask123/appstore.koplugin)，可在插件商店中搜索「Book Receipt」一键安装。

---

## 🔧 依赖

- KOReader 核心库
- readingline.koplugin（用于读取阅读统计数据）

---

## 🏗️ 文件结构

```
book-receipt.koplugin/
├── _meta.lua              # 插件元数据
├── main.lua               # 主入口：模式管理、菜单注入
├── README.md
├── lib/
│   ├── font_pref.lua       # 字体优先级管理
│   ├── rl_reference.lua    # 渲染工具函数
│   ├── poem_data.lua       # 诗词数据（200条）
│   ├── poem_text.lua       # 诗词文本
│   ├── quotation_data.lua  # 名言数据（200条）
│   ├── quotation_text.lua  # 名言文本
│   ├── recipe_data.lua     # 菜谱数据（250道）
│   └── recipe_text.lua     # 菜谱文本
├── tickets/
│   ├── day.lua            # 日票渲染
│   ├── week.lua           # 周票渲染
│   ├── month.lua          # 月票渲染
│   ├── year.lua           # 年票渲染
│   ├── book.lua           # 单书行程票
│   └── screen.lua         # 阅读屏保票
├── styles/
│   ├── film.lua           # 胶片票根
│   ├── inkstain.lua       # 墨痕壁纸
│   ├── menu.lua           # 菜单样式
│   └── station.lua        # 站台样式
├── assets/
│   ├── github_qr.png      # GitHub 仓库二维码
│   └── train-icons-svg/   # 复古火车票图标集
└── train-icons-svg/       # 扩展图标资源
```

---

## 🎨 设计亮点

- **墨水屏友好**：所有渲染使用 Blitbuffer 矢量绘制，无位图依赖，刷新快
- **字体自适应**：优先使用用户阅读字体，自动回退至 KOReader 系统字体
- **扩展接口**：其他插件可通过 `BookReceiptRegistry` 注册自定义样式
- **数据独立**：内置诗词、名言、菜谱文本库，无需联网即可随机抽取

---

## 📝 扩展接口

其他插件可通过以下接口注册新样式：

```lua
-- 在插件初始化时注册
local br = _G.BookReceiptRegistry
br.register("my_style", {
    func = function(bb, x, y, w, h, ref_date)
        -- 渲染逻辑
    end,
    label = "我的样式",
})
```

---

## 🔮 开发状态

- ✅ 四种主样式（胶片 / 墨痕 / 菜单 / 站台）完整实现
- ✅ 六种票型（日 / 周 / 月 / 年 / 单书 / 屏保）全部上线
- ✅ 固定 / 随机 / 轮流三种模式
- ✅ 手势调出集成（QuickLook）
- ✅ 锁屏展示集成
- ✅ 菜单设置注入
- ✅ 字体优先级优化（用户字体 > 系统字体）
- ✅ 真机验证通过（KPW3 / kindlea9）

---

## 📄 许可证

MIT License

---

## 🙏 致谢

本插件基于 [2-book-receipt-shortcut-and-lockscreen.lua](https://github.com/ksaMask123/Koreader.patches) 补丁整合改进，面向 KOReader 社区开源发布。

特别感谢：
- [KOReader](https://github.com/koreader/koreader) 开放插件架构
- [readingline.koplugin](https://github.com/koreader/koreader) 提供阅读数据统计接口
- 所有 KOReader 社区贡献者

---

**让每一段阅读都值得纪念。** 📚✨
