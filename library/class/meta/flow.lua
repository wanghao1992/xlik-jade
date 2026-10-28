--- current class name
FlowClass = "Flow"

--- 流执行，业务片段顺序执行定义
--- 片段支持 priority(越小越先, 默认0, 同优先级按注册顺序), 便于多模块各自注册时控制结算顺序
--- after 片段在全部 flux 执行完且未触发中止后执行, 用于吸血/挂debuff等"结算后"逻辑
---@class Flow:Meta
local _index = Meta(FlowClass)

--- 设置伤害过程中止条件
---@param func fun(data:table):boolean
---@return void
function _index:abort(func)
    sync.must()
    if (type(func) == "function") then
        self._abort = func
    end
end

---@private 生成按 priority(升序) + 注册顺序排好的片段列表
---@param arr Array|nil
---@return table[]
local function ordered(arr)
    if (nil == arr or arr:count() < 1) then
        return {}
    end
    local list = arr:values()
    table.sort(list, function(a, b)
        if (a.priority ~= b.priority) then
            return a.priority < b.priority
        end
        return a.seq < b.seq
    end)
    return list
end

---@private 递增注册序号
---@param f Flow
---@return number
local function nextSeq(f)
    f._seq = (f._seq or 0) + 1
    return f._seq
end

--- 注册流片段
--- 同一 key 重复注册会覆盖原片段(位置/优先级以新值为准)
---@param key string 唯一key
---@param func fun(data:table):void
---@param priority number|nil 执行优先级, 越小越先执行(默认0), 同优先级按注册顺序
---@return void
function _index:flux(key, func, priority)
    sync.must()
    must(type(key) == "string", "key@string")
    if (type(func) ~= "function") then
        return
    end
    if (nil == self._actions) then
        self._actions = Array()
    end
    self._actions:set(key, { key = key, func = func, priority = tonumber(priority) or 0, seq = nextSeq(self) })
    self._ordered = nil
end

--- 注册后置片段
--- 在全部 flux 执行完且未触发中止(abort)后执行, 适合吸血/挂debuff等不影响数值的结算后逻辑
---@param key string 唯一key
---@param func fun(data:table):void
---@param priority number|nil 执行优先级, 越小越先执行(默认0)
---@return void
function _index:after(key, func, priority)
    sync.must()
    must(type(key) == "string", "key@string")
    if (type(func) ~= "function") then
        return
    end
    if (nil == self._afters) then
        self._afters = Array()
    end
    self._afters:set(key, { key = key, func = func, priority = tonumber(priority) or 0, seq = nextSeq(self) })
    self._orderedAfter = nil
end

---@private 执行片段列表(单个片段出错只打印, 不中断流程)
---@param self Flow
---@param list table[]
---@param data table
---@param tag string
---@return void
local function exec(self, list, data, tag)
    for _, item in ipairs(list) do
        promise(item.func, function()
            print("Flow:" .. self._key .. ":" .. item.key .. tag .. " run error")
        end, nil, data)
    end
end

--- 伤害过程执行
---@param data table 数据
---@return void
function _index:run(data)
    sync.must()
    local actions = self._actions
    local afters = self._afters
    local hasAction = (nil ~= actions and actions:count() > 0)
    local hasAfter = (nil ~= afters and afters:count() > 0)
    if (false == hasAction and false == hasAfter) then
        return
    end
    data = data or {}
    local abort = self._abort
    local stopped = false
    if (hasAction) then
        if (nil == self._ordered) then
            self._ordered = ordered(actions)
        end
        --- 每个 flux 执行后检查一次中止条件; 中止则不再执行后续 flux 与 after
        for _, item in ipairs(self._ordered) do
            promise(item.func, function()
                print("Flow:" .. self._key .. ":" .. item.key .. " run error")
            end, nil, data)
            if (type(abort) == "function" and abort(data)) then
                stopped = true
                break
            end
        end
    end
    if (false == stopped and hasAfter) then
        if (nil == self._orderedAfter) then
            self._orderedAfter = ordered(afters)
        end
        exec(self, self._orderedAfter, data, ":after")
    end
end

--- 构造流执行对象
---@param key string 唯一key
---@return Flow
function Flow(key)
    sync.must()
    must(type(key) == "string", "key@string")
    local cache = class.cache(FlowClass)
    if (nil == cache[key]) then
        cache[key] = oMeta({ _key = key, _actions = Array(), _afters = Array() }, _index)
    end
    return cache[key]
end

--- Flow是否已实例
---@param key string
---@return boolean
function isFlow(key)
    if (type(key) ~= "string") then
        return false
    end
    return nil ~= class._cache[FlowClass] and nil ~= class._cache[FlowClass][key]
end
