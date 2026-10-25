--- 模版技能 分裂
---   来源: share-collection「split分裂」(library基库改造), 已按本框架适配, 逻辑保持原实现
--[[
    options = {
        sourceUnit 源单位
        targetUnit 目标单位
        radius 分裂半径
        damage 伤害值，模拟攻击百分比自行先计算
        damageSrc 伤害来源（默认ability）
        damageType 伤害类型（影响元素反应或自定义效果）
        damageTypeLevel 伤害类级别（影响元素附着或自定义效果）
        breakArmor 破甲类型（默认无视回避）
        model 分裂点特效路径
        containSelf 是否包含目标自身
    }
]]
---@param options {sourceUnit:Unit,targetUnit:Unit,radius:number,damage:number,damageSrc:table,damageType:table,damageTypeLevel:number,breakArmor:table,model:string,containSelf:boolean}
---@return void
function ability.split(options)
    sync.must()
    local sourceUnit = options.sourceUnit
    local targetUnit = options.targetUnit
    if (false == class.isObject(sourceUnit, UnitClass) or sourceUnit:isDead()) then
        return
    end
    if (false == class.isObject(targetUnit, UnitClass) or targetUnit:isDead()) then
        return
    end
    local radius = options.radius or 200
    local damage = options.damage or 0
    if (damage > 0) then
        local containSelf = false
        if (type(options.containSelf) == "boolean") then
            containSelf = options.containSelf
        end
        local filter
        if (containSelf) then
            ---@param enumUnit Unit
            filter = function(enumUnit)
                return enumUnit:isAlive() and sourceUnit:isEnemy(enumUnit:owner())
            end
        else
            ---@param enumUnit Unit
            filter = function(enumUnit)
                return enumUnit:isAlive() and false == enumUnit:isSelf(targetUnit) and sourceUnit:isEnemy(enumUnit:owner())
            end
        end
        local enumUnits = Group(UnitClass):catch({
            filter = filter,
            circle = {
                x = targetUnit:x(),
                y = targetUnit:y(),
                radius = radius,
            },
        })
        if (#enumUnits > 0) then
            for _, eu in ipairs(enumUnits) do
                effector.unit(options.model, eu, 0.6)
                ability.damage({
                    sourceUnit = sourceUnit,
                    targetUnit = eu,
                    damage = damage,
                    damageSrc = options.damageSrc or injury.damageSrc.ability,
                    damageType = options.damageType or injury.damageType.common,
                    damageTypeLevel = options.damageTypeLevel,
                    breakArmor = options.breakArmor or { injury.breakArmorType.avoid },
                })
            end
        end
    end
end
