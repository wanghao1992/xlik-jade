# 图鉴 UI 套件创建方案

## 一、目标与范围

在 demo 项目内新建一套「图鉴」系统，包含一个 UIKit 套件与配套数据/逻辑：

1. **卡片图鉴页签**：展示全部卡片；同一张卡片有多张时叠加显示数量（`×N`），不重复占格；未拥有（数量 0）的卡片叠蒙版。
2. **羁绊图鉴页签**：展示全部羁绊；每条羁绊显示配方卡片（图标 + 名称 + 需要数量）与效果文案；已激活的「点亮」；未激活但配方卡片充足时显示「激活」按钮，点击即激活羁绊并施加效果。

**同时新建卡牌系统**（因为项目里没有任何卡牌/持有数据）：卡片数据表 + 持有数量存档 + 调试发卡命令。

**范围边界（按用户确认）**：
- 羁绊效果**只做可映射的属性类加成**（落 `saveFlow.applyAttr` 能识别的属性名）；无法映射的效果（生命窃取、闪避、对 BOSS/小怪增伤、召唤、皮肤、团队复活等）在图鉴里**照常展示并标注「（暂未实现）」**。
- 图标**先用占位**（框架常量 `X_UI_QUESTION`），`icon` 字段数据驱动，后续替换。
- 卡片获取**只做存档 + 调试发卡命令**，不接游戏内掉落来源。
- 图鉴入口 = **新增功能栏按钮**（`xlik_funcbar`）。

## 二、现状分析

