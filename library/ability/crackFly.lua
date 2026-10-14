--- 目标单位技能 击飞
---   来源: share-collection「crackFly击飞」(库基库改造), 已按本框架适配:
---     · 补 superposition.plus/minus("crackFly"), 使 Unit:isCrackFlying() 可用(本框架 Buff 不会自动同步叠加态)
---     · 其余保持与原实现一致
---@private
---@param isComplete boolean
---@param options abilityCrackFlyOptions
---@param vec number[] len:2
---@return void
local _call = function(isComplete, options, vec)
    local res = isComplete
    options.buff:rollback()
    options.buff = nil
    local qty = 0
    if (type(options.bounce) == "table") then
        qty = options.bounce.qty or 0
    end
    if (true == res) then
        local resBounce = true
        if (qty > 0) then
            if (type(options.onBounce) == "function") then
                local r = options.onBounce(options, vec)
                if (type(r) == "boolean" and false == r) then
                    resBounce = false
                end
            end
            if (true == resBounce) then
                options.bounce.qty = options.bounce.qty - 1
                if (class.isObject(options.targetUnit, UnitClass) and false == class.isDestroy(options.targetUnit)) then
                    ability.crackFly(setmetatable({
                        distance = options.distance * (options.bounce.distance or 0.8),
                        height = options.height * (options.bounce.height or 0.8),
                        duration = options.duration * (options.bounce.duration or 0.8),
                    }, { __index = options }))
                end
                return
            end
        end
        if (type(options.onEnd) == "function") then
            res = options.onEnd(options, vec)
        end
    end
end

--[[
    目标单位技能 击飞
    使用 Unit:isCrackFlying() 判断是否经历被击飞
    options = {
        sourceUnit = Unit, --[可选]伤害来源
        targetUnit = Unit, --[必须]目标单位
        model = nil, --[可选]目标单位飞行特效
        attach = nil, --[可选]目标单位飞行特效位置默认origin
        animate = "dead", --[可选]目标单位飞行动作或序号,默认无
        animateScale = 1.00, --[可选]目标单位飞行动画速度，默认1
        frequency = 0.03, --[可选]刷新周期，默认0.03
        distance = 0, --[可选]击退距离，默认0
        height = 100, --[可选]飞跃高度，默认100
        duration = 0.5, --[可选]击飞过程持续时间，默认0.5秒
        bounce = abilityCrackFlyBounce, --[可选]弹跳参数，qty弹跳次数，后面三个为相对前1次的相乘变化率，默认{qty:0,distance:0.8,height:0.8,duration:0.8}
        onMove = abilityCrackFlyFunc, --[可选]每周期回调（return false时可强行中止循环）
        onBounce = abilityCrackFlyFunc, --[可选]每弹跳回调（return false时可强行中止后续弹跳）
        onEnd = abilityCrackFlyFunc, --[可选]结束回调（弹跳完毕才算结束）
    }
]]
---@alias abilityCrackFlyBounce {qty:number,distance:number,height:number,duration:number}
---@alias abilityCrackFlyFunc fun(options:abilityCrackFlyOptions,vec:number[]):boolean
---@alias abilityCrackFlyOptions {sourceUnit:Unit,targetUnit:Unit,model:string,attach:string,animate:string|number,animateScale:number,frequency:number,distance:number,height:number,bounce:abilityCrackFlyBounce,duration:number,onMove:abilityCrackFlyFunc,onEnd:abilityCrackFlyFunc,onBounce:abilityCrackFlyFunc}
---@param options abilityCrackFlyOptions|abilityBuffAddon
---@return void
function ability.crackFly(options)
    sync.must()
    local sourceUnit = options.sourceUnit
    local targetUnit = options.targetUnit
    if (false == class.isObject(targetUnit, UnitClass) or targetUnit:isDead()) then
        return
    end
    options.distance = math.max(0, options.distance or 0)
    options.height = options.height or 100
    options.duration = options.duration or 0.5
    if (options.height <= 0 or options.duration < 0.1) then
        return
    end
    if (targetUnit:isCrackFlying()) then
        return
    end
    local frequency = options.frequency or 0.03
    local flyHeight0 = targetUnit:flyHeight()
    local animate = options.animate
    local animateDiff = (options.animateScale or 1) - targetUnit:animateScale()
    local attach = options.attach or "origin"

    options.buff = Buff({
        key = "crackFly",
        object = targetUnit,
        signal = buffSignal.down,
        name = options.name,
        icon = options.icon,
        description = options.description,
        ---@param buffObj Unit
        purpose = function(buffObj)
            effector.attach(buffObj, options.model, attach)
            if (animateDiff ~= 0) then
                buffObj:animateScale("+=" .. animateDiff)
            end
            if (animate ~= nil) then
                buffObj:animate(animate)
            end
            superposition.plus(buffObj, "crackFly")
            superposition.plus(buffObj, "noPath")
            superposition.plus(buffObj, "pause")
        end,
        ---@param buffObj Unit
        rollback = function(buffObj)
            effector.detach(buffObj, options.model, attach)
            if (animateDiff ~= 0) then
                buffObj:animateScale("-=" .. animateDiff)
            end
            if (animate ~= nil) then
                buffObj:animate("stand")
            end
            buffObj:flyHeight(flyHeight0)
            superposition.minus(buffObj, "pause")
            superposition.minus(buffObj, "noPath")
            superposition.minus(buffObj, "crackFly")
        end,
    })
    local fac0 = 0
    if (class.isObject(sourceUnit, UnitClass)) then
        fac0 = vector2.angle(sourceUnit:x(), sourceUnit:y(), targetUnit:x(), targetUnit:y())
    else
        fac0 = targetUnit:facing() - 180
    end
    local dtSpd = 1 / (options.duration / frequency)
    local dt = 0
    local vec0 = { targetUnit:x(), targetUnit:y(), targetUnit:h() }
    local tx, ty = vector2.polar(targetUnit:x(), targetUnit:y(), options.distance, fac0)
    local vec2 = { tx, ty, targetUnit:h() }
    local mid = vector2.distance(vec0[1], vec0[2], vec2[1], vec2[2])
    local mx, my = vector2.polar(vec0[1], vec0[2], mid, fac0)
    local vec1 = { mx, my, options.height * 2 }
    local vecT = { vec0[1], vec0[2], vec0[3] }
    time.setInterval(frequency, function(curTimer)
        if (targetUnit:isDead()) then
            class.destroy(curTimer)
            _call(false, options, vecT)
            return
        end

        if (dt < 0.2) then
            dt = dt + dtSpd * 1.2
        else
            dt = dt + dtSpd * 0.95
        end

        if (dt >= 1) then
            class.destroy(curTimer)
            targetUnit:position(vec2[1], vec2[2])
            targetUnit:flyHeight(vec2[3])
            _call(true, options, vec2)
            return
        end

        local nx, ny, nz = vector3.bezier2(vec0, vec1, vec2, dt)
        if (false == RegionPlayable:isBorder(nx, ny)) then
            vecT[1], vecT[2], vecT[3] = nx, ny, nz
        end

        if (type(options.onMove) == "function") then
            if (false == options.onMove(options, vecT)) then
                class.destroy(curTimer)
                _call(false, options, vecT)
                return
            end
        end
        targetUnit:flyHeight(vecT[3])
        J.SetUnitX(targetUnit:handle(), vecT[1])
        J.SetUnitY(targetUnit:handle(), vecT[2])
    end)
end
