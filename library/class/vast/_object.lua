--- 索引链深度保护(C 栈溢出防护)
--- oVast 的多索引 __index 是纯 Lua 闭包, 一旦索引链里存在环状元表关系,
--- 递归会一路走 C 层 __index, 抛出的 "C stack overflow" 连 pcall 都拦不住,
--- 还会连带打断上层流程(表现为伤害/UI 丢帧 + 刷日志)。
--- 这里在深度超限时中断递归并打印一次诊断, 便于定位成环对象。
--- 计数依赖 japi._asyncInc(每帧自增)自动复位, 因此即使某次查询抛错导致计数未回退,
--- 也只会影响当前这一帧, 不会像固定标志位那样永久卡死。
local INDEX_DEPTH_FRAME = -1
local INDEX_DEPTH = 0
local INDEX_DEPTH_MAX = 64
local INDEX_WARNED = false

--- 构造Vast型Object
---@param params table
---@vararg table
---@return Object|Vast
function oVast(params, ...)
    sync.must()
    local indexes = { ... }
    must(#indexes > 0, "{...} index metatable missing")
    local o = params
    if (#indexes == 1) then
        setmetatable(o, { __index = indexes[1], __reality = true })
    else
        setmetatable(o, {
            __reality = true,
            __indexes = indexes,
            __index = function(self, key)
                local frame = japi._asyncInc
                if (frame ~= INDEX_DEPTH_FRAME) then
                    INDEX_DEPTH_FRAME = frame
                    INDEX_DEPTH = 0
                end
                if (INDEX_DEPTH >= INDEX_DEPTH_MAX) then
                    if (false == INDEX_WARNED) then
                        INDEX_WARNED = true
                        local tpl = rawget(self, "_tpl")
                        print(string.format(
                            "[索引链保护] __index 深度超限(疑似元表链成环) key=%s obj=%s key字段=%s tpl=%s",
                            tostring(key), tostring(self), tostring(rawget(self, "_key")), tostring(tpl)))
                    end
                    return nil
                end
                INDEX_DEPTH = INDEX_DEPTH + 1
                local v = nil
                for _, es in ipairs(indexes) do
                    v = es[key]
                    if (nil ~= v) then
                        break
                    end
                end
                INDEX_DEPTH = INDEX_DEPTH - 1
                return v
            end
        })
    end
    --- ID
    class.id(o, true)
    --- construct
    do
        local construct = nil
        construct = function(c)
            local super = getmetatable(c)
            if type(super) == "table" then
                if super.__indexes then
                    for i = #super.__indexes, 1, -1 do
                        construct(super.__indexes[i])
                    end
                elseif super.__index then
                    construct(super.__index)
                end
            end
            if rawget(c, "construct") then
                c.construct(o)
                event.syncTrigger(c._className, eventKind.classConstruct, { triggerObject = o })
            end
        end
        construct(o)
    end
    --- debug
    class.debug(o)
    return o
end