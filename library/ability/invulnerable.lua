--- 底层技能 无敌
--[[
    使用 Unit:isInvulnerable() 判断是否无敌
    options = {
        whichUnit = Unit, --[必须]目标单位
        duration = Unit, --[必须]持续时间（秒），默认0
        model = string, --[可选]绑定特效路径，默认DivineShieldTarget
        attach = string, --[可选]绑定特效位置，默认origin
        native = boolean, --[可选]是否挂原生 Avul，默认true；false 时仅伤害归零，单位仍可被选中/攻击
    }
    native=false 用于不希望敌方因"目标不可攻击"而丢失目标回巢的场景(如全程无敌的持续输出技能)
]]
---@param options {whichUnit:Unit,duration:number,model:string,attach:string,native:boolean}|abilityBuffAddon
---@return void
function ability.invulnerable(options)
    sync.must()
    local whichUnit = options.whichUnit
    if (false == class.isObject(whichUnit, UnitClass) or whichUnit:isDead()) then
        return
    end
    local duration = options.duration or 0
    if (duration <= 0) then
        return
    end
    local useNative = options.native
    if (nil == useNative) then
        useNative = true
    end
    --- 原生 Avul 会让单位不可被选为攻击目标, 敌方会丢失目标并返回原处;
    ---   非原生时只挂 "damageImmune", 由伤害流程把伤害归零
    local immuneKey = (true == useNative) and "invulnerable" or "damageImmune"
    local model = options.model or "DivineShieldTarget"
    local attach = options.attach or "origin"
    Buff({
        key = "invulnerable",
        object = whichUnit,
        signal = buffSignal.up,
        name = options.name,
        icon = options.icon,
        duration = duration,
        description = options.description,
        ---@param buffObj Unit
        purpose = function(buffObj)
            effector.attach(buffObj, model, attach)
            superposition.plus(buffObj, immuneKey)
        end,
        ---@param buffObj Unit
        rollback = function(buffObj)
            effector.detach(buffObj, model, attach)
            superposition.minus(buffObj, immuneKey)
        end,
    })
end