--- 单位目标技能 蛇形移动
---   来源: share-collection「serpentine蛇行」(library基库改造), 已按本框架适配:
---     · 补 superposition.plus/minus("serpentine"), 使 Unit:isSerpentine() 可用
--[[
    单位目标技能 蛇形移动
    蛇形移动不影响高度移动，扭动状态在每次使用时翻转
    使用 Unit:isSerpentine() 判断是否蛇形移动中
    options = {
        sourceUnit, --[必须]蛇形移动单位，同时也是伤害来源
        targetUnit, --[可选]目标单位（有单位目标，那么冲击跟踪到单位就结束）
        targetVec = number[] len:2[可选]强制设定目标坐标
        model = nil, --[可选]蛇形移动单位origin特效
        animate = "attack", --[可选]蛇形移动动作
        animateScale = 1.00, --[可选]蛇形移动的动画速度
        frequency = 0.03, --[可选]刷新周期，默认0.03
        speed = 500, --[可选]每秒冲击的距离（默认1秒500px）
        acceleration = 0, --[可选]冲击加速度（每个周期[0.02秒]都会增加一次）
        point1 = 0.3, --[可选]偏移点1，默认0.3，不大于point2
        offset1 = 200, --[可选]偏移距离值1，默认200
        point2 = 0.7, --[可选]偏移点2，默认0.7，不大于0.9
        offset2 = 200, --[可选]偏移距离值2，默认200
        pause = true, --[可选]是否暂停单位（默认true；false时蛇行期间仍可攻击/施法）
        facing = true, --[可选]是否每周期强制朝向移动方向（默认true；false时朝向交给外部控制, 避免打断攻击转向）
        stunPause = false, --[可选]眩晕时是否暂停推进（默认false；true时眩晕期间停在原地, 眩晕结束后继续）
        pauseKey = nil, --[可选]带该Buff(key)时暂停推进(如传送), 结束后从原进度继续
        visible = true, --[可选]是否在Buff栏显示本段蛇行的内部Buff（默认true；外部已有常驻展示Buff时传false）
        onMove = abilitySerpentineFunc, --[可选]每周期移动回调（return false时可强行中止循环）
        onEnd = abilitySerpentineFunc, --[可选]结束回调（弹跳完毕才算结束）
    }
]]
---@alias abilitySerpentineFunc fun(options:abilitySerpentineOptions,vec:number[]):nil|boolean
---@alias abilitySerpentineOptions {sourceUnit:Unit,targetUnit:Unit,targetVec:number[],animate:string|number,animateScale:number,frequency:number,speed:number,acceleration:number,point1:number,point2:number,offset1:number,offset2:number,pause:boolean,facing:boolean,stunPause:boolean,model:string,onMove:abilitySerpentineFunc,onEnd:abilitySerpentineFunc}
---@private
---@param isComplete boolean
---@param options abilitySerpentineOptions
---@param vec number[]
---@return void
local _call = function(isComplete, options, vec)
    options.buff:rollback()
    options.buff = nil
    local res = isComplete
    if (true == res) then
        if (type(options.onEnd) == "function") then
            res = options.onEnd(options, vec)
        end
    end
end

