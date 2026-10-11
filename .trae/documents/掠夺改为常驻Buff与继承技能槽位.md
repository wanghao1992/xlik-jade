# 掠夺改为常驻 Buff + 槽位12 改放「继承技能」方案

## 一、需求概述

1. 把英雄常驻技能「掠夺」（`TPL_ABILITY.STEAL`，当前占用技能栏槽位 12 / 快捷键 G）改为**常驻 Buff**，不再占用技能栏。
2. 空出来的**槽位 12** 用来放英雄进化（转职）时保留（继承）的旧职业技能。
3. 转职后英雄共拥有 4 个职业技能：**新职业自身 3 个（槽位 1/2/3，热键 Q/W/E）+ 1 个继承技能（槽位 12，热键 G）**。
4. 已与用户确认：
   - 进化时「可保留技能」候选**包含上一次继承来的技能**（共 4 选 1，可一代代续接继承链）。
   - 地图等级 1（掠夺加成 0）时，掠夺 Buff **仍常驻显示**。

## 二、现状分析

### 掠夺现状
- 定义在 [掠夺.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/ability/掠夺.lua)：`TPL_ABILITY.STEAL`，被动技能，占槽位 12（G）。
- 效果来源：`abilityGet` 事件中按 `saveFlow.mapLevel(player)-1` 施加攻击力/攻速/`攻击金币`/`杀敌金币`；`unitAttack` 事件中按 `攻击金币` 发金。
- 引用处仅两处： [英雄.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/英雄.lua#L15) 与 [职业.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/职业.lua#L27) 的 `preAbility` / `sharedAbility` 中 `[12] = TPL_ABILITY.STEAL`。
- 注意：`杀敌金币` 还被存档加成使用（[存档流程.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/存档流程.lua#L442-L444) 用 `hero:set('杀敌金币', (hero:get('杀敌金币') or 0) + value)` 累加），因此掠夺写入 `杀敌金币` 必须**用累加方式**，不能覆盖。

### 转职/技能栏现状
- [转职.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/转职.lua#L247-L288) `applySkills`：先卸下所有 `TPL_ABILITY.JOB` 技能，再组装 `Q/W/E`（槽位 1/2/3）。当前规则是「保留旧技能时：新职业技能剔除同名项后取前 2 个填槽 1/2，保留技能占槽 3」→ 英雄总共仍是 3 个职业技能，保留技能会挤掉新职业的一个技能。
- [职业.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/职业.lua#L15) 与 转职.lua 中 `JOB_ABILITY_INDEX = {1,2,3}`，对应热键 Q/W/E。
- 技能栏热键映射（[keyboard.lua](file:///d:/Lua/xlik-jade/library/common/keyboard.lua#L248-L306) 上下行镜像）确认：槽位 1/2/3 = Q/W/E，槽位 12 = G。
- 进化面板 [main.lua(xlik_job)](file:///d:/Lua/xlik-jade/vendor/assets/war3mapUI/xlik_job/main.lua#L111-L119)：`self.keepCount = 3` 限制「技能继承」区最多展示 3 个候选；面板宽度足够容纳 4 个（keepW≈0.23 < 面板宽≈0.354）。
- `jobFlow.oldJobSkills`（[转职.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/转职.lua#L124-L147)）扫描全部槽位中的 `TPL_ABILITY.JOB` 技能作为「可保留」候选；改动后槽位 12 的继承技能也会被扫到 → 候选最多 4 个。

### Buff 机制
- [buff.lua](file:///d:/Lua/xlik-jade/library/class/meta/buff.lua#L148-L204)：不传 `duration` 即默认 `-1`（永久，无计时器）；`purpose` 生效、`rollback` 回滚；`_visible` 默认 true。
- Buff 栏 UI [xlik_buff/main.lua](file:///d:/Lua/xlik-jade/vendor/assets/war3mapUI/xlik_buff/main.lua#L149-L155) 只展示 `visible()==true` 的 Buff；永久 Buff 显示满透明度、无倒计时。
- 参考现有常驻/加成 Buff 写法：`job.attrBuff`（[职业工具.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/职业工具.lua#L417-L440)）、创建英雄时的「出生保护」Buff（[创建英雄.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建英雄.lua#L44-L64)）。

## 三、改动方案（逐文件）

### 1. `projects/demo/scripts/globals/tpl/ability/掠夺.lua`（改写为掠夺 Buff 模块）
删除 `TPL_ABILITY.STEAL`（AbilityTpl）定义，改为定义全局 `stealFlow` 模块：

- `stealFlow.apply(hero)`（同步，英雄创建时调用）：
  - 守卫：`class.isObject(hero, UnitClass)` 且 `PlayerClass` 所有者；`false == BuffHas(hero, "掠夺")`（幂等，避免重复施加上 Buff）。
  - `local lv = math.max(saveFlow.mapLevel(player), 1) - 1`，`atk = lv*9`，`aspd = lv*9`，`gold = lv*1.5`。
  - `Buff({ key = "掠夺", object = hero, signal = buffSignal.up, name = "掠夺", icon = [[ReplaceableTextures\PassiveButtons\PASBTNPillage.blp]], description = {...同原文案...}, purpose, rollback })`（**不传 duration → 永久常驻**，始终创建，包含 lv<=0）。
  - `purpose(o)`：`o:attack("+="..atk)`；`o:attackSpeed("+="..aspd)`；`o:set('攻击金币', (o:get('攻击金币') or 0) + gold)`；`o:set('杀敌金币', (o:get('杀敌金币') or 0) + gold)`（**累加**，避免覆盖存档加成）。atk/aspd/gold 为 0 时跳过对应写入。
  - `rollback(o)`：仅在 `false == class.isDestroy(o)` 时，对称 `-=` 回退攻击/攻速，`攻击金币`/`杀敌金币` 按 `-gold` 累减回退。
- 全局普攻发金钩子（文件顶层注册，等价于旧 `onUnitEvent`）：
  ```
  event.syncRegister(UnitClass, eventKind.unitAttack, "slkc_steal_gold", function(evtData) ... end)
  ```
  - 守卫：`triggerUnit` 是 Unit、未死亡、`BuffHas(hero, "掠夺")`、`攻击金币 > 0`。
  - 取 `hero:get('攻击金币')`，对 `hero:owner()` 执行 `player:worth("+", { gold = gold })`（保持旧行为：不吃金币加成%）。
- 保留头部注释说明「已由技能改为常驻被动 Buff，槽位 12 让位给继承技能」。

### 2. `projects/demo/scripts/globals/tpl/unit/英雄.lua`
- 从 `preAbility` 中删除 `[12] = TPL_ABILITY.STEAL`（[第15行](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/英雄.lua#L15)）。
- 更新槽位注释：槽位 12 预留给转职继承技能。

### 3. `projects/demo/scripts/globals/tpl/unit/职业.lua`
- 从 `sharedAbility()` 中删除 `[12] = TPL_ABILITY.STEAL`（[第27行](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/职业.lua#L27)）。
- 更新文件头槽位说明（[第5-9行](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/tpl/unit/职业.lua#L5-L9)）：`[12]` 改为「继承技能（由 转职.lua 挂载）」。

### 4. `projects/demo/scripts/process/创建英雄.lua`
- 在英雄创建后、`saveFlow.applyToHero`（[第72行](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/创建英雄.lua#L72)）之前调用 `stealFlow.apply(hero)`（建议放在 `extra:bind(hero)` 之后、「出生保护」Buff 附近）。
- 目的：保持掠夺效果在存档加成之前生效，且 `杀敌金币` 用累加写入，顺序无关也不会丢加成。

### 5. `projects/demo/scripts/process/转职.lua`
- 新增常量 `local INHERIT_ABILITY_INDEX = 12`（继承技能槽位）。
- 改写 `applySkills(hero, data, keepSkillName)`（[第247-288行](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/转职.lua#L247-L288)）：
  1. 保持「先卸下所有 `TPL_ABILITY.JOB` 技能（扫全部槽位，含槽位 12）」。
  2. `data.skills` 前 3 个 → 依次 `slot:insert(ab, 1/2/3)`（新职业 3 技能固定占 Q/W/E，不再被保留技能挤掉）。
  3. 若 `keepSkillName` 非空：若其出现在新职业 3 技能中（同名重复）则**跳过**（避免重复挂载）；否则 `slot:insert(jobAbility[keepSkillName], INHERIT_ABILITY_INDEX)` 放入槽位 12。
- 更新函数头注释（[第241行](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/转职.lua#L241)）说明新规则。
- `oldJobSkills` 无需改代码：槽位 12 的继承技能会被自然扫入候选（满足「4 选 1 续接」）。服务端 `xlik_job_confirm` 的候选校验逻辑不变，仍正确。

### 6. `vendor/assets/war3mapUI/xlik_job/main.lua`
- `self.keepCount = 3` → `self.keepCount = 4`（[第115行](file:///d:/Lua/xlik-jade/vendor/assets/war3mapUI/xlik_job/main.lua#L115)），使「技能继承」区可展示最多 4 个候选（含上一次继承的技能）。
- 布局自动适配：`keepW`、`keepNoneBtn` 均按 `keepCount` 计算，无需手工调几何。更新相关注释。

### 7. `projects/demo/scripts/process/存档流程.lua`（仅注释）
- 更新 [第760行](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/存档流程.lua#L760) 附近注释：`实际落地在 TPL_ABILITY.STEAL(掠夺) 的 abilityGet` → 改为「实际落地在 掠夺 常驻 Buff（tpl/ability/掠夺.lua 的 stealFlow.apply）」。展示文案（tips）保持不变。

## 四、假设与决策

- **掠夺 Buff 常驻**：不传 `duration`（= -1 永久），无计时器，不自动回滚；英雄死亡/复活不销毁（Buff 挂单位对象上）。
- **始终创建**：即使 `地图等级=1`（加成为 0）也创建并显示 Buff（用户已确认）。
- **保留效果口径不变**：攻击力 `lv*9`、攻速 `lv*9`（百分比点）、攻击金币/杀敌金币 `lv*1.5`；普攻发金不吃金币加成%，与旧实现一致。
- **累加写入**：`攻击金币`/`杀敌金币` 改用「读旧值 + 增量」方式，避免覆盖存档等其它系统的加成。
- **槽位固定**：新职业 3 技能恒占槽位 1/2/3（Q/W/E）；继承技能恒占槽位 12（G）。同名重复时继承槽留空（不重复挂载）。
- **保留文件位置**：仍放在 `tpl/ability/掠夺.lua`（减少改动面），仅将其内容由「技能 TPL」改为「Buff 模块 + 全局普攻钩子」；文件头注释说明用途变更。
- 不新建文件、不改动 Buff/技能栏等框架层。

## 五、验证步骤

1. 语法静态检查（不执行打包，遵循用户偏好）：对改动的 Lua 文件运行 `luac -p`（若环境无 luac 则用等价语法检查），确保无语法/拼写错误。
   - 关注文件：`掠夺.lua`、`英雄.lua`、`职业.lua`、`创建英雄.lua`、`转职.lua`、`存档流程.lua`。
2. 静态自检清单：
   - 全仓库确认无残留 `TPL_ABILITY.STEAL` 引用（`Grep "STEAL"`）。
   - `掠夺` Buff 在英雄创建时施加，键名唯一，`BuffHas` 幂等。
   - 转职后槽位 1/2/3 = 新职业 3 技能，槽位 12 = 继承技能（无同名重复）。
   - 再次进化时，「技能继承」区展示 4 个候选，选择后正确写入槽位 12。
3. 打包与游戏内实测由用户执行（本方案不运行 `xlik.exe run demo -l!`）。
