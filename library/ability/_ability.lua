--- 技能模组，通用的技能处理方法规则函数，包含技能通用的执行过程，用于Ability或单独调用
---@alias abilityBuffAddon {name:string,icon:string,description:string[]}
---@class ability
ability = ability or {}

-- 技能目标类型数据
local m_tt = Mapping("abilityTargetType")
ability.targetType = {
    pas = m_tt:set("p", "被动"),
    none = m_tt:set("n", "无目标"),
    unit = m_tt:set("u", "单位目标"),
    loc = m_tt:set("l", "点目标"),
    circle = m_tt:set("c", "圆形范围目标"),
    square = m_tt:set("s", "方形范围目标"),
    build = m_tt:set("b", "建造"),
}

--- 检测是否属于有效的技能目标类型
---@param value table ability.targetType.*
---@return boolean
function ability.isValidTargetType(value)
    return isMapping(value, m_tt._kind)
end

--- [实际]计算整合数值型
--- 根据base、vary计算出技能该等级时对应的数据
--- 公式：base + (level-1) * vary
---@param obj Ability
---@param whichLevel number|nil
---@param abKey string 技能取值key
---@param uPercent string|nil 单位百分比变化取值key
---@param uFixed string|nil 单位固定变化取值key
---@return number
function ability.caleValueNumber(obj, whichLevel, abKey, uPercent, uFixed)
    whichLevel = whichLevel or obj:level()
    local base = abKey .. "Base"
    local vary = abKey .. "Vary"
    local val = (obj:get(base) or 0) + (whichLevel - 1) * (obj:get(vary) or 0)
    ---@type Unit
    local u = obj:get("bindUnit")
    if (class.isObject(u, UnitClass)) then
        if (uPercent) then
            local p = u:get(uPercent)
            if (type(p) == "number") then
                val = val * (1 + 0.01 * p)
            end
        end
        if (uFixed) then
            local f = u:get(uFixed)
            if (type(f) == "number") then
                val = val + f
            end
        end
    end
    return val
end

--- [成长推导]随耗
--- 根据配置的数据设定记录技能成长推导数据的通用进展配置方法
---@param whichAbility AbilityTpl|Ability
---@param key string
---@param base number|table
---@param vary number|table
---@param cond function 条件执行回调
---@param deplete function 实消执行回调
---@param value function 实际数值回调
---@param reason string|nil 原因声明
---@return AbilityTpl|Ability
function ability.anyCostAdv(whichAbility, key, base, vary, cond, deplete, value, reason)
    if (nil ~= base) then
        whichAbility:set(key .. "CostBase", base)
    end
    if (nil ~= vary) then
        whichAbility:set(key .. "CostVary", vary)
    end
    ---@type Array
    local costAdv = whichAbility:get("costAdv")
    if (nil == costAdv) then
        costAdv = Array()
        whichAbility:set("costAdv", costAdv)
    end
    costAdv:set(key, { cond = cond, deplete = deplete, value = value, reason = reason })
    return whichAbility
end

--- [实际]随耗
--- 根据adv进展配置值获得技能该等级的消耗数据
---@param whichAbility AbilityTpl|Ability
---@param key string
---@param whichLevel number|nil
---@param default any
---@return number|table
function ability.anyCost(whichAbility, key, whichLevel, default)
    local costAdv = whichAbility:get("costAdv")
    if (isArray(costAdv)) then
        local any = costAdv:get(key)
        if (type(any) == "table") then
            local f = any.value
            if (type(f) == "function") then
                return f(whichAbility, whichLevel)
            end
        end
    end
    return default
end

--- [实际]计算整合资源型
--- 根据base、vary计算出技能该等级的财物消耗数据
--- 公式：base + (level-1) * vary
---@param obj Ability
---@param whichLevel number|nil
---@return number
function ability.caleValueWorth(obj, whichLevel)
    local base = obj:get("worthCostBase")
    if (nil == base) then
        return
    end
    whichLevel = whichLevel or obj:level()
    local worthKeys = worth.get():keys()
    local val = {}
    local vary = nil
    if (whichLevel > 1) then
        vary = obj:get("worthCostVary")
    end
    for _, k in ipairs(worthKeys) do
        if (type(base[k]) == "number" and base[k] ~= 0) then
            val[k] = base[k]
        end
        if (type(vary) == "table" and type(vary[k]) == "number" and vary[k] ~= 0) then
            val[k] = (val[k] or 0) + (whichLevel - 1) * vary[k]
        end
    end
    ---@type Unit
    local u = obj:get("bindUnit")
    if (class.isObject(u, UnitClass)) then
        local p = u:costPercent()
        if (type(p) == "number") then
            val = worth.cale(val, "*", 1 + 0.01 * p)
        end
        local fixed = u:costWorth()
        if (nil ~= fixed) then
            val = worth.cale(val, "+", fixed)
        end
    end
    return val
