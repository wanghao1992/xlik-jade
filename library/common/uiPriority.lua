--- UI 套件显示优先级管理(项目侧实现, 保证在 UI 套件加载前就绪)
--- 规则(数字越大越靠前/越优先):
---   xlik_job > xlik_ultimate > xlik_treasure > xlik_affix > xlik_learn > 其他
--- 职责:
---   1) 给每个套件的 UI 树设置原生帧优先级(DzFrameSetPriority);
---   2) 同一时间只保留一个"模态"套件: 高优先级打开时把低优先级排队并关闭,
---      低优先级打开时若高优先级在显示则排队; 高优先级关闭后自动打开队列里优先级最高的;
---   3) "其他"面板(<=150)被高优先级抢占时直接关闭, 不重新排队。
uiPriority = uiPriority or {}

--- 各套件优先级
uiPriority._priorities = uiPriority._priorities or {
    xlik_job = 500,
    xlik_ultimate = 400,
    xlik_treasure = 300,
    xlik_learn = 200,
    xlik_alerter = 9000,
}
--- 当前显示的模态套件 { kit, openFn, closeFn }
uiPriority._active = uiPriority._active or nil
--- 等待显示的套件队列 { kit, openFn }
uiPriority._queue = uiPriority._queue or {}
--- 取消计数: 用于让已排期的队列 openFn 失效
uiPriority._canceled = uiPriority._canceled or {}

--- 注册套件优先级
---@param kit string
---@param priority number
---@return void
function uiPriority.register(kit, priority)
    if (type(kit) == "string" and type(priority) == "number") then
        uiPriority._priorities[kit] = priority
    end
end

--- 取套件优先级(未注册 = 100, 即"其他")
---@param kit string
---@return number
function uiPriority.of(kit)
    return uiPriority._priorities[kit] or 100
end

--- 应用原生帧优先级(越大越靠前)
---@param layer UI|nil
---@param kit string
---@return void
function uiPriority.apply(layer, kit)
    if (nil == layer or nil == kit) then
        return
    end
    if (type(layer.handle) ~= "function") then
        return
    end
    if (japi and japi.DZ_FrameSetPriority) then
        pcall(japi.DZ_FrameSetPriority, layer:handle(), uiPriority.of(kit))
    end
end

--- 递归给整棵 UI 树设置优先级(原生优先级不一定继承给子控件)
---@param node UI|nil
---@param kit string
---@return void
function uiPriority.applyTree(node, kit)
    if (nil == node) then
        return
    end
    uiPriority.apply(node, kit)
    local children = node.children and node:children()
    if (type(children) == "table") then
        for _, child in pairs(children) do
            uiPriority.applyTree(child, kit)
        end
    end
end

