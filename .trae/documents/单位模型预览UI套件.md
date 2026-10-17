# 单位模型预览 UI 套件（xlik_model）

## 目标

用 `UIModel`（SPRITE + 带 `Camera` 的 FDF 模板）在 UI 面板中显示单位模型：

- 左侧：3D 模型舞台 + 单位名称 + 模型路径 + 动作按钮（站立/攻击/施法/死亡）
- 右侧：单位列表（当前英雄 + 全部职业 + 召唤/形态），支持翻页、滚轮、点击切换
- 入口：聊天框 `-model [名称|序号]`（`LK_DEBUG`）

## 文件

| 文件 | 说明 |
|---|---|
| `vendor/assets/war3mapUI/xlik_model/main.lua` | 套件本体 |
| `vendor/assets/war3mapUI/xlik_model/main.fdf` | 4 组镜头模板（`Camera`，模型单位 + 度制 FOV） |
| `library/class/ui/model.lua` | `UIModel` 可选 FDF 模板参数 |
| `projects/demo/assets/project.lua` | `assets_ui("xlik_model")` |
| `projects/demo/scripts/globals/setup/command.lua` | `-model [名称|序号]` 调试命令 |

`main.fdf` 打包后生成 `UI\xlik_model.fdf` 并自动加入 `UI\xlik.toc`。

## 数据来源

客户端本地组装，不依赖服务端下发：

1. `PlayerLocal().hero`：`hero:model()`（含当前皮肤/变身）、`properName()` / `name()`；
2. `game.config.jobs`：职业名、模型路径、图标；
3. `game.config.job_units`：召唤物/形态单位。

## 使用

```text
-model            -- 默认当前英雄；没有英雄时显示列表第一个职业
-model 剑圣       -- 名称匹配（包含匹配，不区分大小写）
-model 3          -- 第 3 个条目
-model Footman    -- 模型路径匹配
```

面板内：

- 打开面板直接加载当前选中的模型（默认镜头 1/4 正面 3/4）；
- 点击右侧列表切换单位时直接加载；
- **左上角「镜头 x/5」按钮**或**左下角 `<` / `>`** 切换镜头；
- 动作按钮调用 `UIModel:animate(name, true)`。

## 镜头预设（main.fdf，已实机验证）

| # | 模板 | 位置 / 目标 | FOV | 说明 |
|---|---|---|---|---|
| 1 | `XLIK_MODEL_CAM1` | `320 -100 170` / `0 0 80` | 45° | 正面 3/4（默认） |
| 2 | `XLIK_MODEL_CAM2` | `340 0 150` / `0 0 80` | 45° | 正面 |
| 3 | `XLIK_MODEL_CAM4` | `0 -340 160` / `0 0 80` | 45° | 侧面 |
| 4 | `XLIK_MODEL_CAM5` | `-320 120 170` / `0 0 80` | 45° | 背面 |

实机 1.27 结果：

- 1/2/3/4（正面 3/4、正面、侧面、背面）显示完整；
- 远景、近景、特写均已按反馈移除；
- 6/7（屏幕尺度）和 8/9（弧度 FOV）的试验已移除；
- 引擎默认 `LK_MODEL` 模型尺寸过大（之前需要 `DzFrameSetScale(0.001)`），已从正常切换列表移除，只在所有镜头模板都创建失败时由 Lua 兜底。

> WC3 单位模型正面朝 **+X**，正面镜头放在 +X 侧；`CameraFieldOfView` 单位是**度**。

## 和「不思议生存」实现方式的区别

- 不思议生存走 `model2`：`FrameAddModel + FrameSetModel2 + FrameSetModelCameraSource/Target`
  （内置 JAPI），运行时镜头，天然正常；
- xlik 的 DZ/WH JAPI 没有这组 native，所以走 `SPRITE + FDF Camera`；
- 本套件不用 `DzFrameSetScale(0.001)` 修大小，大小由镜头距离/FOV 控制；
- 门禁已从只认 `DzFrameSetModel` 改为 `DzFrameSetModel` 或 `FrameSetModel`，WH 复刻也能加载模型。

## 验证步骤

1. `xlik.exe run demo -l!` 打包；
2. `xlik.exe run demo -l` 进图，聊天框输入 `-model`；
3. 切换镜头 1~4 检查角度/大小；
4. 若要更大/更小的构图，可在 `main.fdf` 里把 `CameraPosition` 相对 `CameraTarget` 缩放
   （例如整体乘 0.8 = 拉近，乘 1.3 = 拉远），重新打包。

## 注意

- 动作按钮依赖 `FrameSetAnimate`；WH 复刻未注册该 native 时动作不变，属预期；
- 测试时窗口保持启动大小，不要全屏/频繁改尺寸（WC3 1.27 容易卡死）；
- `-model` 在五笔输入法下需要按两次 Enter。
