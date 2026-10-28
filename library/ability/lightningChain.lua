--- 模版技能 闪电链
---   来源: share-collection「lightningChain闪电链」(library基库改造), 已按本框架适配:
---     · 修正伤害参数中 damageTypeLevel 的字段名(原为 dmgTypeLv, 会导致等级丢失)
--[[
    模版技能 闪电链
    options = {
        sourceUnit 伤害来源
        targetUnit 目标单位
        lightningKind 闪电效果类型(可选 详情查看 lightning.kind)
        qty = 1, --传递的最大单位数（可选，默认1）
        rate = 0, --增减率%（可选，默认不增不减为0，范围建议[-100,100]）
        radius = 600, --寻找下一目标的作用半径范围（可选，默认600）
        isRepeat = false, --是否允许同一个单位重复打击（最近2次打击不会是同一个，repeat也不能打击同一个单体单位多次）
        damage 伤害
        damageSrc 伤害来源 injury.damageSrc
        damageType 伤害类型 injury.damageType
        damageTypeLevel 伤害等级默认1
        breakArmor 破防类型 injury.breakArmorType
        onHit = function(dmgParams), --命中回调(可选), dmgParams.damage 为本次实际伤害值
        prevUnit = [unit], --隐藏的参数，上一个的目标单位（必须有，用于构建两点间闪电特效）
        index = 1,--隐藏的参数，用于暗地里记录是第几个被电到的单位
        repeatGroup = [group],--隐藏的参数，用于暗地里记录单位是否被电过
    }
]]
---@private
---@param index number
---@param lightningKind table
---@param prevUnit Unit
---@param dmgParams table
---@return void
local _call = function(index, lightningKind, prevUnit, dmgParams)
    local targetUnit = dmgParams.targetUnit
    local sourceUnit = dmgParams.sourceUnit
    local sx, sy, sz
    local tx, ty, th = targetUnit:x(), targetUnit:y(), targetUnit:h()
    if (class.isObject(prevUnit, UnitClass)) then
        sx, sy, sz = prevUnit:x(), prevUnit:y(), prevUnit:h()
    elseif (class.isObject(sourceUnit, UnitClass)) then
        sx, sy, sz = sourceUnit:x(), sourceUnit:y(), sourceUnit:h()
    else
        sx, sy, sz = tx, ty, th + 1000  --头顶劈下
    end
    lightning.create(lightningKind, sx, sy, sz, tx, ty, th, 0.25)
    ability.damage(dmgParams)
    if (type(dmgParams.onHit) == "function") then
        dmgParams.onHit(dmgParams)
    end
end

---@param options {sourceUnit:Unit,targetUnit:Unit,lightningKind:table,qty:number,rate:number,radius:number,isRepeat:boolean,damage:number,damageSrc:table,damageType:table,damageTypeLevel:number,breakArmor:table,extra:table,onHit:fun(dmgParams:table)}
---@return void
function ability.lightningChain(options)
    sync.must()
    local sourceUnit = options.sourceUnit
    local targetUnit = options.targetUnit
    if (false == class.isObject(targetUnit, UnitClass) or targetUnit:isDead()) then
        return
    end
    local damage = options.damage or 0
    if (damage > 0) then
        local lightningKind = options.lightningKind or lightning.kind.thunder
        local qty = options.qty or 1
        local rate = 100
        local index = 1
        local dmgParams = {
            sourceUnit = sourceUnit,
            targetUnit = targetUnit,
            damage = damage * rate * 0.01,
            damageSrc = options.damageSrc or injury.damageSrc.ability,
            damageType = options.damageType or injury.damageType.common,
            damageTypeLevel = options.damageTypeLevel or 1,
            breakArmor = options.breakArmor or { injury.breakArmorType.avoid },
            extra = options.extra,
            onHit = options.onHit,
        }
        _call(index, lightningKind, nil, dmgParams)
        qty = qty - 1
        if (qty > 0) then
            local radius = options.radius or 600
            local isRepeat = options.isRepeat or false
            local repeatJudge = { [targetUnit:id()] = 1 }
            time.setInterval(0.25, function(curTimer)
                if (qty <= 0 or class.isDestroy(dmgParams.targetUnit)) then
                    class.destroy(curTimer)
                    return
                end
                if (options.rate) then
                    rate = rate + options.rate
                end
                index = index + 1
                local nextUnit = Group(UnitClass):closest({
                    circle = {
                        x = dmgParams.targetUnit:x(),
                        y = dmgParams.targetUnit:y(),
                        radius = radius,
                    },
                    ---@param enumUnit Unit
                    filter = function(enumUnit)
                        if (nil ~= repeatJudge[enumUnit:id()]) then
                            return false
                        end
                        if (class.isDestroy(enumUnit) or enumUnit:isDead()) then
                            return false
                        end
                        if (nil == sourceUnit or class.isDestroy(sourceUnit)) then
                            return enumUnit:isAlly(dmgParams.targetUnit:owner())
                        else
                            return enumUnit:isEnemy(sourceUnit:owner())
                        end
                    end,
                })
                if (nil == nextUnit) then
                    class.destroy(curTimer)
                    return
                end
                if (true ~= isRepeat) then
                    repeatJudge[nextUnit:id()] = 1
                end
                dmgParams.damage = damage * rate * 0.01
                local prevUnit = dmgParams.targetUnit
                dmgParams.targetUnit = nextUnit
                _call(index, lightningKind, prevUnit, dmgParams)
                qty = qty - 1
            end)
        end
    end
end
