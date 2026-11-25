--- 魔兽自带漂浮字
--- 常用于伤害文字
---@class ttg
ttg = ttg or {}

ttg._limit = 200
ttg._count = ttg._count or 0
--- 待回收漂浮字: { tag=number, expire=number(游戏秒), destroy=boolean }
--- 原实现每条飘字一个 setTimeout, 高频 AoE 下会堆积大量计时器;
--- 改为单个轮询统一回收(0.1 秒粒度对飘字生命周期无可见影响)
---@type table[]
ttg._pending = ttg._pending or {}
ttg._pollTimer = ttg._pollTimer
ttg._pollInterval = 0.1

--- 启动(或复用)回收轮询
---@return void
local function ensurePoll()
    if (class.isObject(ttg._pollTimer, TimerClass)) then
        return
    end
    ttg._pollTimer = time.setInterval(ttg._pollInterval, function()
        local now = time.elapsed() or 0
        local list = ttg._pending
        for i = #list, 1, -1 do
            local item = list[i]
            if (now >= item.expire) then
                if (true == item.destroy) then
                    pcall(J.DestroyTextTag, item.tag)
                end
                ttg._count = math.max(0, ttg._count - 1)
                table.remove(list, i)
            end
        end
    end)
end

--- 销毁漂浮字
---@param whichTag number
---@return void
function ttg.destroy(whichTag)
    sync.must()
    J.DestroyTextTag(whichTag)
    ttg._count = ttg._count - 1
end

--- 创建漂浮字
---@return number integer
function ttg.create()
    sync.must()
    ttg._count = ttg._count + 1
    return J.CreateTextTag()
end

--- 常驻显示漂浮文字
---@param x number
---@param y number
---@param content string 内容
---@param options {size:number,opacity:number,zOffset:number}
---@return number
function ttg.permanent(x, y, content, options)
    content = tostring(content)
    if (string.len(content) <= 0) then
        return
    end
    if (ttg._count > ttg._limit) then
        return
    end
    local size = 10
    local opacity = 255
    local zOffset = 0
    if (type(options) == "table") then
        size = options.size or size
        opacity = options.opacity or opacity
        zOffset = options.zOffset or zOffset
    end
    local this = ttg.create()
    J.SetTextTagPermanent(this, true)
    J.SetTextTagText(this, content, size * 0.023 / 10)
    J.SetTextTagColor(this, 255, 255, 255, math.floor(opacity))
    J.SetTextTagPos(this, x - vistring.len(content) * size * 0.5, y, zOffset)
    return this
end

--- 显示漂浮文字
--- size number
--- opacity number 透明度 0-255，为0则不可见
--- xOffset number x轴偏移速度
--- yOffset number y轴偏移速度
--- zOffset number z轴高度偏移量
---@param x number
---@param y number
---@param content string 内容
---@param during number 持续时间，大于0
---@param options {size:number,opacity:number,zOffset:number,xOffset:number,yOffset:number,color:number[],fade:number}
---@return void
function ttg.display(x, y, content, during, options)
    sync.must()
    content = tostring(content)
    if (string.len(content) <= 0 or during <= 0) then
        return
    end
    if (ttg._count > ttg._limit) then
        return
    end
    local size = 10
    local opacity = 255
    local zOffset = 0
    local xOffset = 0
    local yOffset = 0
    local fade = 0
    local r, g, b, a = 255, 255, 255, 255
    if (type(options) == "table") then
        size = options.size or size
        opacity = options.opacity or opacity
        zOffset = options.zOffset or zOffset
        xOffset = options.xOffset or xOffset
        yOffset = options.yOffset or yOffset
        fade = tonumber(options.fade) or 0
        local c = options.color
        if (type(c) == "table") then
            r = math.floor(c[1] or 255)
            g = math.floor(c[2] or 255)
            b = math.floor(c[3] or 255)
            a = math.floor(c[4] or opacity)
        end
    end
    a = math.floor(a or opacity)
    local tt = ttg.create()
    J.SetTextTagText(tt, content, size * 0.023 / 10)
    J.SetTextTagColor(tt, r, g, b, a)
    J.SetTextTagPos(tt, x - vistring.len(content) * size * 0.5, y, zOffset)
    if (xOffset ~= 0 or yOffset ~= 0) then
        J.SetTextTagVelocity(tt, xOffset, yOffset)
    end
    if (nil == tt or 0 == tt) then
        return
    end
    local now = time.elapsed() or 0
    local expire, destroy
    if (fade > 0 and type(J.SetTextTagLifespan) == "function" and type(J.SetTextTagFadepoint) == "function") then
        --- 交给引擎在 during 之后淡出, 到 during+fade 自动销毁; 这里只回收计数
        J.SetTextTagPermanent(tt, false)
        J.SetTextTagLifespan(tt, during + fade)
        J.SetTextTagFadepoint(tt, during)
        expire = now + during + fade
        destroy = false
    else
        expire = now + during
        destroy = true
    end
    ensurePoll()
    ttg._pending[#ttg._pending + 1] = { tag = tt, expire = expire, destroy = destroy }
end