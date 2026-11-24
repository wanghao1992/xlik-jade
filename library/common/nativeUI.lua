--- 原生 UI 调整公共方法
--- 说明:
---   - 1.27 下 DzFrameShow 对 FDF SimpleButton 不可靠，统一用“移出屏幕”实现隐藏
---   - 顶部左侧按钮索引: 0=任务, 1=菜单, 2=盟友, 3=聊天
---   - 项目可直接调用 nativeUI.hideUpperButtons() / nativeUI.hideUpperButton(2) 等方法
nativeUI = nativeUI or {}

--- 顶部按钮索引
nativeUI.UPPER_QUEST = 0
nativeUI.UPPER_MENU = 1
nativeUI.UPPER_ALLY = 2
nativeUI.UPPER_CHAT = 3

--- 隐藏状态: [index] = true
nativeUI._upperHidden = nativeUI._upperHidden or {}

--- 默认黑边高度（与 japi/lk.lua 的默认值一致）
nativeUI.DEFAULT_BLACK_BORDER_TOP = 0.020
nativeUI.DEFAULT_BLACK_BORDER_BOTTOM = 0.130

--- 顶部按钮布局参数（取自 UpperButtonBar.fdf）
nativeUI.UPPER_BUTTON_WIDTH = 0.085
nativeUI.UPPER_BUTTON_GAP = 0
nativeUI.UPPER_BAR_WIDTH = 0.34
nativeUI.UPPER_BAR_START = 0.002
--- 可见按钮组的右边界，默认贴原条右缘；想让整组再往屏幕中间靠可调大
nativeUI.UPPER_BAR_RIGHT = nil

--- 获取顶部按钮句柄
---@param index number 0~3
---@return number
function nativeUI.upperButton(index)
    if (type(japi.DZ_FrameGetUpperButtonBarButton) ~= "function") then
        return 0
    end
    return tonumber(japi.DZ_FrameGetUpperButtonBarButton(index)) or 0
end

--- 获取顶部按钮列表
---@return table<number,number> [index]=handle
function nativeUI.upperButtons()
    local list = {}
    for i = 0, 3 do
        local handle = nativeUI.upperButton(i)
        if (0 ~= handle) then
            list[i] = handle
        end
    end
    return list
end

--- 把 Frame 移到屏幕外
---@param handle number
---@return boolean
function nativeUI.moveOffScreen(handle)
    handle = tonumber(handle)
    if (nil == handle or 0 == handle) then
        return false
    end
    japi.DZ_FrameClearAllPoints(handle)
    japi.DZ_FrameSetAbsolutePoint(handle, UI_ALIGN_CENTER, -1, 0)
    return true
end

--- 应用顶部按钮布局
---   隐藏的移出屏幕；显示的按钮按原顺序整体向右补位（右侧贴原条右缘）
---@return number, number 处理成功数, 隐藏数
function nativeUI.applyUpper()
    local list = nativeUI.upperButtons()
    local parent = 0
    for i = 0, 3 do
        if (nil ~= list[i]) then
            parent = tonumber(japi.DZ_FrameGetParent(list[i])) or 0
            break
        end
    end

    local applied, hidden = 0, 0
    local visible = {}
    for i = 0, 3 do
        local handle = list[i]
        if (nil ~= handle) then
            applied = applied + 1
            if (true == nativeUI._upperHidden[i]) then
                japi.DZ_FrameClearAllPoints(handle)
                japi.DZ_FrameSetAbsolutePoint(handle, UI_ALIGN_CENTER, -1, 0)
                hidden = hidden + 1
            else
                visible[#visible + 1] = {
                    handle = handle,
                    width = tonumber(japi.DZ_FrameGetWidth(handle)) or nativeUI.UPPER_BUTTON_WIDTH,
                }
            end
        end
    end

    local count = #visible
    if (count > 0) then
        local gap = nativeUI.UPPER_BUTTON_GAP or 0
        local totalWidth = gap * (count - 1)
        for _, v in ipairs(visible) do
            totalWidth = totalWidth + (tonumber(v.width) or nativeUI.UPPER_BUTTON_WIDTH)
        end

        --- 右侧对齐：整组向右补位，右侧贴原条右缘，空位留在左侧
        local right = tonumber(nativeUI.UPPER_BAR_RIGHT)
        if (nil == right) then
            local barWidth = 0
            if (0 ~= parent) then
                barWidth = tonumber(japi.DZ_FrameGetWidth(parent)) or 0
            end
            if (barWidth <= 0) then
                barWidth = nativeUI.UPPER_BAR_WIDTH
            end
            right = (nativeUI.UPPER_BAR_START or 0) + barWidth
        end
        local x = right - totalWidth
        for _, v in ipairs(visible) do
            local width = tonumber(v.width) or nativeUI.UPPER_BUTTON_WIDTH
            japi.DZ_FrameClearAllPoints(v.handle)
            if (0 ~= parent) then
                japi.DZ_FrameSetPoint(v.handle, UI_ALIGN_LEFT_TOP, parent, UI_ALIGN_LEFT_TOP, x, 0)
            else
                japi.DZ_FrameSetAbsolutePoint(v.handle, UI_ALIGN_LEFT_TOP, x, 0)
            end
            x = x + width + gap
        end
    end
    return applied, hidden
end

--- 设置单个顶部按钮显隐
---@param index number 0~3
---@param visible boolean
---@return boolean
function nativeUI.setUpperVisible(index, visible)
    index = math.floor(tonumber(index) or -1)
    if (index < 0 or index > 3) then
        return false
    end
    nativeUI._upperHidden[index] = (false == visible) or nil
    nativeUI.applyUpper()
    return true
end

--- 隐藏单个顶部按钮
---@param index number 0~3
---@return boolean
function nativeUI.hideUpperButton(index)
    return nativeUI.setUpperVisible(index, false)
end

--- 显示单个顶部按钮
---@param index number 0~3
---@return boolean
function nativeUI.showUpperButton(index)
    return nativeUI.setUpperVisible(index, true)
end

--- 隐藏全部顶部按钮
---@return number 成功处理数量
function nativeUI.hideUpperButtons()
    for i = 0, 3 do
        nativeUI._upperHidden[i] = true
    end
    local applied = nativeUI.applyUpper()
    return applied
end

--- 显示全部顶部按钮
---@return number 成功处理数量
function nativeUI.showUpperButtons()
    for i = 0, 3 do
        nativeUI._upperHidden[i] = nil
    end
    local applied = nativeUI.applyUpper()
    return applied
end

--- 顶部按钮是否隐藏
---@param index number 0~3
---@return boolean
function nativeUI.isUpperHidden(index)
    return true == nativeUI._upperHidden[index]
end

--- 设置黑边
---@param top number
---@param bottom number
---@return void
function nativeUI.setBlackBorders(top, bottom)
    japi.SetBlackBorders(tonumber(top) or 0, tonumber(bottom) or 0)
end

--- 恢复默认黑边
---@return void
function nativeUI.restoreBlackBorders()
    nativeUI.setBlackBorders(nativeUI.DEFAULT_BLACK_BORDER_TOP, nativeUI.DEFAULT_BLACK_BORDER_BOTTOM)
end

--- 原生简单帧查找
---@param name string
---@param id number|nil
---@return number
function nativeUI.simpleFrame(name, id)
    if (type(japi.DZ_SimpleFrameFindByName) ~= "function") then
        return 0
    end
    return tonumber(japi.DZ_SimpleFrameFindByName(name, id or 0)) or 0
end
