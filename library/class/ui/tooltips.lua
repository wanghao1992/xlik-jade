--- current class name
UITooltipsClass = "UITooltips"

--- 提示面板UI (视觉见 .trae/design/wc3-panels.html §12 悬浮提示体系)
---   框架: 上下切角条带 + 左右边 + 底纹 + 品质光条 + 下箭头(全部切图, 见 war3mapImage/提示框_*)
---   结构: 标题行(图标/名称/副标题/品质角标) -> 分隔线 -> 数值行 -> 描述 -> 列表 -> 页脚
---@class UITooltips:UI
local _index = UI(UITooltipsClass, {
    ---@type boolean 保护
    _protect = true
})

--- 设计图像素 -> UI 单位(1920x1080 -> 0.8x0.6)
local PX_W, PX_H = 1 / 2400, 1 / 1800
---@param v number
---@return number
local function pxw(v) return v * PX_W end
---@param v number
---@return number
local function pxh(v) return v * PX_H end

--- 框架贴图(放在 slkc_fdf 套件 assets 里, 这里用完整地图路径引用: 全局类无 kit 别名)
local ASSET_DIR = 'war3mapUI\\slkc_fdf\\assets\\'
local TEX = {
    top = ASSET_DIR .. '提示框_上.tga',
    bottom = ASSET_DIR .. '提示框_下.tga',
    left = ASSET_DIR .. '提示框_左.tga',
    right = ASSET_DIR .. '提示框_右.tga',
    fill = ASSET_DIR .. '提示框_底.tga',
    accentFmt = ASSET_DIR .. '提示框_条%d.tga',
    chip = ASSET_DIR .. '提示框_角标.tga',
    line = ASSET_DIR .. '提示框_线.tga',
    gem = ASSET_DIR .. '提示框_菱形.tga',
    cornerFmt = ASSET_DIR .. '提示框_角_%s.tga',
    border = '通用边框.tga',
}

--- 品质 -> 名称 / 色 / 边框(与图鉴、宝库同一套)
local Q_NAME = { '普通', '优秀', '稀有', '史诗', '传说' }
local Q_HEX = { 'dfe8ee', 'a9e78f', '8ecbff', 'd8b1f5', 'f0d38a' }
local Q_BORDER = { '边框_lv2.tga', '边框_lv3.tga', '边框_lv4.tga', '边框_lv5.tga', '边框_lv8.tga' }

--- 解析贴图路径: 全局类没有 kit 别名, 借用任一 kit 名触发 alias -> 完整路径的回退
---@param p string|nil
---@return string|nil
local function texPath(p)
    if (type(p) ~= 'string' or p == '') then
        return p
    end
    --- kit 名只是为了让 AssetsUI 走 "kit 未命中 -> image 别名表" 的分支
    local out = japi.AssetsUI('xlik_codex', p, 'image')
    if (type(out) == 'string' and out ~= '') then
        return out
    end
    return p
end

--- 框架尺寸 / 内容留白
local STRIP_H = pxh(16)          -- 上下条带高度
local EDGE_W = pxw(2)            -- 左右边宽度(1px 金边 + 1px 内黑线)
local PAD_L, PAD_R = pxw(12), pxw(12)
local PAD_T, PAD_B = pxh(15), pxh(15)

--- 字号
local FS_NAME, FS_SUB, FS_BODY = 12, 9, 10
--- 正方形尺寸: 直接返回相同的 UI 比例(宽=高)
--- 说明: pxw/pxh 是 16:9 下的换算, 非 16:9 客户端会把 34x34 压成长方形;
--- 而 DZ_GetClientWidth/Height 返回的宽高并不可靠(实测宽会拿到桌面宽度),
--- 因此这里不走宽高比换算, 直接用同一 UI 值 —— 游戏内渲染出来就是正方形
---@param px number
---@return number, number
local function pxSquare(px)
    local h = pxh(px)
    return h, h
end

local RULE_H, STAT_H, FOOT_H = pxh(10), pxh(17), pxh(22)
local LINE_BULLET = '|cffc9aa50·|r '
--- 固定宽度(设计像素): 所有提示框同宽, 超宽内容自动折行
local TOOLTIP_W_PX = 640
--- 标题行/副标题行高度(标题字体实际渲染高度大于字号, 需单独留位)
local NAME_H, SUB_H = pxh(23), pxh(15)

