--- JAPI通用库，编写定义通用及框架自带的api控制函数
--[[
    Api接口基本将尽可能地按照新的实现为标准
    * JAPI一切方法都会根据环境而变（包括框架自带的），环境问题请自行解决
    * 如果你所拥有的环境不匹配方法，将提示方法不存在
    
    函数名头指japi方法函数名称大写开头的标识
     - 自带方法 无
     - ydapi  YD_
     - dzapi  DZ_
     - kkapi  KK_
     
    ！注意
    因为旧DZ、新DZ、最新的KK三个版本的接口新旧混合，功能重复相互混合，管理得极其混乱不堪，故框架作出下列调整：
     - 自实现api 请查看 japi/lk.lua
     - ydapi 请查看 japi/yd.lua（如果你查找的方法以YDWE、EX开头，大概率在这里）
     - dzapi 请查看 japi/dz.lua（如果你查找的方法以Dz、DzApi开头，大概率在这里）
     - kkapi 请查看 japi/kk.lua（如果你查找的方法以KKApi开头，大概率在这里）
    注释中带有[别名]的api则是改掉了名字，你可以使用原来的名字来搜索它
    注释中带有[不明]的api表示无迹可寻API，注释功能说明为猜测不可尽信
    注释中带有[PRE]的api表示平台预体验API，可能该功能无法用于平台正式环境
]]
---@class japi
japi = japi or {}

---@type table<string,number>
japi._tips = japi._tips or {}

---@protected
---@param msg string
---@return void
function japi.Tips(msg)
    if (japi._tips[msg] ~= 1) then
        japi._tips[msg] = 1
        local err = SYMBOL_JAPI .. msg
        if (LK_DEBUG) then
            print(err)
        else
            echo(err)
        end
    end
end

---@protected
---@param method string
---@vararg any
---@return any
function japi.Exec(method, ...)
    if (type(method) ~= "string") then
        return false
    end
    if (nil == J.Japi) then
        return false
    end
    local call = J.Japi[method]
    if (type(call) ~= "function") then
        japi.Tips(method .. "NotExist")
        return false
    end
    return call(...)
end

-- ---------------------------------------------------------------------------
-- 归一化层：平台无关的 UI 原生入口
--
-- class/ui 只依赖下面这些归一化名（= DZ 名去掉 Dz 前缀），具体走哪个 provider 由这里决定：
--   解析顺序见 japi._nativeOrder（靠前者优先）——发布到平台时保持 { "DZ", "WH" }，
--   以保证平台行为与改动前完全一致；只有平台缺席的能力才落到内置 JAPI。
-- 归一化名与内置 JAPI 的原生名一致（无前缀的 FrameSetSize / GetGameUI / ...）。
-- toc 的归一化名用 japi.FrameLoadToc —— 避开已被 lk.lua 占用的 japi.LoadToc。
-- ---------------------------------------------------------------------------

--- 原生实现解析顺序：靠前者优先
---@type table
japi._nativeOrder = japi._nativeOrder or { "DZ", "WH" }

---@protected
---@type table<string,string>
japi._nativeCache = japi._nativeCache or {}

--- 按候选名解析出「真实存在的 native 名」，结果缓存
---@protected
---@param uniq string 归一化名（仅作缓存 key）
---@param cands table 候选：{ { provider前缀, native名 }, ... }
---@return string
local function resolveNative(uniq, cands)
    local hit = japi._nativeCache[uniq]
    if (hit ~= nil) then
        return hit
    end
    for _, provider in ipairs(japi._nativeOrder) do
        for _, item in ipairs(cands) do
            if (item[1] == provider and nil ~= J.Japi and type(J.Japi[item[2]]) == "function") then
                japi._nativeCache[uniq] = item[2]
                return item[2]
            end
        end
    end
    -- 全部不可用：退回第一个候选名，交由 japi.Exec 打印一次 Tips
    japi._nativeCache[uniq] = cands[1][2]
    return cands[1][2]
end

--- 平台无关 - 取根控件
---@return number integer
function japi.GetGameUI()
    return japi.Exec(resolveNative("GetGameUI", { { "DZ", "DzGetGameUI" }, { "WH", "GetGameUI" } }))
end

--- 平台无关 - 按 fdf tag 建控件
---@param frameType string
---@param name string
---@param parent number integer
---@param template string
---@param id number integer
---@return number integer
function japi.CreateFrameByTagName(frameType, name, parent, template, id)
    local n = resolveNative("CreateFrameByTagName", { { "DZ", "DzCreateFrameByTagName" }, { "WH", "CreateFrameByTagName" } })
    return japi.Exec(n, frameType, name, parent, template, id)
end

--- 平台无关 - 销毁控件
---@param frame number integer
---@return void
function japi.DestroyFrame(frame)
    return japi.Exec(resolveNative("DestroyFrame", { { "DZ", "DzDestroyFrame" }, { "WH", "DestroyFrame" } }), frame)
end

--- 平台无关 - 清空控件锚点
---@param frame number integer
---@return void
function japi.FrameClearAllPoints(frame)
    return japi.Exec(resolveNative("FrameClearAllPoints", { { "DZ", "DzFrameClearAllPoints" }, { "WH", "FrameClearAllPoints" } }), frame)