---@param options abilitySerpentineOptions|abilityBuffAddon
function ability.serpentine(options)
    sync.must()
    local sourceUnit = options.sourceUnit
    must(class.isObject(sourceUnit, UnitClass), "options.sourceUnit@Unit")
    if (type(options.targetVec) ~= "table") then
        must(class.isObject(options.targetUnit, UnitClass), "options.targetUnit@Unit")
    end
    if (sourceUnit:isSerpentine()) then
        return
    end
    --- 位移互斥: 后触发的位移立即顶掉前一个(如冲锋), 保证同一时间只有一个位移在推进
    ability.moveStop(sourceUnit)

    local frequency = options.frequency or 0.03
    local speed = math.min(5000, math.max(100, options.speed or 500))
    local pauseUnit = (options.pause ~= false)
    local facingLock = (options.facing ~= false)
    local stunPause = (options.stunPause == true)
    local pauseKey = options.pauseKey

    local vec0 = { sourceUnit:x(), sourceUnit:y() }
    ---@type number[]
    local vec3
    if (type(options.targetVec) == "table") then
        vec3 = { options.targetVec[1], options.targetVec[2] }
    else
        vec3 = { options.targetUnit:x(), options.targetUnit:y() }
    end

    local distance = vector2.distance(vec0[1], vec0[2], vec3[1], vec3[2])
    local dtSpd = 1 / (distance / speed / frequency)
    local dtAcc = 0
    if ((options.acceleration or 0) > 0) then
        dtAcc = 1 / (distance / options.acceleration / frequency)
    end
    local facing = vector2.angle(vec0[1], vec0[2], vec3[1], vec3[2])

    local turn1, turn2 = 90, -90
    if (nil ~= sourceUnit._serpentine) then
        turn1, turn2 = -90, 90
        sourceUnit._serpentine = nil
    else
        sourceUnit._serpentine = true
    end
    local point1, offset1 = options.point1 or 0.3, options.offset1 or 200
    local mx, my = vector2.polar(vec0[1], vec0[2], distance * point1, facing)
    mx, my = vector2.polar(mx, my, offset1 * 4, facing + turn1)
    local vec1 = { mx, my }
    local point2, offset2 = options.point2 or 0.6, options.offset2 or 200
    mx, my = vector2.polar(vec0[1], vec0[2], distance * point2, facing)
    mx, my = vector2.polar(mx, my, offset2 * 3, facing + turn2)
    local vec2 = { mx, my }

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
        key = "serpentine",
        object = sourceUnit,
        name = options.name,
        icon = options.icon,
        description = options.description,
        visible = options.visible,
        ---@param buffObj Unit
        purpose = function(buffObj)
            effector.attach(buffObj, options.model, "origin")
            if (animateDiff ~= 0) then
                buffObj:animateScale("+=" .. animateDiff)
            end
            if (animate ~= nil) then
                buffObj:animate(animate)
            end
            superposition.plus(buffObj, "serpentine")
            superposition.plus(buffObj, "noPath")
            if (pauseUnit) then
                superposition.plus(buffObj, "pause")
            end
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
            if (pauseUnit) then
                superposition.minus(buffObj, "pause")
            end
            superposition.minus(buffObj, "noPath")
            superposition.minus(buffObj, "serpentine")
        end,
    })
    local dt = 0
    local distancePrev = distance
    local vecT = { vec0[1], vec0[2] }

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

        --- 传送等外部暂停: 停在原地不推进, 结束后从原进度继续
        if (type(pauseKey) == "string" and true == BuffHas(sourceUnit, pauseKey)) then
            return
        end

        if (type(options.targetVec) ~= "table" and nil ~= options.targetUnit and options.targetUnit:isAlive()) then
            vec3[1], vec3[2] = options.targetUnit:x(), options.targetUnit:y()
            dt = dt + dtSpd * math.min(1, distance / distancePrev)
        else
            dt = dt + dtSpd
        end

        local distanceCur = distancePrev
        if (dt < 1) then
            local nx, ny = vector2.bezier3(vec0, vec1, vec2, vec3, dt)
            if (RegionPlayable:isBorder(nx, ny)) then
                stop(false, vecT)
                return
            end
            vecT[1], vecT[2] = nx, ny
            distanceCur = vector2.distance(vecT[1], vecT[2], vec3[1], vec3[2])
        end
        if (dt >= 1) then
            sourceUnit:position(vec3[1], vec3[2])
            if (facingLock) then
                sourceUnit:facing(vector2.angle(vecT[1], vecT[2], vec3[1], vec3[2]))
            end
            stop(true, vec3)
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
        if (facingLock) then
            sourceUnit:facing(vector2.angle(vecT[1], vecT[2], vec3[1], vec3[2]))
        end
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