--- 按最大宽度折行(保留颜色码, 不会把 |cffxxxxxx 从中间切断)
---@param text string
---@param fontSize number
---@param maxW number
---@return string, number 折行后的文本与行数
local function wrapRich(text, fontSize, maxW)
    --- 去掉首尾多余换行: 否则末尾的 |n 会被算成一行, 导致框底多出空白
    while (string.sub(text, 1, 2) == '|n') do
        text = string.sub(text, 3)
    end
    while (string.sub(text, -2) == '|n') do
        text = string.sub(text, 1, -3)
    end
    if (text == '') then
        return '', 0
    end
    local out = {}
    local lineW, lines = 0, 1
    local i, n = 1, #text
    while (i <= n) do
        local c = string.sub(text, i, i)
        if (c == '|') then
            local tag = string.sub(text, i, i + 1)
            if (tag == '|c') then
                --- 颜色码 |cAARRGGBB 共 10 个字符
                out[#out + 1] = string.sub(text, i, i + 9)
                i = i + 10
            elseif (tag == '|r') then
                out[#out + 1] = '|r'
                i = i + 2
            elseif (tag == '|n') then
                out[#out + 1] = '|n'
                lineW = 0
                lines = lines + 1
                i = i + 2
            else
                out[#out + 1] = c
                i = i + 1
                lineW = lineW + vistring.width(c, fontSize)
            end
        else
            local bl = mbstring.byteLen(text, i)
            local ch = string.sub(text, i, i + bl - 1)
            local w = vistring.width(ch, fontSize)
            if (lineW > 0 and lineW + w > maxW) then
                out[#out + 1] = '|n'
                lineW = 0
                lines = lines + 1
            end
            out[#out + 1] = ch
            lineW = lineW + w
            i = i + bl
        end
    end
    return table.concat(out), lines
end

--- 去掉颜色码
---@param s string
---@return string
local function stripColor(s)
    local t = string.gsub(s, '|c%x%x%x%x%x%x%x%x', '')
    t = string.gsub(t, '|r', '')
    t = string.gsub(t, '|n', '')
    return t
end

--- 是否为空行(忽略颜色码与换行符)
---@param s string
---@return boolean
local function isBlank(s)
    if (type(s) ~= 'string' or s == '') then
        return true
    end
    return (string.trim(stripColor(s)) == '')
end

--- 拆"标签: 值"形式的描述行(用于两端对齐的数值行)
---@param s string
---@return string|nil label, string|nil value, string|nil hex
local function splitKV(s)
    if (type(s) ~= 'string') then
        return nil
    end
    local plain = stripColor(s)
    local i = string.find(plain, ':') or string.find(plain, '：')
    if (nil == i) then
        return nil
    end
    local label = string.trim(string.sub(plain, 1, i - 1))
    local val = string.trim(string.sub(plain, i + 1))
    if ('' == label or '' == val) then
        return nil
    end
    local hex = string.match(s, '^|c%x%x(%x%x%x%x%x%x)')
    return label, val, hex
end

--- 内容设置
--[[
    -- 基础(旧): tips / icons / bars / padding / textAlign / fontSize
    -- 新结构(按设计图):
        quality   品质 1-5(决定光条/宝石/角标颜色, 及默认边框)
        name      标题(也可用 title)
        sub       副标题「品质 · 类型 · 限制」
        grade     右上角角标文本(缺省用品质名)
        icon      图标贴图(与网格同一张)
        iconBorder 图标边框(缺省按品质取 边框_lv*.tga)
        stats     {{ label=, value=, tone='buff'|'weak' }}
        desc      描述(自动折行)
        foot      { left=, right=, tone='ok'|'warn' }
        tips      {"行1", ...} 列表(自动加菱形点标)
]]
---@param options table
---@return self
function _index:content(options)
    if (type(options) == "string") then
        options = { tips = options }
    end
    options = options or {}
    local fontSize = tonumber(options.fontSize) or FS_BODY
    local q = math.floor(tonumber(options.quality) or 0)
    if (q < 1 or q > 5) then
        q = 0
    end

    ------------------------------------------------------------------ 取参数
    --- 方件尺寸按客户端宽高比实时换算(必须在调用时取, 初始化阶段客户端尺寸可能还未就绪)
    local ICON_W, ICON_H = pxSquare(34)
    local GEM_W, GEM_H = pxSquare(8)
    local RULE_GEM_W, RULE_GEM_H = pxSquare(7)
    local ROW_ICON_W, ROW_ICON_H = pxSquare(13)
    --- 兼容 tipsPre/tipsPost: tipsPre 首行作为标题, tipsPost 作为正文
    local pre = type(options.tipsPre) == 'table' and options.tipsPre or nil
    local post = type(options.tipsPost) == 'table' and options.tipsPost or nil
    local hasOwnName = (nil ~= options.name or nil ~= options.title)
    local name = options.name or options.title or (pre and #pre > 0 and pre[1] or nil)
    local sub = options.sub
    local grade = options.grade or (q > 0 and Q_NAME[q] or nil)
    local iconTex = options.icon
    local iconBorder = options.iconBorder or (q > 0 and Q_BORDER[q] or nil) or TEX.border
    local stats = type(options.stats) == 'table' and options.stats or {}
    local foot = type(options.foot) == 'table' and options.foot or nil
    local desc = options.desc
    local tips = options.tips
    if (type(tips) == 'string') then
        tips = string.explode('|n', tips)
    end
    if (nil == tips) then
        if (post) then
            tips = post
        elseif (pre) then
            --- 标题若取自 tipsPre[1], 正文从第 2 行开始
            tips = {}
            for i = (hasOwnName and 1 or 2), #pre do
                tips[#tips + 1] = pre[i]
            end
        end
    end
    --- 过滤空行(描述体里常用空串占位, 直接渲染会留下孤立的点标)
    local lines = {}
    for _, s in ipairs(tips or {}) do
        if (not isBlank(s)) then
            lines[#lines + 1] = s
        end
    end
    tips = lines
    --- kv 模式: 把"标签: 值"形式的行转成两端对齐的属性行(设计图的数值行)
    if (options.kv == true and #tips > 0) then
        local body, kv = {}, {}
        for _, s in ipairs(tips) do
            local label, val, hex = splitKV(s)
            if (label and vistring.width(val, fontSize) <= pxw(200)) then
                kv[#kv + 1] = { label = label, value = val, hex = hex }
            else
                body[#body + 1] = s
            end
        end
        if (#kv > 0) then
            local merged = {}
            for _, s in ipairs(stats) do
                merged[#merged + 1] = s
            end
            for _, s in ipairs(kv) do
                merged[#merged + 1] = s
            end
            stats = merged
        end
        tips = body
    end
    local icons = type(options.icons) == 'table' and options.icons or {}
    local bars = type(options.bars) == 'table' and options.bars or {}

    --- 内容留白(可用 options.padding 覆盖: 上右下左)
    local padL, padR, padT, padB = PAD_L, PAD_R, PAD_T, PAD_B
    if (type(options.padding) == 'table') then
        padT = options.padding[1] or padT
        padR = options.padding[2] or padR
        padB = options.padding[3] or padB
        padL = options.padding[4] or padL
    end

    ------------------------------------------------------------------ 面板尺寸(固定宽度)
    --- 固定宽度: 所有提示框同宽, 不再随内容长短变化; 超宽内容自动折行
    local W = pxw(tonumber(options.width) or TOOLTIP_W_PX)
    local bodyW = W - padL - padR

    ------------------------------------------------------------------ 量算各段高度
    --- 标题行
    local headerH = 0
    local gradeW = 0
    if (name) then
        gradeW = grade and (vistring.width(grade, FS_SUB) + pxw(16)) or 0
        local textH = NAME_H + (sub and SUB_H or 0)
        headerH = math.max(iconTex and ICON_H or 0, textH)
    end

    --- 数值行
    local statN = math.min(#stats, 4)
    local statH = statN * STAT_H

    --- 描述(折行)
    local descH, descText = 0, ''
    if (desc) then
        local n = 0
        descText, n = wrapRich(tostring(desc), fontSize, bodyW)
        if (n > 0) then
            descH = vistring.height(n, fontSize) + pxh(6)
        end
    end

    --- 列表(带菱形点标)
    local tipH, tipText = 0, ''
    if (#tips > 0) then
        local arr = {}
        for i, s in ipairs(tips) do
            --- 首行作主信息(不加点标), 其余加菱形点标
            arr[i] = ((i == 1) and '' or LINE_BULLET) .. s
        end
        local n = 0
        tipText, n = wrapRich(table.concat(arr, '|n'), fontSize, bodyW)
        if (n > 0) then
            tipH = vistring.height(n, fontSize) + pxh(2)
        end
    end

    --- 旧版图标行 / 进度条
    local iconRowH = 0
    local iconN = math.min(#icons, 4)
    for i = 1, iconN do
        if (type(icons[i]) == 'table') then
            iconRowH = pxh(16)
        end
    end
    local barN = math.min(#bars, 2)
    local barH = 0
    for i = 1, barN do
        if (type(bars[i]) == 'table') then
            barH = barH + (bars[i].height or pxh(1)) + vistring.height(1, fontSize - 2) + pxh(3)
        end
    end

    --- 页脚
    local footH = foot and FOOT_H or 0

    --- 规则线(有标题才画)
    local ruleH = name and RULE_H or 0

    local H = padT + headerH + ruleH + statH + descH + tipH + iconRowH + barH + footH + padB
    self:size(W, H)

    ------------------------------------------------------------------ 框架(5 段)
    --- 四边分别锚到各自的角上: 避免用 W-宽度 算分数坐标导致取整偏移,
    --- 1px 金线被半像素平均后会看起来像断线/缺口
    self._frameTop:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, 0, 0)
        :size(W, STRIP_H):show(true)
    self._frameBottom:relation(UI_ALIGN_LEFT_BOTTOM, self, UI_ALIGN_LEFT_BOTTOM, 0, 0)
        :size(W, STRIP_H):show(true)
    --- 左右边正好夹在上下条带之间, 不留缝
    local edgeH = math.max(0.0001, H - 2 * STRIP_H)
    self._frameLeft:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, 0, -STRIP_H)
        :size(EDGE_W, edgeH):show(true)
    self._frameRight:relation(UI_ALIGN_RIGHT_TOP, self, UI_ALIGN_RIGHT_TOP, 0, -STRIP_H)
        :size(EDGE_W, edgeH):show(true)
    --- 底纹铺满整框, 避免根框架的默认贴图从边缘透出来
    self._frameFill:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, 0, 0):size(W, H):show(true)

    --- 四角包角(与条带同高, 四边无缝对接)
    local cw = STRIP_H
    for i = 1, 4 do
        local p = (i == 1 and UI_ALIGN_LEFT_TOP)
            or (i == 2 and UI_ALIGN_RIGHT_TOP)
            or (i == 3 and UI_ALIGN_LEFT_BOTTOM)
            or UI_ALIGN_RIGHT_BOTTOM
        self._corners[i]:relation(p, self, p, 0, 0):size(cw, cw):show(true)
    end

    --- 品质光条
    if (q > 0) then
        self._accent:texture(string.format(TEX.accentFmt, q))
            :relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, pxw(2), -pxh(8))
            :size(pxw(3), math.max(0.0001, H - pxh(16))):show(true)
    else
        self._accent:show(false)
    end

    ------------------------------------------------------------------ 标题行
    local y = 0
    if (name) then
        local tx = padL
        if (iconTex) then
            self._iconBg:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -padT)
                :size(ICON_W, ICON_H):texture(texPath(iconTex)):show(true)
            self._iconBd:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -padT)
                :size(ICON_W, ICON_H):texture(texPath(iconBorder)):show(true)
            self._gem:show(false)
            tx = padL + ICON_W + pxw(9)
        else
            self._iconBg:show(false)
            self._iconBd:show(false)
            --- 无图标时用小菱形代替
            self._gem:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(padT + pxh(6)))
                :size(GEM_W, GEM_H):texture(TEX.gem):show(true)
            tx = padL + pxh(11)
        end
        self._name:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, tx, -padT)
            :size(math.max(pxw(40), bodyW - (tx - padL) - (gradeW > 0 and (gradeW + pxw(8)) or 0)), NAME_H)
            :fontSize(FS_NAME)
            :text(colour.hex('ffeeb8', tostring(name)))
            :show(true)
        if (sub) then
            self._sub:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, tx, -(padT + NAME_H))
                :size(bodyW - (tx - padL), SUB_H)
                :fontSize(FS_SUB)
                :text(colour.hex('8d8165', tostring(sub)))
                :show(true)
        else
            self._sub:show(false)
        end
        if (grade) then
            local gx = W - padR - gradeW
            local hex = q > 0 and Q_HEX[q] or 'cfc1a0'
            self._gradeBg:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, gx, -(padT + pxh(2)))
                :size(gradeW, pxh(15)):texture(TEX.chip):show(true)
            self._gradeTxt:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, gx, -(padT + pxh(2)))
                :size(gradeW, pxh(15))
                :textAlign(TEXT_ALIGN_CENTER)
                :fontSize(FS_SUB)
                :text(colour.hex(hex, tostring(grade)))
                :show(true)
        else
            self._gradeBg:show(false)
            self._gradeTxt:show(false)
        end
        y = y + headerH

        --- 分隔线 + 中央菱形
        self._rule:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(padT + y + pxh(4)))
            :size(bodyW, pxh(1)):texture(TEX.line):show(true)
        self._ruleGem:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP,
            padL + bodyW / 2 - RULE_GEM_W / 2, -(padT + y + pxh(1)))
            :size(RULE_GEM_W, RULE_GEM_H):texture(TEX.gem):show(true)
        y = y + ruleH
    else
        self._iconBg:show(false)
        self._iconBd:show(false)
        self._gem:show(false)
        self._name:show(false)
        self._sub:show(false)
        self._gradeBg:show(false)
        self._gradeTxt:show(false)
        self._rule:show(false)
        self._ruleGem:show(false)
    end

    ------------------------------------------------------------------ 数值行
    for i = 1, 4 do
        local lb, vl = self._statLb[i], self._statVl[i]
        local s = stats[i]
        if (i <= statN and type(s) == 'table') then
            local yy = padT + y + (i - 1) * STAT_H
            lb:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -yy)
                :size(bodyW * 0.6, pxh(15))
                :fontSize(fontSize)
                :text(colour.hex('a99d82', tostring(s.label or '')))
                :show(true)
            local hex = s.hex or 'e8d3a0'
            if (s.tone == 'buff') then
                hex = '9fe3b0'
            elseif (s.tone == 'weak') then
                hex = 'e0664f'
            end
            vl:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -yy)
                :size(bodyW, pxh(15))
                :textAlign(TEXT_ALIGN_RIGHT)
                :fontSize(fontSize)
                :text(colour.hex(hex, tostring(s.value or '')))
                :show(true)
        else
            lb:show(false)
            vl:show(false)
        end
    end
    y = y + statH

    ------------------------------------------------------------------ 描述
    if (descText ~= '') then
        self._desc:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(padT + y + pxh(4)))
            :size(bodyW, descH)
            :textAlign(TEXT_ALIGN_LEFT)
            :fontSize(fontSize)
            :text(descText)
            :show(true)
    else
        self._desc:show(false)
    end
    y = y + descH

    ------------------------------------------------------------------ 列表
    if (tipText ~= '') then
        self._text:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(padT + y + pxh(3)))
            :size(bodyW, tipH)
            :textAlign(options.textAlign or TEXT_ALIGN_LEFT)
            :fontSize(fontSize)
            :text(tipText)
            :show(true)
    else
        self._text:show(false)
    end
    y = y + tipH

    ------------------------------------------------------------------ 图标行(旧版)
    local ix = padL
    for i = 1, 4 do
        local bg, txt = self._icons[i].bg, self._icons[i].txt
        local it = icons[i]
        if (i <= iconN and type(it) == 'table') then
            bg:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, ix, -(padT + y))
                :size(ROW_ICON_W, ROW_ICON_H):texture(texPath(it.texture)):show(true)
            txt:fontSize(fontSize - 1):text(it.text):show(true)
            ix = ix + ROW_ICON_W + pxw(4) + vistring.width(it.text or '', fontSize)
        else
            bg:show(false)
        end
    end
    y = y + iconRowH

    ------------------------------------------------------------------ 进度条(旧版)
    for i = 1, 2 do
        local b = self._bars[i]
        local it = bars[i]
        if (i <= barN and type(it) == 'table') then
            local bh = it.height or pxh(1)
            local txh = vistring.height(1, fontSize - 2)
            b:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(padT + y))
                :size(it.width or bodyW, bh)
            b:text(LAYOUT_ALIGN_LEFT_TOP, it.text)
            b:fontSize(LAYOUT_ALIGN_LEFT_TOP, fontSize - 2)
            b:valueTexture(texPath(it.texture))
            b:ratio(it.ratio, it.width or bodyW, bh)
            b:show(true)
            y = y + bh + txh + pxh(1)
        else
            b:show(false)
        end
    end

    ------------------------------------------------------------------ 页脚
    if (foot) then
        local fy = padT + y + pxh(4)
        self._footLine:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -fy)
            :size(bodyW, pxh(1)):texture(TEX.line):show(true)
        if (foot.left) then
            self._footL:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(fy + pxh(4)))
                :size(bodyW * 0.62, pxh(15))
                :fontSize(FS_SUB)
                :text(colour.hex('7f7460', tostring(foot.left)))
                :show(true)
        else
            self._footL:show(false)
        end
        if (foot.right) then
            local hex = 'f0d38a'
            if (foot.tone == 'ok') then
                hex = '9fe3b0'
            elseif (foot.tone == 'warn') then
                hex = 'e0664f'
            end
            self._footR:relation(UI_ALIGN_LEFT_TOP, self, UI_ALIGN_LEFT_TOP, padL, -(fy + pxh(4)))
                :size(bodyW, pxh(15))
                :textAlign(TEXT_ALIGN_RIGHT)
                :fontSize(FS_SUB)
                :text(colour.hex(hex, tostring(foot.right)))
                :show(true)
        else
            self._footR:show(false)
        end
    else
        self._footLine:show(false)
        self._footL:show(false)
        self._footR:show(false)
    end

    return self