end

--- 平台无关 - 设置控件锚点
---@param frame number integer
---@param point number integer
---@param relativeFrame number integer
---@param relativePoint number integer
---@param x number
---@param y number
---@return void
function japi.FrameSetPoint(frame, point, relativeFrame, relativePoint, x, y)
    local n = resolveNative("FrameSetPoint", { { "DZ", "DzFrameSetPoint" }, { "WH", "FrameSetPoint" } })
    return japi.Exec(n, frame, point, relativeFrame, relativePoint, x, y)
end

--- 平台无关 - 设置控件尺寸
---@param frame number integer
---@param w number
---@param h number
---@return void
function japi.FrameSetSize(frame, w, h)
    return japi.Exec(resolveNative("FrameSetSize", { { "DZ", "DzFrameSetSize" }, { "WH", "FrameSetSize" } }), frame, w, h)
end

--- 平台无关 - 显隐控件
---@param frame number integer
---@param enable boolean
---@return void
function japi.FrameShow(frame, enable)
    return japi.Exec(resolveNative("FrameShow", { { "DZ", "DzFrameShow" }, { "WH", "FrameShow" } }), frame, enable)
end

--- 平台无关 - 设置透明度
---@param frame number integer
---@param alpha number integer
---@return void
function japi.FrameSetAlpha(frame, alpha)
    return japi.Exec(resolveNative("FrameSetAlpha", { { "DZ", "DzFrameSetAlpha" }, { "WH", "FrameSetAlpha" } }), frame, alpha)
end

--- 平台无关 - 设置贴图
---@param frame number integer
---@param texture string
---@param flag number integer
---@return void
function japi.FrameSetTexture(frame, texture, flag)
    local n = resolveNative("FrameSetTexture", { { "DZ", "DzFrameSetTexture" }, { "WH", "FrameSetTexture" } })
    return japi.Exec(n, frame, texture, flag)
end

--- 平台无关 - 设置文本
---@param frame number integer
---@param text string
---@return void
function japi.FrameSetText(frame, text)
    return japi.Exec(resolveNative("FrameSetText", { { "DZ", "DzFrameSetText" }, { "WH", "FrameSetText" } }), frame, text)
end

--- 平台无关 - 设置文本颜色
---@param frame number integer
---@param color number integer
---@return void
function japi.FrameSetTextColor(frame, color)
    return japi.Exec(resolveNative("FrameSetTextColor", { { "DZ", "DzFrameSetTextColor" }, { "WH", "FrameSetTextColor" } }), frame, color)
end

--- 平台无关 - 设置字体（内置 JAPI 无 flag 参数，此处按解析结果丢参）
---@param frame number integer
---@param fileName string
---@param height number
---@param flag number integer
---@return void
function japi.FrameSetFont(frame, fileName, height, flag)
    local n = resolveNative("FrameSetFont", { { "DZ", "DzFrameSetFont" }, { "WH", "FrameSetTextFont" } })
    if (n == "FrameSetTextFont") then
        return japi.Exec(n, frame, fileName, height)
    end
    return japi.Exec(n, frame, fileName, height, flag)
end

--- 平台无关 - 设置文本对齐（内置 JAPI 无此能力 → 静默降级）
---@param frame number integer
---@param align number integer
---@return any
function japi.FrameSetTextAlignment(frame, align)
    local n = resolveNative("FrameSetTextAlignment", { { "DZ", "DzFrameSetTextAlignment" } })
    if (n == "DzFrameSetTextAlignment" and type(J.Japi[n]) == "function") then
        return japi.Exec(n, frame, align)
    end
    japi.Tips("FrameSetTextAlignmentUnsupported")
    return false
end

--- 平台无关 - 设置模型
---@param frame number integer
---@param modelFile string
---@param modelType number integer
---@param flag number integer
---@return void
function japi.FrameSetModel(frame, modelFile, modelType, flag)
    local n = resolveNative("FrameSetModel", { { "DZ", "DzFrameSetModel" }, { "WH", "FrameSetModel" } })
    return japi.Exec(n, frame, modelFile, modelType, flag)
end

--- 平台无关 - 播放模型动画
---@param frame number integer
---@param animId number integer
---@param autoCast boolean
---@return void
function japi.FrameSetAnimate(frame, animId, autoCast)
    local n = resolveNative("FrameSetAnimate", { { "DZ", "DzFrameSetAnimate" }, { "WH", "FrameSetAnimate" } })
    return japi.Exec(n, frame, animId, autoCast)
end

--- 平台无关 - 取鼠标焦点控件
---@return number integer
function japi.GetMouseFocus()
    return japi.Exec(resolveNative("GetMouseFocus", { { "DZ", "DzGetMouseFocus" }, { "WH", "GetMouseFocus" } }))
end

--- 平台无关 - 载入 toc/fdf
--- 归一化名有意避开 japi.LoadToc（后者在 lk.lua 里，带去重逻辑）
---@param fileName string
---@return void
function japi.FrameLoadToc(fileName)
    return japi.Exec(resolveNative("FrameLoadToc", { { "DZ", "DzLoadToc" }, { "WH", "LoadToc" } }), fileName)
end