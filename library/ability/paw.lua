--- 模版技能 爪冲击
---   来源: share-collection「paw爪」(library基库改造), 已按本框架适配:
---     · 修正多爪且 stepLength <= 0 时未发射箭矢的问题
--[[
    模版技能 爪冲击
    options = {
        sourceUnit = Unit, --[可选]伤害来源（没有来源单位时，必须有sourceVec）
        sourceVec = number[] len:3[可选]强制设定初始坐标
        targetVec = number[] len:3[必须]目标修正坐标（非实际冲击终点坐标，仅指定方向）
        model = nil, --[必须]虚拟爪箭矢的特效
        animateScale = 1.00, --[可选]虚拟爪箭矢的动画速度，默认1
        scale = 1.00, --[可选]虚拟爪箭矢的模型缩放，默认1
        frequency = 0.03, --[可选]刷新周期，默认0.03
        speed = 500, --[可选]每秒冲击的距离，默认1秒500px
        acceleration = 0, --[可选]冲击加速度，每个周期都会增加一次
        distance = 500, --[可选]冲击距离，默认500，最小为100
        qty = 3, --[可选]冲击个数，默认3，最小为1
        angle = 15, --[可选]冲击分隔角度，默认15，最小为10；当冲击个数为1时，此数值无效
        stepLength = 20, --[可选]冲击启步距离，默认20，最小为0
        onMove = abilityPawFunc, --[可选]每周期回调,当return false时可强行中止循环
        onEnd = abilityPawFunc, --[可选]结束回调,当return true时才会执行reflex
    }
]]
---@alias abilityPawFunc fun(options:abilityPawOptions,vec:number[]):boolean
---@alias abilityPawOptions {model:string,animateScale:number,scale:number,frequency:number,speed:number,acceleration:number,angle:number,sourceUnit:Unit,targetUnit:Unit,sourceVec:number[],targetVec:number[],onMove:abilityPawFunc,onEnd:abilityPawFunc}
---@param options abilityPawOptions
function ability.paw(options)
    sync.must()
    must(type(options.model) == "string", "options.model@string")
    must(type(options.targetVec) == "table", "options.targetVec@table")
    local distance = math.max(100, options.distance or 500)
    local qty = math.max(1, options.qty or 3)
    local angle = math.max(10, options.angle or 15)
    local stepLength = math.max(0, options.stepLength or 20)

    local targetVec = options.targetVec
    local vec0 = options.sourceVec
    if (type(vec0) ~= "table") then
        must(class.isObject(options.sourceUnit, UnitClass), "options.sourceUnit@Unit")
        vec0 = { options.sourceUnit:x(), options.sourceUnit:y(), options.sourceUnit:h() }
    end

    local fac0 = vector2.angle(vec0[1], vec0[2], targetVec[1], targetVec[2])
    local opt = {
        model = options.model,
        animateScale = options.animateScale,
        scale = options.scale,
        frequency = options.frequency,
        speed = options.speed,
        acceleration = options.acceleration,
        onMove = options.onMove,
        onEnd = options.onEnd,
    }
    if (qty <= 1) then
        local sv, tv
        if (stepLength <= 0) then
            sv, tv = vec0, targetVec
        else
            local x, y = vector2.polar(vec0[1], vec0[2], stepLength, fac0)
            sv = { x, y, vec0[3] or japi.Z(x, y) }
            x, y = vector2.polar(vec0[1], vec0[2], stepLength + distance, fac0)
            tv = { x, y, targetVec[3] or japi.Z(x, y) }
        end
        ability.missile(setmetatable({ sourceVec = sv, targetVec = tv }, { __index = opt }))
    else
        local angle1st
        if (qty % 2 == 1) then
            local q = (qty - 1) / 2
            angle1st = fac0 - q * angle
        else
            local q = qty / 2
            angle1st = fac0 - (q - 1) * angle - angle / 2
        end
        for i = 0, qty - 1, 1 do
            local fac = angle1st + i * angle
            local sv, tv
            if (stepLength <= 0) then
                sv, tv = vec0, targetVec
            else
                local x, y = vector2.polar(vec0[1], vec0[2], stepLength, fac)
                sv = { x, y, vec0[3] or japi.Z(x, y) }
                x, y = vector2.polar(vec0[1], vec0[2], stepLength + distance, fac)
                tv = { x, y, targetVec[3] or japi.Z(x, y) }
            end
            ability.missile(setmetatable({ sourceVec = sv, targetVec = tv }, { __index = opt }))
        end
    end
end
