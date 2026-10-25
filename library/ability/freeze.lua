--- 底层技能 冻结|时间停止
---   来源: share-collection「freeze冻结」(library基库改造), 已按本框架适配, 逻辑保持原实现
--[[
    options = {
        whichUnit 目标单位
        duration 持续时间
        model 绑定特效路径
        attach 绑定特效位置
        red 红偏0-255
        green 绿偏0-255
        blue 蓝偏0-255
        alpha 透明度0-255
    }
]]
---@param options {whichUnit:Unit,duration:number,model:string,attach:string,red:number,green:number,blue:number,alpha:number}|abilityBuffAddon
---@return void
function ability.freeze(options)
    sync.must()
    local whichUnit = options.whichUnit
    if (nil == whichUnit) then
        return
    end
    if (false == class.isObject(whichUnit, UnitClass) or whichUnit:isDead()) then
        return
    end
    local duration = options.duration or 0
    if (duration <= 0) then
        -- 假如没有设置时间，忽略
        return
    end
    local red = options.red or 255
    local green = options.green or 255
    local blue = options.blue or 255
    local alpha = options.alpha or 255
    local attach = options.attach or "origin"
    Buff({
        key = "freeze",
        object = whichUnit,
        signal = buffSignal.down,
        name = options.name,
        icon = options.icon,
        description = options.description,
        duration = duration,
        ---@param buffObj Unit
        purpose = function(buffObj)
            effector.attach(buffObj, options.model, attach)
            buffObj:rgba(red, green, blue, alpha, duration)
            buffObj:animateScale("-=1")
        end,
        ---@param buffObj Unit
        rollback = function(buffObj)
            buffObj:animateScale("+=1")
            effector.detach(buffObj, options.model, attach)
        end,
    })
end
