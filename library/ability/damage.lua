--- 底层技能 伤害
--[[
    对接引流 Flow `damage`
    使用 Unit:isHurting() 判断是否受伤中
    使用 Unit:isDamaging() 判断是否造成伤害中

    options 字段约定(全部由本模块统一初始化, 业务只需填「入参」分区):
      入参   : sourceUnit / targetUnit / damage / damageSrc / damageType / damageTypeLevel / breakArmor / extra
      中间值 : defend(结算护甲) / crit(是否暴击) / critDamage(暴击伤害%) / damage(逐段结算后的伤害)
      标记   : fixedHp(按最大生命百分比的固定伤害) / absorbed(被护盾吸收量) / capped(是否被伤害上限截断)
               counter(元素克制倍率) / amplify(增伤加区, 见 projects/demo 的 damaging.lua)
    说明: 中间值/标记在 Flow 执行前统一给好默认值, flux 出错也不会让后续分段连锁拿到 nil;
          sourceAttr/targetAttr 缓存属性表引用, 避免各 flux 反复做 sourceUnit._attr 链式取值。

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

--- 受伤/造成伤害状态的持续时间(秒)
--- 同一单位在持续时间内再次受到伤害时只刷新到期时间, 不再新建计时器
local HURT_STATE_TIME = 3.5

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

--- 结束某状态(触发 superposition 回退)
---@param obj Object
---@param key string
---@return void
local function hurtStateDown(obj, key)
    if (nil == obj) then
        return
    end
    local states = obj._hurtStates
    local st = states and states[key]
    if (nil == st) then
        return
    end
    states[key] = nil
    st._timer = nil
    if (false == class.isDestroy(obj)) then
        superposition.minus(obj, key)
    end
end

--- 刷新某单位的伤害/受伤状态(同一 key 单计时器)
--- 旧实现每次伤害都新建 3.5s 计时器, 高频伤害(持续伤害/AoE)会堆积大量计时器;
--- 这里改为"单位 + key"唯一计时器, 重复触发只把到期时间往后推。
---@param obj Object
---@param key string
---@return void
local function refreshHurtState(obj, key)
    if (nil == obj) then
        return
    end
    local states = obj._hurtStates
    if (nil == states) then
        states = {}
        obj._hurtStates = states
    end
    local untilTime = time._inc * 0.01 + HURT_STATE_TIME
    local st = states[key]
    if (nil ~= st) then
        st._until = untilTime
        return
    end
    st = { _until = untilTime, _timer = nil }
    states[key] = st
    superposition.plus(obj, key)
    local function tick()
        local left = st._until - time._inc * 0.01
        if (left > 0) then
            st._timer = time.setTimeout(left, tick)
            return
        end
        hurtStateDown(obj, key)
    end
    st._timer = time.setTimeout(HURT_STATE_TIME, tick)
end

--- 单次伤害上限(按目标最大生命的百分比)
--- 配置 game.config.damage_cap_percent = 50 表示单次最多造成目标 50% 最大生命的伤害;
--- 0 / 未配置 表示不限制(默认关闭, 不改变原有数值)。
---@param u Unit
---@return number 上限值(<=0 表示不限制)
local function damageCap(u)
    local pct = (type(game.config) == "table") and tonumber(game.config.damage_cap_percent) or nil
    if (nil == pct or pct <= 0) then
        return 0
    end
    local hp = tonumber(u:get("hp")) or 0
    if (hp <= 0) then
        return 0
    end
    return math.max(1, math.floor(hp * pct * 0.01))
end

--- 护盾吸收
--- 护盾是纯 Lua 属性(unit:shieldCur), 不写入引擎生命值, 因此在扣血前先行消耗。
--- 未设置护盾的单位 _shield / _shieldCur 为 0, 此函数直接返回 0(与旧行为完全一致)。
---@param u Unit
---@param damage number
---@return number 实际吸收量
local function absorbShield(u, damage)
    if (damage <= 0) then
        return 0
    end
    local shield = tonumber(u:get("shieldCur")) or 0
    if (shield <= 0) then
        return 0
    end
    local take = math.min(shield, damage)
    u:set("shieldCur", shield - take)
    return take
end

--- 伤害实现(原 ability.damage 函数体)
---@param options table
---@return void
local function damageImpl(options)
    --- ===== 入参整理 =====
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

    --- ===== 中间值/标记初始化 =====
    --- 业务 flux 直接读写这些字段, 不必各自兜底; 单个 flux 抛错也不会让后续分段拿到 nil
    options.defend = 0
    options.crit = false
    options.critDamage = 0
    options.absorbed = 0
    options.capped = false
    --- 按最大生命百分比的固定伤害: 不吃暴击/附魔/天赋/宝物等倍率(见 projects/demo 的 damaging.lua)
    options.fixedHp = (type(options.extra) == "table" and true == options.extra._percentHp)
    --- 属性表引用缓存(各 flux 共用, 避免重复链式取值)
    options.sourceAttr = (nil ~= options.sourceUnit and options.sourceUnit._attr) or false
    options.targetAttr = options.targetUnit._attr or false

    --- 对接伤害过程
    if (isFlow("damage")) then
        Flow("damage"):run(options)
    end

    --- ===== 最终伤害结算(下限 -> 取整 -> 上限 -> 护盾 -> 扣血) =====
    --- 伤害下限: 结算后不足 1 点视为无效伤害(不触发伤害/受伤事件, 与旧行为一致)
    if (options.damage < 1) then
        return
    end
    --- 统一取整: 避免 hpCur 收到 12.7000000001 之类的浮点串, 也避免尾差累积
    local damage = math.max(1, math.round(options.damage))
    --- 单次伤害上限(默认不限制)
    local cap = damageCap(options.targetUnit)
    if (cap > 0 and damage > cap) then
        damage = cap
        options.capped = true
    end
    --- 护盾吸收(无护盾时 absorbed = 0, 与旧行为一致)
    local absorbed = absorbShield(options.targetUnit, damage)
    if (absorbed > 0) then
        options.absorbed = absorbed
        damage = damage - absorbed
    end
    options.damage = damage
    --- 被护盾完全吸收: 不触发伤害/受伤事件
    if (damage < 1) then
        return
    end

    if (nil ~= options.sourceUnit) then
        options.targetUnit._lastHurtSource = options.sourceUnit
        options.sourceUnit._lastDamageTarget = options.targetUnit
        refreshHurtState(options.sourceUnit, "damage")
        refreshHurtState(options.sourceUnit:owner(), "damage")
        --- 触发伤害事件
        event.syncTrigger(options.sourceUnit, eventKind.unitDamage, options)
        if (options.damageSrc == injury.damageSrc.attack) then
            event.syncTrigger(options.sourceUnit, eventKind.unitAttack, options)
        end
    end
    refreshHurtState(options.targetUnit, "hurt")
    refreshHurtState(options.targetUnit:owner(), "hurt")
    --- 触发受伤事件
    event.syncTrigger(options.targetUnit, eventKind.unitHurt, options)
    if (options.damageSrc == injury.damageSrc.attack) then
        event.syncTrigger(options.targetUnit, eventKind.unitBeAttack, options)
    end
    options.targetUnit:hpCur("-=" .. options.damage)
end

---@see injury.damageType
---@see injury.damageSrc
---@see injury.breakArmorType
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
