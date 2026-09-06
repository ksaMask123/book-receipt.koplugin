# Book Receipt (阅读小票)

KOReader 插件：在锁屏界面和手势操作中展示多种阅读小票样式。

## 功能特性

### 样式（固定展示）
- **胶片票根**：经典复古风格，显示书籍封面、进度、时间
- **墨痕壁纸**：全屏阅读统计，含折线图、书单、诗句
- **菜单样式**：留台单风格，展示菜谱、名言、设备信息

### 票型（轮换池）
- **日票**：当日阅读轨迹，检票口设计
- **周票**：七日活动日历，按天展示阅读记录
- **月票**：月度统计汇总，热力图概览
- **年票**：年度阅读数据，12月热力网格
- **单书行程票**：单本书的阅读旅程和时间线
- **阅读屏保票**：全屏阅读历史摘要

### 模式
- **固定**：始终展示指定样式
- **随机**：每次随机抽取样式或票型
- **轮流**：按顺序循环展示所有选项

## 触发方式

### 手势调出
长按右上角（QuickLook 手势）呼出阅读小票

### 锁屏展示
设置 → 屏保类型 → 选择「Book Receipt」

## 菜单设置

屏保菜单中新增「阅读摘要设置」：
- 手势调出样式：固定/随机/轮流
- 锁屏壁纸样式：独立配置
- 票型全部并入轮换池，无需手动单选

## 安装

```bash
# 复制插件到 KOReader plugins 目录
cp -r book-receipt.koplugin /path/to/koreader/plugins/

# 或使用 rsync
rsync -av book-receipt.koplugin/ /path/to/koreader/plugins/
```

重启 KOReader 后生效。

## 依赖

- KOReader 核心库
- readingline.koplugin（用于阅读数据统计读取）

## 扩展接口

其他插件可通过以下接口注册新票型：

```lua
-- 在插件初始化时注册
local br = _G.BookReceiptRegistry
br.register("my_ticket", {
    func = function(bb, x, y, w, h, ref_date)
        -- 渲染逻辑
    end,
    label = "我的票型",
})
```

## 文件结构

```
book-receipt.koplugin/
├── _meta.lua              # 插件元数据
├── main.lua               # 主入口：模式管理、菜单注入
├── README.md
├── lib/
│   ├── rl_reference.lua    # 渲染工具函数
│   ├── poem_data.lua       # 诗词数据（200条）
│   ├── recipe_data.lua     # 菜谱数据（250道）
│   └── quotation_data.lua  # 名言数据（200条）
├── tickets/
│   ├── day.lua            # 日票渲染
│   ├── week.lua           # 周票渲染
│   ├── month.lua          # 月票渲染
│   ├── year.lua           # 年票渲染
│   ├── book.lua           # 单书行程票
│   └── screen.lua         # 阅读屏保票
└── styles/
    ├── film.lua           # 胶片票根
    ├── inkstain.lua       # 墨痕壁纸
    └── menu.lua           # 菜单样式
```

## 开发状态

- ✅ 完整功能迁移（v0.2.0）
- ✅ 三样式 + 六票型全部实现
- ✅ 固定/随机/轮流三种模式
- ✅ 手势调出集成
- ✅ 锁屏展示集成
- ✅ 菜单注入
- ⏳ 真机验证

## 源码

- GitHub: https://github.com/ksaMask123/Koreader.patches
- 原始补丁: `2-book-receipt-shortcut-and-lockscreen.lua`

## 许可证

MIT License