| 项 | 位置 | 说明 |
|---|---|---|
| UIKit 套件范式 | [xlik_baoku/main.lua](file:///d:/Lua/xlik-jade/vendor/assets/war3mapUI/xlik_baoku/main.lua) | `UIKit(kit)` + `onSetup` 建面板；`UIBackdrop(FDF=LK_SLKC_MENU_PANEL)` 底 + `block(true)`；顶部按钮行当页签；`viewport` + `grid` 网格 + 滚动条；`UITooltips()` 悬停；`releaseFocus()` 关面板 |
| 套件注册 | [project.lua](file:///d:/Lua/xlik-jade/projects/demo/assets/project.lua#L7-L22) | `assets_ui("xlik_xxx")` 声明（自动加载 `vendor/assets/war3mapUI/<kit>/main.lua`） |
| 服务端→客户端下发布局 | [宝库流程.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/宝库流程.lua#L304-L400) | `pushPanel`：`build` → `async.call(player, ...)` → `ui:open/refresh`；`sync.receive('xlik_baoku_open', ...)` |
| 存档底层 | [存档.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/存档.lua) | `FIELD[组] = {type='num'/'bool', keys={...}, wk=n}`；`saveArchive.get/set/add/getBool/setBool`；数值 wk=2 单槽上限 8099、每 key 30 槽；布尔 1 key=360 位 |
| 属性落地 | [存档流程.lua applyAttr](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/存档流程.lua#L286-L475) | 老图中文属性名 → 引擎属性/`_attr`/`ampl`；数值为「分数」（0.10=10%），百分比键内部 `*100` |
| 建英雄上架 | [创建英雄.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建英雄.lua#L71-L82) | 依次调各系统 `applyToHero` |
| 调试命令 | [command.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/command.lua#L35-L46) | `LK_DEBUG` 下 `player.command("^-xxx$", fn)` |
| 功能栏入口 | [xlik_funcbar/main.lua](file:///d:/Lua/xlik-jade/vendor/assets/war3mapUI/xlik_funcbar/main.lua#L9-L197) | `btnNames` 当前 8 条（2 排 × 4）；`switch_function_xxx` 发 `sync.send("xlik_xxx_open", {player:index()})`；`toggleBtns` 折叠时按钮 8 移首位 |
| 占位图标/蒙版/边框 | [image_wardrobe.lua](file:///d:/Lua/xlik-jade/projects/demo/assets/image_wardrobe.lua#L12-L58)、`X_UI_QUESTION` | `X_UI_QUESTION`（全局常量）、`存档禁用蒙版.tga`、`通用边框.tga` **均已存在/已声明** → 本功能**不新增任何图片资源** |

**结论**：项目内无任何卡牌、羁绊、图鉴相关代码，全部为新增。

## 三、数据设计：新增 `projects/demo/scripts/globals/setup/图鉴.lua`

全局表 `codexData`，分卡片与羁绊两块。

```lua
--- 图鉴数据: 卡片 + 羁绊
codexData = codexData or {}

--- 占位图标(用户确认暂用占位; 后续替换只改本字段)
codexData.icon = X_UI_QUESTION   -- 注意: 本文件在 X_UI_QUESTION 定义之后加载, 直接引用
```

### 3.1 卡片表 `codexData.cards`

`{ id, name, icon }[]`，id 从 1 连续编号，槽位 = id。共 **42 张**（从羁绊配方去重得到）：

```
1 阿尔萨斯  2 泰瑞纳斯  3 乌瑟尔  4 光明使者  5 吉安娜  6 安东尼达斯  7 萨尔
8 格罗姆  9 凯恩  10 血蹄图腾  11 泰兰德  12 月刃  13 玛法里奥  14 塞纳留斯
15 克尔苏加德  16 瘟疫之匣  17 霜之哀伤  18 伊利丹  19 玛维  20 凯尔萨斯  21 瓦斯琪
22 灰烬使者  23 毁灭之锤  24 埃辛诺斯战刃  25 古尔丹之颅  26 统御之盔  27 艾露恩之弓
28 萨格拉斯之眼  29 阿克蒙德  30 基尔加丹  31 玛尔加尼斯  32 克苏恩  33 尤格萨隆
34 恩佐斯  35 山丘之王  36 穆拉丁  37 剑圣  38 恶魔猎手  39 希尔瓦娜斯
40 地精工兵  41 娜迦海妖  42 血法师
```

末尾生成索引：`codexData.cardIndex[name] = id`（供配方按名字转 id）。

### 3.2 羁绊表 `codexData.bonds`

`{ id, name, icon, cards, effect, attrs, unmapped }[]`，共 **35 条**，id 从 1 连续编号，槽位 = id。

- `cards`：`{ {id=卡id, need=需要数量}, ... }`（本版每条 `need=1`；结构支持后续改数量）。
- `effect`：原效果文案（一字不改，用于 tooltip 与列表展示）。
- `attrs`：`{ {属性名, 数值}, ... }`，属性名为 `saveFlow.applyAttr` 词汇；数值用**老图分数口径**（百分比写小数，点数写原值）。
- `unmapped`：`{ "效果描述", ... }`，无法映射的效果文案（列表中在效果后追加「（暂未实现）」）。

**配方（按原表，全部 need=1）**：以卡名写 `cards`（如 `{ '阿尔萨斯', '泰瑞纳斯' }`），加载时经 `cardIndex` 转 id。

**效果→属性映射表（35 条完整）**：

| id | 羁绊 | attrs（映射生效） | unmapped（占位） |
|---|---|---|---|
| 1 | 洛丹伦王权 | 基础护甲 5；附加伤害减免% 0.05；附加生命恢复% 0.003 | — |
| 2 | 白银之手 | 法术伤害 0.10 | 治疗效果+15%；对小怪增伤+10% |
| 3 | 达拉然守护 | 附加魔法恢复% 0.50 | 冷却缩减+8%；技能伤害+10% |
| 4 | 部落的崛起 | 攻击力增幅% 0.10 | 生命窃取+3%；杀敌生命+1(上限30) |
| 5 | 牛头人的坚韧 | 生命上限增幅% 0.15；附加伤害减免% 0.08 | 抗眩晕+20% |
| 6 | 暗夜哨兵 | — | 闪避+8%；移动速度+10%；攻击范围+10% |
| 7 | 塞纳留斯之赐 | 附加生命恢复% 0.003；法术伤害 0.10 | 对精英怪增伤+10% |
| 8 | 天灾军团 | 每秒金币 1 | 击杀召唤骷髅；生命窃取+5% |
| 9 | 圣光师徒 | 附加伤害减免% 0.10；基础生命回复 1 | 一次致死免疫 |
| 10 | 弑师者 | 攻击力增幅% 0.20；附加暴击伤害% 0.30 | 对挑战怪增伤+15% |
| 11 | 青梅竹马 | 附加魔法恢复% 0.20；生命上限增幅% 0.15；基础生命回复 1 | — |
| 12 | 宿命对决 | 攻击力增幅% 0.15；基础攻击速度% 0.10 | 受伤加成+15% |
| 13 | 兄弟阋墙 | 附加魔法恢复% 0.01；攻击力增幅% 0.15 | 闪避+8% |
| 14 | 暗夜双刃 | 攻击力增幅% 0.20 | 治疗效果+15%；暴击几率+10% |
| 15 | 血精灵的背叛 | 法术伤害 0.15；基础攻击速度% 0.15 | 冷却缩减+8% |
| 16 | 巫妖王的低语 | 附加生命恢复% 0.005 | 召唤骷髅+1；生命窃取+3% |
| 17 | 霜之哀伤 | 攻击力增幅% 0.15 | 死亡骑士皮肤；攻击附带暗影伤害；生命窃取+20%；杀敌攻击+1(上限80) |
| 18 | 灰烬使者 | 附加伤害减免% 0.08 | 攻击附加神圣伤害；对BOSS增伤+15% |
| 19 | 毁灭之锤 | 攻击力增幅% 0.08 | 被动(地震)；溅射伤害+15% |
| 20 | 埃辛诺斯战刃 | 基础攻击速度% 0.20 | 溅射伤害+20%；溅射范围+15% |
| 21 | 古尔丹之颅 | 法术伤害 0.20 | 恶魔皮肤；生命窃取+15%；每秒-1%生命 |
| 22 | 统御之盔 | 全属性增幅% 0.15；每秒金币 2 | 被动(召唤亡灵) |
| 23 | 艾露恩之弓 | — | 攻击弹射一次；攻击范围+20%；月神之光范围+20% |
| 24 | 萨格拉斯之眼 | 法术伤害 0.15 | 被动(毁灭射线)；每秒失去1%法力 |
| 25 | 巫妖王 | 全属性增幅% 0.30；每秒金币 3 | 巫妖王皮肤；敌人每秒受冰霜伤害 |
| 26 | 恶魔猎手 | 攻击力增幅% 0.25；基础攻击速度% 0.20 | 恶魔猎手皮肤；生命窃取+20%；免疫恐惧 |
| 27 | 部落大酋长 | 攻击力增幅% 0.25；基础攻击速度% 0.20 | 狂暴；免疫恐惧12秒 |
| 28 | 联盟统帅 | 护甲增幅% 0.20；附加伤害减免% 0.15 | 一次团队复活 |
| 29 | 燃烧军团降临 | — | 召唤地狱火；全场敌人每秒-1.5%生命；对变异怪增伤+20% |
| 30 | 上古之神 | 法术伤害 0.20 | 全场敌人每秒-1%生命；随机精神控制 |
| 31 | 艾泽拉斯的救赎 | 全属性增幅% 0.15；每秒金币 2 | 一次团队复活；一次致死免疫 |
| 32 | 坚守阵地 | 护甲增幅% 0.10；附加伤害减免% 0.08；附加生命恢复% 0.005 | — |
| 33 | 清怪专家 | 基础攻击速度% 0.15 | 溅射伤害+15%；暴击几率+8% |
| 34 | 经济引擎 | 每秒金币 3；金币加成% 0.15；经验加成% 0.10 | — |
| 35 | 越战越勇 | — | 杀敌攻击+1；杀敌生命+1；杀敌全属性+0.3 |

> 说明：「移动速度+10%」「攻击范围+10%/20%」在 `applyAttr` 里对应的是**点数**分支（非百分比），为避免语义错误，归入 unmapped 占位。

## 四、存档设计：改 `projects/demo/scripts/globals/setup/存档.lua`

在 `FIELD['衣柜']` 之后追加两组：

```lua
--- 图鉴-卡片持有数量(新增): 槽位 = 卡片 id 1..42; wk=2 -> 每 key 30 槽, 2 key 共 60 槽
FIELD['图鉴卡牌'] = { type = 'num', keys = { 'tk1', 'tk2' }, wk = 2 }

--- 图鉴-羁绊激活状态(新增): 槽位 = 羁绊 id 1..35; 1 key = 360 位
FIELD['图鉴羁绊'] = { type = 'bool', keys = { 'tj1' } }
```

- 卡片数量读：`saveArchive.get(handle, '图鉴卡牌', cardId)`；写：`saveArchive.set(...)`。
- 羁绊激活读：`saveArchive.getBool(handle, '图鉴羁绊', bondId)`；写：`saveArchive.setBool(...)`。

## 五、业务逻辑：新增 `projects/demo/scripts/process/图鉴流程.lua`（全局 `codexFlow`）

参照 `宝库流程.lua` 的结构（常量 → 工具 → 读写 → 面板 → 客户端请求）。

### 5.1 对外 API

| API | 说明 |
|---|---|
| `codexFlow.cardCount(player, cardId)` | 该卡持有数量 |
| `codexFlow.activated(player, bondId)` | 羁绊是否已激活（`getBool`） |
| `codexFlow.activable(player, bondId)` | 配方卡片是否全部满足（`count >= need`） |
| `codexFlow.activate(player, bondId)` | 校验 → **扣卡**（各卡 `count -= need`）→ `setBool(激活)` → 对当前英雄施加 attrs → 重推面板；返回 `ok, msg` |
| `codexFlow.applyToHero(player, hero)` | 建英雄时：遍历已激活羁绊，逐条 `saveFlow.applyAttr(player, hero, name, value)` |
| `codexFlow.grantAll(player, times)` | 调试：全部卡片 `+= times` |
| `codexFlow.grant(player, cardId, times)` | 调试：指定卡片 `+= times` |
| `codexFlow.build(player)` | 组装面板数据（见 5.3） |
| `codexFlow.open(player)` | `async.call` → `UIKit('xlik_codex'):open(data)` 或已开则 `refresh` |

**激活语义（决策）**：激活 = **消耗**配方卡片（各卡 `need` 份），并在存档记永久激活位。激活后效果对该玩家英雄长期生效（每次建英雄 `applyToHero` 重新施加）。重复点击已激活羁绊无效。

### 5.2 面板数据 `codexFlow.build(player)`

```lua
{
  tabIndex = 1,                     -- 默认卡片页签
  tabs = { '卡片图鉴', '羁绊图鉴' },
  cards = {                         -- 全部 42 张
    { id, name, icon, count, owned = count>0 },
    ...
  },
  bonds = {                         -- 全部 35 条
    {
      id, name, icon,
      recipe = { {cardId, name, icon, need, have, ok = have>=need}, ... },
      effect = '原效果文案',
      unmapped = { '...', ... },
      activated = bool, activable = bool,
    },
    ...
  },
  cardOwned = n, cardTotal = 42, bondActivated = m, bondTotal = 35,
}
```

两页签数据一次性下发，客户端切页签纯本地，不重复请求。

### 5.3 同步协议

```lua
sync.receive('xlik_codex_open', function(syncData)      -- 打开/刷新
    codexFlow.open(Player(syncData.transferData[1]))
end)
sync.receive('xlik_codex_activate', function(syncData)  -- 激活羁绊
    local p = Player(syncData.transferData[1])
    local ok, msg = codexFlow.activate(p, syncData.transferData[2])
    async.call(p, function()
        alerter.message(p, ok and ('|cff6dff1e[图鉴]|r 已激活羁绊: ' .. msg) or ('|cffff2121[图鉴]|r ' .. msg))
    end)
end)
```

## 六、UI 套件：新增 `vendor/assets/war3mapUI/xlik_codex/main.lua`

`local kit = "xlik_codex"`，`---@class UI_XLIK_CODEX:UIKit`，写法与几何口径照 `xlik_baoku`（`PX_W=1/2400`、`PX_H=1/1800`、FDF 面板底、`releaseFocus`）。

```
layer (UIBackdrop, FDF=LK_SLKC_MENU_PANEL, block, 居中偏上, ~0.62 × ~0.40)
├─ title          "图鉴"(金色, fontSize 12, 居中)
├─ tabRow         2 个页签按钮(卡片图鉴 / 羁绊图鉴; 选中=底亮+金字)
├─ [卡片页] cardView (viewport + grid)
│    10 列 × 可视 4 行; 42 张 -> 5 行, 滚动条
│    每格(0.024 宽 ICON): 图标(占位 X_UI_QUESTION) + 边框(通用边框.tga)
│        · count==0: 叠蒙版(存档禁用蒙版.tga)
│        · count>0 : 右下角计数 "×N"
│        · 图标下方: 卡片名(fontSize 7)
│        · 悬停: UITooltips 显示名称 + "持有 ×N"
├─ [羁绊页] bondView (viewport + 单列 list + 滚动条)
│    可见 6 行/页, 35 条 -> 滚动
│    每行 BOND_ROW_H(~0.052):
│      · 左 recipeBox(定宽 ~0.13): 最多 4 个配方图标(0.017)横排,
│           每图标右下角 "×have/need"(ok=绿/不足=红); 下方一行卡名 "A+B+C"
│      · 中 infoBox: 羁绊名(gold, fontSize 9) + 效果文案(fontSize 8, 最多 2 行)
│      · 右 statusBox(~0.055):
│           已激活  -> 文本「已激活」(金色, 高亮)          -- 点亮
│           可激活  -> 按钮「激活」(LK_SLKC_BUTTON_PANEL 底)
│           均不满足-> 文本「未激活」(灰)
│      · 悬停: UITooltips 显示 完整效果 + unmapped(标「（暂未实现）」) + 配方(需/持有)
├─ status         底部左: "卡片 x/42 · 羁绊已激活 m/35"
├─ closeBtn       右上角「关闭」
```

**套件 API**：`ui:open(data)` / `ui:refresh(data)` / `ui:close()` / `ui:isOpen()` / `ui:selectTab(i)`（本地切换 + 重渲染 + 重置滚动）/ `ui:showNextPage()`/`showPrePage()` 或滚轮 `onWheel` / `ui:enterCard(i)`、`ui:enterBond(i)`（悬停 tips）/ `ui:clickActivate(bondId)` → `sync.send('xlik_codex_activate', { PlayerLocal():index(), bondId })`。关闭时 `releaseFocus()`。

**资源引用**（不新增文件）：图标 `:texture(X_UI_QUESTION)`；蒙版 `存档禁用蒙版.tga`；边框 `通用边框.tga`。

## 七、装配改动

| 文件 | 改动 |
|---|---|
| [project.lua](file:///d:/Lua/xlik-jade/projects/demo/assets/project.lua) | 增 `assets_ui("xlik_codex")` |
| [存档.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/存档.lua) | 增 `FIELD['图鉴卡牌']`、`FIELD['图鉴羁绊']` |
| [创建英雄.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建英雄.lua#L71-L82) | `baoFlow.applyToHero` 之后追加 `codexFlow.applyToHero(player, hero)` |
| [command.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/command.lua) | `LK_DEBUG` 下增调试命令 `-card [数量]`：默认全部卡片 ×1，`-card N` = 全部卡片 ×N（测试叠加与激活） |
| [xlik_funcbar/main.lua](file:///d:/Lua/xlik-jade/vendor/assets/war3mapUI/xlik_funcbar/main.lua) | 见 7.1 |

### 7.1 功能栏新增「图鉴」按钮

现为 8 个槽位（2 排 × 4）。改造为 **9 个按钮、2 排 × 5 + 1 排 4**（即上排 5 个、下排 4 个）：

- `btnNames` 改为 9 条，顺序：`存档 / 泡温泉 / 签到 / 通行证 / 洗练配置`（上排） + `衣柜 / 宝库 / 图鉴 / 隐藏`（下排）。
  - 即「图鉴」= 索引 8，「隐藏」= 索引 9。
  - 「图鉴」热键用 `keyboard.code["F6"]`，回调 `switch_function_codex`（同构宝库：已开则本地关闭，否则 `sync.send("xlik_codex_open", { player:index() })`）。
- 建按钮循环 `for i = 1, 9`；排布阈值改为 `i <= 5`（上排），下排 `i == 6` 锚定 `heroIcon` 右下 + 行间距、其余锚定 `btnBeds[i-1]`。
- `toggleBtns`：折叠/展开的切换按钮由原索引 8 改为 **索引 9**；折叠时隐藏 1..8、把按钮 9 移到首位（`heroIcon` 右侧），文案「展开/隐藏」。

## 八、决策与假设

| 项 | 决定 |
|---|---|
| 卡牌存储 | 新增存档数值组 `图鉴卡牌`（wk=2、2 key），槽位=卡片 id |
| 羁绊激活 | 新增存档布尔组 `图鉴羁绊`（1 key），槽位=羁绊 id；**激活永久、跨局生效** |
| 激活消耗 | **消耗**配方卡片（各卡 `need` 份，本版全部 need=1）；重复激活无效 |
| 效果范围 | 仅落 `saveFlow.applyAttr` 支持的属性；其余进 `unmapped`，UI 标注「（暂未实现）」 |
| 图标 | 全部占位 `X_UI_QUESTION`，数据驱动可替换；不新增图片资源 |
| 卡片获取 | 仅 `-card` 调试命令（`LK_DEBUG`）；不接游戏内来源 |
| 页签数据 | `build` 一次性下发两页签数据；切页签纯本地 |
| 面板尺寸/几何 | 复用 `xlik_baoku` 的 `PX_W/PX_H` 与网格/滚动条口径 |
| 入口 | 功能栏新增按钮（上排 5 + 下排 4），热键 F6 |

## 九、验证步骤

1. **语法**：对全部新增/改动 `.lua` 跑 `loadfile`（本机 Lua 5.1）。
2. **构建**：`xlik.exe run demo -l!` 通过（无新增资源，应无 `【图片】... 不存在` 报错）。
3. **实机**（`xlik.exe run demo -l`）：
   - 功能栏出现「图鉴」按钮（F6 亦可）→ 面板打开，两个页签可切换。
   - `-card 3` → 卡片页：42 张全部可见，拥有显示 `×3`、未拥有叠蒙版；羁绊页：全部羁绊「可激活」按钮出现。
   - 点某羁绊「激活」→ 提示成功；该行变「已激活」高亮；对应卡片数量按需扣减；卡片页数量同步刷新。
   - 羁绊页 tooltip 显示完整效果 + 「（暂未实现）」项 + 配方持有/需求。
   - 关闭再开、切页签，状态保持；不重复占格（同卡只一格）。
4. **效果**：激活「洛丹伦王权」后重开一局（不 `clear`）建英雄 → `hero:defend()`/`_attr['伤害减免']`/`_attr['生命恢复%']` 加成生效。
5. **回归**：宝库/衣柜/签到/通行证/功能栏其它按钮与布局正常。

## 十、影响面

- **新增代码**：`scripts/globals/setup/图鉴.lua`、`scripts/process/图鉴流程.lua`、`vendor/assets/war3mapUI/xlik_codex/main.lua`
- **改动**：`scripts/globals/setup/存档.lua`（+2 组）、`scripts/globals/setup/command.lua`（+1 命令）、`scripts/process/创建英雄.lua`（+1 调用）、`assets/project.lua`（+1 行）、`vendor/assets/war3mapUI/xlik_funcbar/main.lua`（+1 按钮 + 布局）
- **新增资源**：无
- **回滚**：删除三处新增文件，还原上述 5 处改动；平台侧数据用 `xlik.exe clear` 清理。
