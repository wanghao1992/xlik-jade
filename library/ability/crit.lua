--- 底层技能 暴击
---   来源: share-collection「crit暴击」(library基库改造), 已按本框架适配, 逻辑保持原实现
--[[
    options = {
        sourceUnit 伤害来源
        targetUnit 目标单位
        model 模型路径
        damage 暴击最终伤害
        damageSrc 伤害来源 injury.damageSrc
        damageType 伤害类型
        damageTypeLevel 伤害等级
        breakArmor 破防类型
    }
]]
---@param options {sourceUnit:Unit,targetUnit:Unit,model:string,damage:number,damageSrc:table,damageType:table,damageTypeLevel:number,breakArmor:table}
---@return void
function ability.crit(options)
    sync.must()
    local sourceUnit = options.sourceUnit
    local targetUnit = options.targetUnit
    if (false == class.isObject(sourceUnit, UnitClass) or sourceUnit:isDead()) then
        return
    end
    if (false == class.isObject(targetUnit, UnitClass) or targetUnit:isDead()) then
        return
    end
    effector.unit(options.model, targetUnit, 0.2)
    local damage = options.damage or 0
    if (damage > 0) then
        ability.damage({
            sourceUnit = sourceUnit,
            targetUnit = targetUnit,
            damage = damage,
            damageSrc = options.damageSrc or injury.damageSrc.ability,
            damageType = options.damageType or injury.damageType.common,
            damageTypeLevel = options.damageTypeLevel,
            breakArmor = options.breakArmor or { injury.breakArmorType.avoid }
        })
    end
end