end

--- 取消耗结算用的绑定单位
--- 技能在"已被移除/正在重绑"时 bindUnit() 会返回 nil(例如转职重置技能栏、宝物/装备临时给技能),
--- 此时若直接 obj:bindUnit():xxx() 会报 attempt to index a nil value, 这里统一兜底。
---@param obj Ability
---@return Unit|nil
local function costUnit(obj)
    local u = obj:bindUnit()
    if (false == class.isObject(u, UnitClass)) then
        return nil
    end
    return u
end

--- [实际]HP
--- 用于获取HP实际消耗的计算方法
---@param obj Ability
---@return void
function ability.hpCostValue(obj, whichLevel)
    local val = ability.caleValueNumber(obj, whichLevel, "hpCost", "costPercent", "cost")
    return math.ceil(math.max(0, val))
end

--- [条件]HP
--- HP消耗条件的判定方法
---@param obj Ability
---@return boolean
function ability.hpCostCond(obj)
    local val = ability.hpCostValue(obj)
    if (val <= 0) then
        return true
    end
    local u = costUnit(obj)
    if (nil == u) then
        --- 未绑定单位(技能已被移除/重绑中): 视为不可施放, 避免空引用
        return false
    end
    return val < u:hpCur()
end

--- [实消]HP
--- HP变动消耗后削减的执行方法
---@param obj Ability
---@return void
function ability.hpCostDeplete(obj)
    sync.must()
    local u = costUnit(obj)
    if (nil == u) then
        return
    end
    local val = ability.hpCostValue(obj)
    u:hpCur("-=" .. val)
end

--- [实际]MP
--- 用于获取MP实际消耗的计算方法
---@param obj Ability
---@return void
function ability.mpCostValue(obj, whichLevel)
    local val = ability.caleValueNumber(obj, whichLevel, "mpCost", "costPercent", "cost")
    return math.ceil(math.max(0, val))
end

--- [条件]MP
--- MP消耗条件的判定方法
---@param obj Ability
---@return boolean
function ability.mpCostCond(obj)
    local val = ability.mpCostValue(obj)
    if (val <= 0) then
        return true
    end
    local u = costUnit(obj)
    if (nil == u) then
        --- 未绑定单位(技能已被移除/重绑中): 视为不可施放, 避免空引用
        return false
    end
    return val <= u:mpCur()
end

--- [实消]MP
--- MP变动消耗后削减的执行方法
---@param obj Ability
---@return void
function ability.mpCostDeplete(obj)
    sync.must()
    local u = costUnit(obj)
    if (nil == u) then
        return
    end
    local val = ability.mpCostValue(obj)
    u:mpCur("-=" .. val)
end

--- [实际]资源型
--- 用于获取财物资源实际消耗的计算方法
---@param obj Ability
---@return void
function ability.worthCostValue(obj, whichLevel)
    local val = ability.caleValueWorth(obj, whichLevel)
    return worth.l2u(val)
end

--- [条件]资源型
--- 财物资源消耗条件的判定方法
---@param obj Ability
---@return boolean
function ability.worthCostCond(obj)
    local val = ability.worthCostValue(obj)
    local u = costUnit(obj)
    local owner = obj._triggerPlayer or PlayerLocal() or (nil ~= u and u:owner()) or nil
    if (false == class.isObject(owner, PlayerClass)) then
        --- 无法定位所属玩家(技能已被移除/重绑中): 视为不可施放
        return false
    end
    return not (nil ~= val and worth.greater(val, owner:worth()))
end

--- [实消]资源型
--- 财物资源变动消耗后削减的执行方法
---@param obj Ability
---@return void
function ability.worthCostDeplete(obj)
    sync.must()
    local val = ability.worthCostValue(obj)
    local u = costUnit(obj)
    local owner = obj._triggerPlayer or (nil ~= u and u:owner()) or nil
    if (false == class.isObject(owner, PlayerClass)) then
        return
    end
    owner:worth("-", val)
end