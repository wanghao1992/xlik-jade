--- JAPI自wh库，内置 JAPI 插件（japi_replica / wenhao_plugin）方法，方法以 WH_ 开头
--- 该插件的 native 无平台前缀，直接透传给 japi.Exec
--- 与 dz.lua/yd.lua/kk.lua 同构；`class/ui` 走的是 _japi.lua 里的归一化入口，不直接调这里

--- 原生 - 游戏UI
--- 一般用作创建自定义UI的父节点
---@return number integer
function japi.WH_GetGameUI()
    return japi.Exec("GetGameUI")
end

--- 原生 - 按 fdf tag 建控件
--- frameType 是 fdf 基类型、template 是 fdf 条目名（需先 LoadToc）
---@param frameType string
---@param name string
---@param parent number integer
---@param template string
---@param id number integer
---@return number integer
function japi.WH_CreateFrameByTagName(frameType, name, parent, template, id)
    return japi.Exec("CreateFrameByTagName", frameType, name, parent, template, id)
end

--- 原生 - 销毁控件
---@param frame number integer
---@return void
function japi.WH_DestroyFrame(frame)
    return japi.Exec("DestroyFrame", frame)
end

--- 原生 - 清空控件锚点
---@param frame number integer
---@return void
function japi.WH_FrameClearAllPoints(frame)
    return japi.Exec("FrameClearAllPoints", frame)
end

--- 原生 - 设置控件锚点
--- 尺寸/偏移都是「屏幕比例」；point/relativePoint 为暴雪 UI_ALIGN_*（0~8）
---@param frame number integer
---@param point number integer
---@param relativeFrame number integer
---@param relativePoint number integer
---@param x number
---@param y number
---@return void
function japi.WH_FrameSetPoint(frame, point, relativeFrame, relativePoint, x, y)
    return japi.Exec("FrameSetPoint", frame, point, relativeFrame, relativePoint, x, y)
end

--- 原生 - 设置控件尺寸[0-0.8,0-0.6]（屏幕比例，不是像素）
---@param frame number integer
---@param w number
---@param h number
---@return void
function japi.WH_FrameSetSize(frame, w, h)
    return japi.Exec("FrameSetSize", frame, w, h)
end

--- 原生 - 显隐控件
---@param frame number integer
---@param enable boolean
---@return void
function japi.WH_FrameShow(frame, enable)
    return japi.Exec("FrameShow", frame, enable)
end

--- 原生 - 设置透明度[0-255]
---@param frame number integer
---@param alpha number integer
---@return void
function japi.WH_FrameSetAlpha(frame, alpha)
    return japi.Exec("FrameSetAlpha", frame, alpha)
end

--- 原生 - 设置贴图
---@param frame number integer
---@param texture string
---@param flag number integer
---@return void
function japi.WH_FrameSetTexture(frame, texture, flag)
    return japi.Exec("FrameSetTexture", frame, texture, flag)
end

--- 原生 - 设置文本
---@param frame number integer
---@param text string
---@return void
function japi.WH_FrameSetText(frame, text)
    return japi.Exec("FrameSetText", frame, text)
end

--- 原生 - 设置文本颜色
---@param frame number integer
---@param color number integer
---@return void
function japi.WH_FrameSetTextColor(frame, color)
    return japi.Exec("FrameSetTextColor", frame, color)
end

--- 原生 - 设置字体（内置 JAPI 无 flag 参数）
---@param frame number integer
---@param fileName string
---@param height number
---@return void
function japi.WH_FrameSetTextFont(frame, fileName, height)
    return japi.Exec("FrameSetTextFont", frame, fileName, height)
end

--- 原生 - 设置模型
---@param frame number integer
---@param modelFile string
---@param modelType number integer
---@param flag number integer
---@return void
function japi.WH_FrameSetModel(frame, modelFile, modelType, flag)
    return japi.Exec("FrameSetModel", frame, modelFile, modelType, flag)
end

--- 原生 - 播放模型动画
---@param frame number integer
---@param animId number integer
---@param autoCast boolean
---@return void
function japi.WH_FrameSetAnimate(frame, animId, autoCast)
    return japi.Exec("FrameSetAnimate", frame, animId, autoCast)
end

--- 原生 - 取鼠标焦点控件
---@return number integer
function japi.WH_GetMouseFocus()
    return japi.Exec("GetMouseFocus")
end

--- 原生 - 载入 toc/fdf（注册控件类型）
--- 注意：这里对应内置原生名 LoadToc；框架层的归一化入口叫 japi.FrameLoadToc（避开 japi.LoadToc）
---@param fileName string
---@return void
function japi.WH_LoadToc(fileName)
    return japi.Exec("LoadToc", fileName)
end
