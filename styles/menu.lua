-- menu.lua - 留台单样式（委托给inkstain模块处理）
local inkstain = require("styles.inkstain")

return {
    buildInkStainWidget = inkstain.buildInkStainWidget,
    K = inkstain.K,
}
