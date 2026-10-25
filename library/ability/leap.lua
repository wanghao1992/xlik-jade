--- 单位目标技能 冲锋
---   来源: share-collection「leap冲锋」(库基库改造), 已按本框架适配:
---     · 补 superposition.plus/minus("leap"), 使 Unit:isLeaping() 可用(本框架 Buff 不会自动同步叠加态)
---     · 其余保持与原实现一致
---@private
---@param isComplete boolean
---@param options abilityLeapOptions
---@param vec number[] len:2
---@return void
local _call = function(isComplete, options, vec)
    options.buff:rollback()
    options.buff = nil
    local qty = options.reflex or 0
    local res = isComplete
    if (true == res) then
        local resReflex = true
        if (qty > 0 and class.isObject(options.targetUnit, UnitClass)) then
            if (type(options.onReflex) == "function") then
                local r = options.onReflex(options, vec)
                if (type(r) == "boolean" and false == r) then
                    resReflex = false
                end
            end
            if (true == resReflex) then
                local nextUnit = Group(UnitClass):rand({
                    circle = {
                        x = vec[1],
                        y = vec[2],
                        radius = 600,
                    },
                    ---@param enumUnit Unit
                    filter = function(enumUnit)
                        return enumUnit:isOther(options.targetUnit) and enumUnit:isAlive() and enumUnit:isEnemy(options.sourceUnit:owner())
                    end,
                })
                if (class.isObject(nextUnit, UnitClass)) then
                    ability.leap(setmetatable({ reflex = options.reflex - 1, targetUnit = nextUnit }, { __index = options }))
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
    单位目标技能 冲锋
    使用 Unit:isLeaping() 判断是否冲锋中
    options = {
        sourceUnit, --[必须]冲锋单位，同时也是伤害来源
        targetUnit, --[可选]目标单位（有单位目标，那么冲击跟踪到单位就结束）
        targetVec = number[] len:3[可选]强制设定目标坐标
        model = nil, --[可选]冲锋单位origin特效
        animate = "attack", --[可选]冲锋动作
        animateScale = 1.00, --[可选]冲锋的动画速度
        frequency = 0.03, --[可选]刷新周期，默认0.03
        speed = 500, --[可选]每秒冲击的距离（默认1秒500px）
        acceleration = 0, --[可选]冲击加速度（每个周期[0.02秒]都会增加一次）
        height = 0, --[可选]飞跃高度（默认0）
        reflex = 0, --[可选]弹射次数，当targetUnit存在时才有效，默认0
        stunPause = false, --[可选]眩晕时是否暂停推进（默认false；true时眩晕期间停在原地, 眩晕结束后继续）
        onMove = abilityLeapFunc, --[可选]每周期移动回调（return false时可强行中止循环）
        onReflex = abilityLeapFunc, --[可选]每弹跳回调（return false时可强行中止后续弹跳）
        onEnd = abilityLeapFunc, --[可选]结束回调（弹跳完毕才算结束）
    }
]]
---@alias abilityLeapFunc fun(options:abilityLeapOptions,vec:number[]):nil|boolean
---@alias abilityLeapOptions {sourceUnit:Unit,targetUnit:Unit,targetVec:number[],animate:string|number,animateScale:number,frequency:number,speed:number,acceleration:number,height:number,reflex:number,stunPause:boolean,model:string,onMove:abilityLeapFunc,onEnd:abilityLeapFunc,onReflex:abilityLeapFunc}
---@param options abilityLeapOptions|abilityBuffAddon
function ability.leap(options)
    sync.must()
    local sourceUnit = options.sourceUnit
    must(class.isObject(sourceUnit, UnitClass), "options.sourceUnit@Unit")
    if (type(options.targetVec) ~= "table") then
        must(class.isObject(options.targetUnit, UnitClass), "options.targetUnit@Unit")
    end
    if (sourceUnit:isLeaping()) then
        return
    end
    --- 位移互斥: 后触发的位移立即顶掉前一个(如蛇行), 保证同一时间只有一个位移在推进
    ability.moveStop(sourceUnit)

    local frequency = options.frequency or 0.03
    local speed = math.min(5000, math.max(100, options.speed or 500))
    local stunPause = (options.stunPause == true)

    local vec0 = { sourceUnit:x(), sourceUnit:y(), sourceUnit:h() }
    ---@type number[]
    local vec2
    if (type(options.targetVec) == "table") then
        vec2 = { options.targetVec[1], options.targetVec[2], options.targetVec[3] or japi.Z(options.targetVec[1], options.targetVec[2]) }
    else
        vec2 = { options.targetUnit:x(), options.targetUnit:y(), options.targetUnit:h() }
    end

    local distance = vector2.distance(vec0[1], vec0[2], vec2[1], vec2[2])
    local dtSpd = 1 / (distance / speed / frequency)
    local dtAcc = 0
    if ((options.acceleration or 0) > 0) then
        dtAcc = 1 / (distance / options.acceleration / frequency)
    end

    local vec1
    local height = options.height or 0
    if (height > 0) then
        height = vec0[3] + (vec2[3] - vec0[3]) * 0.5 + (options.height or 0) * 1.7
        local facing = vector2.angle(vec0[1], vec0[2], vec2[1], vec2[2])
        local mx, my = vector2.polar(vec0[1], vec0[2], distance / 2, facing)
        vec1 = { mx, my, height }
    end

    local flyHeight0 = sourceUnit:flyHeight()
    local animate = options.animate
    local animateDiff = (options.animateScale or 1) - sourceUnit:animateScale()

    --- 本段位移的"立即终止"入口: 自己结束或被新位移顶掉时统一走这里(销毁计时器 + 回滚 Buff)
    ---@type Timer|nil
    local timer
    local stopped = false
    local function stop(isComplete, endVec)
        if (true == stopped) then
            return
        end
        stopped = true
        if (nil ~= timer) then
            class.destroy(timer)
            timer = nil
        end
        if (sourceUnit._moveStop == stop) then
            sourceUnit._moveStop = nil
        end
        _call(isComplete, options, endVec)
    end

    options.buff = Buff({
        key = "leap",
        object = sourceUnit,
        name = options.name,
        icon = options.icon,
        description = options.description,
        ---@param buffObj Unit
        purpose = function(buffObj)
            effector.attach(buffObj, options.model, "origin")
            if (animateDiff ~= 0) then
                buffObj:animateScale("+=" .. animateDiff)
            end
            if (animate ~= nil) then
                buffObj:animate(animate)
            end
            superposition.plus(buffObj, "leap")
            superposition.plus(buffObj, "noPath")
            superposition.plus(buffObj, "pause")
        end,
        ---@param buffObj Unit
        rollback = function(buffObj)
            effector.detach(buffObj, options.model, "origin")
            if (animateDiff ~= 0) then
                buffObj:animateScale("-=" .. animateDiff)
            end
            if (animate ~= nil) then
                buffObj:animate("stand")
            end
            buffObj:flyHeight(flyHeight0)
            superposition.minus(buffObj, "pause")
            superposition.minus(buffObj, "noPath")
            superposition.minus(buffObj, "leap")
        end,
    })
    local dt = 0
    local distancePrev = distance
    local faraway = frequency * speed * 30
    local vecT = { vec0[1], vec0[2], vec0[3] }
    timer = time.setInterval(frequency, function()
        if (sourceUnit:isDead()) then
            stop(false, vecT)
            return
        end
        --- 已被新位移顶掉/外部终止: 直接退出
        if (true == stopped) then
            return
        end

        --- 眩晕中: 暂停推进(不累计进度、不位移), 眩晕结束后从原进度继续
        if (true == stunPause and true == sourceUnit:isStunning()) then
            return
        end

        local isDynTarget = type(options.targetVec) ~= "table" and nil ~= options.targetUnit and options.targetUnit:isAlive()
        if (isDynTarget) then
            vec2[1], vec2[2], vec2[3] = options.targetUnit:x(), options.targetUnit:y(), options.targetUnit:h()
            dt = dt + dtSpd * math.min(1, distance / distancePrev)
        else
            dt = dt + dtSpd
        end

        local distanceCur = distancePrev
        if (dt < 1) then
            local nx, ny, nz
            if (nil == vec1) then
                nx, ny, nz = vector3.linear(vec0, vec2, dt)
            else
                nx, ny, nz = vector3.bezier2(vec0, vec1, vec2, dt)
            end
            if (RegionPlayable:isBorder(nx, ny)) then
                stop(false, vecT)
                return
            end
            vecT[1], vecT[2], vecT[3] = nx, ny, nz
            distanceCur = vector2.distance(vecT[1], vecT[2], vec2[1], vec2[2])
        end
        if (dt >= 1) then
            sourceUnit:position(vec2[1], vec2[2])
            sourceUnit:flyHeight(vec2[3])
            sourceUnit:facing(vector2.angle(vecT[1], vecT[2], vec2[1], vec2[2]))
            stop(true, vec2)
            return
        end
        if (true == isDynTarget and dt > 0.25 and (distancePrev - distanceCur) > faraway) then
            stop(false, vecT)
            return
        end

        if (type(options.onMove) == "function") then
            if (false == options.onMove(options, vecT)) then
                stop(false, vecT)
                return
            end
        end
        --- 回调内可能已启动了新位移(本段被顶掉): 不再推进
        if (true == stopped) then
            return
        end

        J.SetUnitX(sourceUnit:handle(), vecT[1])
        J.SetUnitY(sourceUnit:handle(), vecT[2])
        sourceUnit:flyHeight(vecT[3])
        sourceUnit:facing(vector2.angle(vecT[1], vecT[2], vec2[1], vec2[2]))
        distancePrev = distanceCur
        if (dtAcc ~= 0) then
            dtSpd = dtSpd + dtAcc
        end
    end)
    --- 登记终止入口: 其它位移开始时通过 ability.moveStop 顶掉本段
    if (true == stopped) then
        class.destroy(timer)
        timer = nil
    else
        sourceUnit._moveStop = stop
    end
end

--- 立即终止单位当前正在进行的位移(冲锋/蛇行), 无位移时忽略
---@param unit Unit
---@return void
function ability.moveStop(unit)
    if (false == class.isObject(unit, UnitClass)) then
        return
    end
    local moveStop = unit._moveStop
    if (type(moveStop) == "function") then
        unit._moveStop = nil
        moveStop()
    end
end