end

--- 构造UITooltips信息对象
---@param index number 序号0框架保留使用，请使用其他1-3号序号或缺省（默认1）
---@return UITooltips
function UITooltips(index)
    index = math.floor(index or 1)
    must(type(index) == "number", "index@integer")
    must(index >= 0 and index <= 3, "index out of range 0~3")
    local cache = class.cache(UITooltipsClass)
    if (nil == cache[index]) then
        local key = UITooltipsClass .. index
        ---@type UITooltips
        local o = oUI({
            _key = key,
            _parent = UIGame,
            _fdfName = "LK_BACKDROP",
            _fdfType = "BACKDROP"
        }, _index)
        o:adaptive(true)
        o:absolut(0, 0)
        o:size(0.1, 0.1)
        o:show(false)
        --- tooltip 永远显示在最上层(高于所有面板套件), 避免被高优先级面板盖住
        if (japi and japi.DZ_FrameSetPriority) then
            pcall(japi.DZ_FrameSetPriority, o:handle(), 10000)
        end
        ------------------------------------------------------------------ 框架(先建, 保证在内容下层)
        --- 用默认 LK_BACKDROP(自带 BackdropBlendAll), 切角透明像素才会正确透出
        local fb = nil
        o._frameFill = UIBackdrop(key .. "Fill", o, fb):texture(TEX.fill):show(false)
        o._frameTop = UIBackdrop(key .. "Top", o, fb):texture(TEX.top):show(false)
        o._frameBottom = UIBackdrop(key .. "Bottom", o, fb):texture(TEX.bottom):show(false)
        o._frameLeft = UIBackdrop(key .. "Left", o, fb):texture(TEX.left):show(false)
        o._frameRight = UIBackdrop(key .. "Right", o, fb):texture(TEX.right):show(false)
        o._accent = UIBackdrop(key .. "Accent", o, fb):texture(string.format(TEX.accentFmt, 5)):show(false)
        --- 四角包角(直角框的角部装饰)
        o._corners = {}
        local cnames = { '左上', '右上', '左下', '右下' }
        for i = 1, 4 do
            o._corners[i] = UIBackdrop(key .. "Corner" .. i, o, fb)
                :texture(string.format(TEX.cornerFmt, cnames[i])):show(false)
        end

        ------------------------------------------------------------------ 标题行
        o._iconBg = UIBackdrop(key .. "Icon", o, fb):show(false)
        o._iconBd = UIBackdrop(key .. "IconBd", o, fb):texture(texPath(TEX.border)):show(false)
        o._gem = UIBackdrop(key .. "Gem", o, fb):texture(TEX.gem):show(false)
        o._name = UIText(key .. "Name", o):textAlign(TEXT_ALIGN_LEFT):show(false)
        o._sub = UIText(key .. "Sub", o):textAlign(TEXT_ALIGN_LEFT):show(false)
        o._gradeBg = UIBackdrop(key .. "GradeBg", o, fb):texture(TEX.chip):show(false)
        o._gradeTxt = UIText(key .. "GradeTxt", o):textAlign(TEXT_ALIGN_CENTER):show(false)

        ------------------------------------------------------------------ 分隔线 / 描述 / 列表 / 页脚
        o._rule = UIBackdrop(key .. "Rule", o, fb):texture(TEX.line):show(false)
        o._ruleGem = UIBackdrop(key .. "RuleGem", o, fb):texture(TEX.gem):show(false)
        o._desc = UIText(key .. "Desc", o):textAlign(TEXT_ALIGN_LEFT):show(false)
        o._footLine = UIBackdrop(key .. "FootLine", o, fb):texture(TEX.line):show(false)
        o._footL = UIText(key .. "FootL", o):textAlign(TEXT_ALIGN_LEFT):show(false)
        o._footR = UIText(key .. "FootR", o):textAlign(TEXT_ALIGN_RIGHT):show(false)

        ------------------------------------------------------------------ 数值行(最多 4 行)
        o._statLb, o._statVl = {}, {}
        for i = 1, 4 do
            o._statLb[i] = UIText(key .. "StatLb" .. i, o):textAlign(TEXT_ALIGN_LEFT):show(false)
            o._statVl[i] = UIText(key .. "StatVl" .. i, o):textAlign(TEXT_ALIGN_RIGHT):show(false)
        end

        ------------------------------------------------------------------ 旧版图标行 / 进度条 / 主文本
        local ic = {}
        for i = 1, 4 do
            local tmp = {}
            tmp.bg = UIBackdrop(key .. "IconBg" .. i, o)
                :size(0.013, 0.013)
                :show(false)
            tmp.txt = UIText(key .. "IconTxt" .. i, tmp.bg)
                :relation(UI_ALIGN_LEFT, tmp.bg, UI_ALIGN_RIGHT, 0.002, 0)
                :textAlign(TEXT_ALIGN_LEFT)
            table.insert(ic, tmp)
        end
        o._icons = ic
        local brs = {}
        for i = 1, 2 do
            local b = UIBar(key .. "Bar" .. i, o, { _layouts = { LAYOUT_ALIGN_LEFT_TOP } })
            b:show(false)
            table.insert(brs, b)
        end
        o._bars = brs
        o._text = UIText(key .. "->Txt", o)
            :textAlign(TEXT_ALIGN_LEFT)
            :fontSize(FS_BODY)
            :show(false)
        ---@param evtData eventOnUIShow
        o:onEvent(eventKind.uiShow, "clear_", function(evtData)
            evtData.triggerUI:onEvent(eventKind.uiLeftClick, "clear2_", function(evtData2)
                evtData2.triggerUI:onEvent(eventKind.uiLeftClick, "clear2_", nil)
                evtData2.triggerUI:show(false)
            end)
        end)
        --
        Pool(UITooltipsClass):insert(o)
        cache[index] = o
    end
    return cache[index]
end