--- 把套件放入等待队列(同 kit 去重, 保留最新 openFn)
---@param kit string
---@param openFn function|nil
---@return void
function uiPriority._enqueue(kit, openFn)
    for _, item in ipairs(uiPriority._queue) do
        if (item.kit == kit) then
            item.openFn = openFn
            return
        end
    end
    uiPriority._queue[#uiPriority._queue + 1] = { kit = kit, openFn = openFn }
end

--- 打开队列里优先级最高的套件(一次只开一个)
---@return void
function uiPriority._drain()
    if (nil ~= uiPriority._active) then
        return
    end
    local queue = uiPriority._queue
    if (#queue == 0) then
        return
    end
    local best = 1
    for i = 2, #queue do
        if (uiPriority.of(queue[i].kit) > uiPriority.of(queue[best].kit)) then
            best = i
        end
    end
    local item = table.remove(queue, best)
    if (type(item.openFn) ~= "function") then
        return
    end
    local kit = item.kit
    local token = uiPriority._canceled[kit] or 0
    if (kit == "xlik_job" or kit == "xlik_learn") then
        print(("[UI优先级] 排队打开 %s"):format(kit))
    end
    local function open()
        if ((uiPriority._canceled[kit] or 0) ~= token) then
            return
        end
        pcall(item.openFn)
    end
    --- 延迟约 0.1s: 让上一个面板的关闭逻辑(隐藏 layer / 恢复技能栏)先跑完
    if (sync and sync.is and sync.is()) then
        if (time and time.setTimeout) then
            time.setTimeout(0.1, open)
        else
            open()
        end
    elseif (async and async.setTimeout) then
        --- async.setTimeout 的单位是帧, 6 帧约 0.1s
        async.setTimeout(6, open)
    else
        open()
    end
end

--- 请求显示某个套件
---@param kit string
---@param openFn function|nil 被队列延后时用于重新打开
---@param closeFn function|nil 被更高优先级抢占时用于关闭
---@return boolean 是否允许立即显示
function uiPriority.request(kit, openFn, closeFn)
    local active = uiPriority._active
    if (kit == "xlik_job" or kit == "xlik_learn") then
        print(("[UI优先级] %s 请求, 当前=%s"):format(kit, tostring(active and active.kit)))
    end
    if (nil ~= active and active.kit == kit) then
        active.openFn = openFn
        active.closeFn = closeFn
        return true
    end
    if (nil ~= active) then
        if (uiPriority.of(active.kit) > uiPriority.of(kit)) then
            --- 更高优先级正在显示: 低优先级排队; "其他"面板直接不显示
            if (uiPriority.of(kit) > 150) then
                uiPriority._enqueue(kit, openFn)
            end
            return false
        end
        --- 当前套件优先级更低/相同: 让出位置
        if (uiPriority.of(active.kit) > 150) then
            uiPriority._enqueue(active.kit, active.openFn)
        end
        uiPriority._active = nil
        if (type(active.closeFn) == "function") then
            pcall(active.closeFn)
        end
    end
    uiPriority._active = { kit = kit, openFn = openFn, closeFn = closeFn }
    return true
end

--- 套件关闭: 若它是当前模态, 清空并尝试打开队列里的下一个
---@param kit string
---@return void
function uiPriority.release(kit)
    local active = uiPriority._active
    if (kit == "xlik_job" or kit == "xlik_learn") then
        print(("[UI优先级] %s 释放, 当前=%s"):format(kit, tostring(active and active.kit)))
    end
    if (nil ~= active and active.kit == kit) then
        uiPriority._active = nil
        uiPriority._drain()
    end
end

--- 取消队列中的某个套件(服务端已取消的面板不再弹出)
---@param kit string
---@return void
function uiPriority.cancel(kit)
    uiPriority._canceled[kit] = (uiPriority._canceled[kit] or 0) + 1
    for i = #uiPriority._queue, 1, -1 do
        if (uiPriority._queue[i].kit == kit) then
            table.remove(uiPriority._queue, i)
        end
    end
    local active = uiPriority._active
    if (nil ~= active and active.kit == kit) then
        uiPriority._active = nil
        uiPriority._drain()
    end
end

--- 当前显示的模态套件名
---@return string|nil
function uiPriority.current()
    return uiPriority._active and uiPriority._active.kit or nil
end

--- 注册优先级
uiPriority.register("xlik_job", 500)       -- 进化/转职面板(最高)
uiPriority.register("xlik_ultimate", 400)  -- 奥义五选一
uiPriority.register("xlik_treasure", 300)  -- 宝物选择
uiPriority.register("xlik_affix", 250)     -- 专属装备词条四选一
uiPriority.register("xlik_learn", 200)     -- 天赋三选一
uiPriority.register("xlik_alerter", 9000)  -- 飘字/提示

--- "其他"面板: 被高优先级抢占时直接关闭, 不重新排队
uiPriority.register("xlik_save", 120)
uiPriority.register("xlik_baoku", 120)
uiPriority.register("xlik_codex", 120)
uiPriority.register("xlik_cardsynth", 120)
uiPriority.register("xlik_txz", 120)
uiPriority.register("xlik_xilian", 120)
uiPriority.register("xlik_wardrobe", 120)
uiPriority.register("xlik_qiandao", 120)
uiPriority.register("xlik_gift", 120)
uiPriority.register("xlik_event", 120)
