--- 底层技能 伤害
--[[
    对接引流 Flow `damage`
    使用 Unit:isHurting() 判断是否受伤中
    使用 Unit:isDamaging() 判断是否造成伤害中
    options = {
        sourceUnit = Unit, --[可选]源单位
        targetUnit = Unit, --[必须]目标单位
        damage = number, --[可选]伤害值，默认0
        damageSrc = MappingValue, --[可选]伤害来源，默认injury.damageSrc.common（详情查看injury.damageSrc）
        damageType = MappingValue, --[可选]伤害类型，默认injury.damageType.common （详情查看injury.damageType）
        damageTypeLevel = number, --[可选]伤害类级别（影响元素附着或自定义效果），默认0
        breakArmor = MappingValue[], --[可选]破防类型，默认{}（详情查看injury.breakArmor）
        extra = table, --[可选]自定义额外数据，框架自带的key将以“下划线”开头命名
    }
]]
---@see injury#damageType
---@see injury#damageSrc
---@see injury#breakArmorType

--- 同帧伤害嵌套深度保护
--- 伤害流程会依次触发 unitDamage / unitAttack / unitHurt 等事件, 若某个事件回调又发起新的伤害,
--- 就可能形成"伤害 -> 事件 -> 伤害"的环, 同帧无限递归, 最终以 C stack overflow 崩溃
--- (报错点往往落在无关的 __index / 单元方法上, 极难定位)。
--- 这里限制同帧嵌套层数并打印一次诊断:
---   正常战斗的嵌套深度不超过 3~4 层(普攻 -> 附加伤害 -> 反弹等), 阈值 16 足够宽松。
--- 计数按帧复位(japi._asyncInc 每帧自增), 即使某次出错没回退也只影响当前帧。
local DMG_FRAME = -1
local DMG_DEPTH = 0
local DMG_DEPTH_MAX = 16
local DMG_WARNED = false

--- 同帧最近若干次伤害记录(环形缓冲, 只在触发保护时格式化, 不产生额外GC)
local DMG_TRACE_MAX = 10
local DMG_TRACE = {}
local DMG_TRACE_IDX = 0
for i = 1, DMG_TRACE_MAX do
    DMG_TRACE[i] = {}
end

--- 单位描述(用于定位伤害链)
---@param u Unit
---@return string
local function unitDesc(u)
    if (false == class.isObject(u, UnitClass)) then
        return tostring(u)
    end
    local tpl = u:tpl()
    local speech = (type(tpl) == "table") and tostring(rawget(tpl, "_speech")) or "?"
    return string.format("%s(uid=%s,handle=%s,tpl=%s)", tostring(u:name()), tostring(u:id()), tostring(u:handle()), speech)
end

--- 打印同帧伤害链(按时间顺序)
---@return void
local function printTrace()
    local lines = { string.format("[伤害嵌套保护] 同帧伤害链(最近%d次, 按时间顺序):", DMG_TRACE_MAX) }
    for i = 1, DMG_TRACE_MAX do
        local idx = (DMG_TRACE_IDX + i - 1) % DMG_TRACE_MAX + 1
        local r = DMG_TRACE[idx]
        if (nil ~= r.s or nil ~= r.t) then
            lines[#lines + 1] = string.format("  %s -> %s 伤害=%s 来源=%s 类型=%s",
                unitDesc(r.s), unitDesc(r.t), tostring(r.d),
                tostring(r.src and r.src.value), tostring(r.dt and r.dt.value))
        end
    end
    print(table.concat(lines, '\n'))
end

