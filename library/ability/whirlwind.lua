--- 模版技能 剑刃风暴
---   来源: share-collection「whirlwind剑刃风暴」(library基库改造), 已按本框架适配:
---     · 补 superposition.plus/minus("whirlwind"), 使 Unit:isWhirlwind() 可用
---     · 修正范围与伤害判定条件, 保证纯视觉(无伤害)时也能正常收尾
--[[
    使用 Unit:isWhirlwind() 判断是否释放风暴中
    options = {
        sourceUnit [必须]中心单位，同时也是伤害来源
        animateAppend = "Spin", --附加动作
        radius [必须]半径范围
        frequency [必须]伤害频率
        duration [必须]持续时间
        filter [可选]作用范围内的单位筛选器,nil则自动选择单位的敌对势力
        centerModel [可选]中心单位特效
        centerAttach 中心单位特效串附加位
        enumModel 选取单位特效串[瞬间0]
        damage 伤害
        damageSrc 伤害来源
        damageType 伤害类型
        damageTypeLevel 伤害等级
        breakArmor 破防类型
    }
]]
---@param options {sourceUnit:Unit,animateAppend:string,radius:number,frequency:number,duration:number,filter:fun(enumUnit:Unit),centerModel:string,centerAttach:string,enumModel:string,damage:number,damageSrc:table,damageType:table,damageTypeLevel:number,breakArmor:table}
---@return void
function ability.whirlwind(options)
    sync.must()
    must(class.isObject(options.sourceUnit, UnitClass), "options.sourceUnit@Unit")
    local frequency = math.max(0, options.frequency or 0)
    local duration = math.max(0, options.duration or 0)
    must(duration >= frequency, "options.duration must be greater than or equal to options.frequency")
    if (options.sourceUnit:isWhirlwind()) then
        return
    end
    local radius = options.radius or 0
    local damage = options.damage or 0
    if (radius <= 0 or frequency <= 0) then
        return
    end
    local animateAppend = options.animateAppend or "Spin"
    options.centerAttach = options.centerAttach or "origin"
    effector.attach(options.sourceUnit, options.centerModel, options.centerAttach, duration)
    options.sourceUnit:animateProperties(animateAppend, true)
    superposition.plus(options.sourceUnit, "whirlwind")
    local ti = 0
    local filter = options.filter or function(enumUnit)
        return enumUnit:isAlive() and enumUnit:isEnemy(options.sourceUnit:owner())
    end
    time.setInterval(frequency, function(curTimer)
        ti = ti + frequency
        if (ti >= duration) then
            class.destroy(curTimer)
            options.sourceUnit:animateProperties(animateAppend, false)
            superposition.minus(options.sourceUnit, "whirlwind")
            return
        end
        local enumUnits = Group(UnitClass):catch({
            circle = {
                x = options.sourceUnit:x(),
                y = options.sourceUnit:y(),
                radius = radius,
            },
            filter = filter
        })
        for _, eu in ipairs(enumUnits) do
            effector.unit(options.enumModel, eu, 0)
            ability.damage({
                sourceUnit = options.sourceUnit,
                targetUnit = eu,
                damage = damage,
                damageSrc = options.damageSrc or injury.damageSrc.ability,
                damageType = options.damageType or injury.damageType.common,
                damageTypeLevel = options.damageTypeLevel,
                breakArmor = options.breakArmor or { injury.breakArmorType.avoid },
            })
        end
    end)
end