--- 伤害实现(原 ability.damage 函数体)
---@param options {sourceUnit:Unit,targetUnit:Unit,damage:number,damageSrc:MappingValue,damageType:MappingValue,damageTypeLevel:number,breakArmor:MappingValue[],extra:table}
---@return void
local function damageImpl(options)
    options.damage = options.damage or 0
    if (options.damage < 1 or false == class.isObject(options.targetUnit, UnitClass)) then
        return
    end
    if (options.targetUnit:isDead()) then
        return
    end
    if (nil ~= options.sourceUnit) then
        if (false == class.isObject(options.sourceUnit, UnitClass)) then
            return
        end
        if (options.sourceUnit:isDead()) then
            return
        end
    end
    -- 禁用错误的伤害来源
    options.damageSrc = options.damageSrc or injury.damageSrc.common
    must(injury.isValidDamageSrc(options.damageSrc), "options.damageSrc@injury.damageSrc")
    if (options.damageSrc == injury.damageSrc.attack and nil ~= options.sourceUnit and options.sourceUnit:isUnArming()) then
        return
    elseif (options.damageSrc == injury.damageSrc.ability and nil ~= options.sourceUnit and options.sourceUnit:isSilencing()) then
        return
    end
    --- 触发受伤前事件
    event.syncTrigger(options.targetUnit, eventKind.unitBeforeHurt, options)
    -- 修正伤害类型
    options.damageType = options.damageType or injury.damageType.common
    must(injury.isValidDamageType(options.damageType), "options.damageType@injury.damageType")
    options.damageTypeLevel = options.damageTypeLevel or 0
    -- 修正破防类型
    options.breakArmor = options.breakArmor or {}
    if (#options.breakArmor > 0) then
        local notType = -1
        for bi, ba in ipairs(options.breakArmor) do
            if (false == injury.isValidBreakArmorType(ba)) then
                notType = bi
                break
            end
        end
        if (notType > 0) then
            must(false, "options.breakArmor[" .. notType .. "]@injury.breakArmorType")
        end
    end
    --- 对接伤害过程
    if (isFlow("damage")) then
        Flow("damage"):run(options)
    end
    --- 最终伤害
    if (options.damage >= 1) then
        if (nil ~= options.sourceUnit) then
            options.targetUnit._lastHurtSource = options.sourceUnit
            options.sourceUnit._lastDamageTarget = options.targetUnit
            superposition.plus(options.sourceUnit, "damage")
            superposition.plus(options.sourceUnit:owner(), "damage")
            time.setTimeout(3.5, function()
                if (false == class.isDestroy(options.sourceUnit)) then
                    superposition.minus(options.sourceUnit, "damage")
                    superposition.minus(options.sourceUnit:owner(), "damage")
                end
            end)
            --- 触发伤害事件
            event.syncTrigger(options.sourceUnit, eventKind.unitDamage, options)
            if (options.damageSrc == injury.damageSrc.attack) then
                event.syncTrigger(options.sourceUnit, eventKind.unitAttack, options)
            end
        end
        superposition.plus(options.targetUnit, "hurt")
        superposition.plus(options.targetUnit:owner(), "hurt")
        time.setTimeout(3.5, function()
            if (false == class.isDestroy(options.targetUnit)) then
                superposition.minus(options.targetUnit, "hurt")
                superposition.minus(options.targetUnit:owner(), "hurt")
            end
        end)
        --- 触发受伤事件
        event.syncTrigger(options.targetUnit, eventKind.unitHurt, options)
        if (options.damageSrc == injury.damageSrc.attack) then
            event.syncTrigger(options.targetUnit, eventKind.unitBeAttack, options)
        end
        options.targetUnit:hpCur("-=" .. options.damage)
    end
end

---@param options {sourceUnit:Unit,targetUnit:Unit,damage:number,damageSrc:MappingValue,damageType:MappingValue,damageTypeLevel:number,breakArmor:MappingValue[],extra:table}
---@return void
function ability.damage(options)
    sync.must()
    --- 同帧嵌套保护
    local frame = japi._asyncInc
    if (frame ~= DMG_FRAME) then
        DMG_FRAME = frame
        DMG_DEPTH = 0
        DMG_TRACE_IDX = 0
        for i = 1, DMG_TRACE_MAX do
            local r = DMG_TRACE[i]
            r.s, r.t, r.d, r.src, r.dt = nil, nil, nil, nil, nil
        end
    end
    --- 记录本次伤害(环形缓冲, 只存引用)
    DMG_TRACE_IDX = DMG_TRACE_IDX % DMG_TRACE_MAX + 1
    local rec = DMG_TRACE[DMG_TRACE_IDX]
    rec.s, rec.t, rec.d = options.sourceUnit, options.targetUnit, options.damage
    rec.src, rec.dt = options.damageSrc, options.damageType
    --- 超限中断
    if (DMG_DEPTH >= DMG_DEPTH_MAX) then
        if (false == DMG_WARNED) then
            DMG_WARNED = true
            print(string.format(
                "[伤害嵌套保护] 同帧伤害嵌套超过%d层(疑似伤害事件互相触发成环), 已中断本次伤害. 来源=%s 目标=%s 伤害=%s",
                DMG_DEPTH_MAX, unitDesc(options.sourceUnit), unitDesc(options.targetUnit), tostring(options.damage)))
            printTrace()
        end
        return
    end
    DMG_DEPTH = DMG_DEPTH + 1
    damageImpl(options)
    DMG_DEPTH = DMG_DEPTH - 1
end
