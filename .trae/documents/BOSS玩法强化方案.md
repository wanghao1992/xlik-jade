# 主线 BOSS 玩法强化方案（防秒 + 技能特效 + 阶段机制）

## 一、目标概述（Summary）

针对「BOSS 可玩性低」的两个痛点，对主线 7 个 BOSS（`BOSS.lua` / `BOSS技能.lua`）做一次成体系的强化：

1. **不容易被秒**（数值 + 机制双管齐下）：

   * 数值：提高 BOSS 基础血量 / 护甲（可调倍率）。

   * 机制：新增「单次受伤上限」「周期性吸收护盾」「血量阈值转阶段（转阶段定格免伤）」三重保命层，避免被一波爆发带走。
2. **技能 + 特效 + 眼前一亮**（覆盖全部 7 个 BOSS、全部模式）：

   * 把原本只在「进阶 / 追击模式」才生效的主动技能**下放到所有模式**（含正常模式）。

   * 把「瞬间无感伤害」的技能改造成**先出预警圈（可躲）→ 延迟落地（带落地特效）**。

   * 每个 BOSS 新增 1 个**招牌技能**（大范围预警圈 + 落地特效 + 眩晕/持续伤害），在转阶段时释放。

   * 新增**周期性场地危险区**（点名落点预警），持续给玩家走位压力。

> 本次范围：仅主线 BOSS（`process/BOSS.lua` + `globals/setup/BOSS技能.lua`）。
> **不含**存档 BOSS / 爬塔 BOSS / 团本「魔君」（后者已有成熟的预警圈机制，见 [存档挑战.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/存档挑战.lua#L528-L719)）。

## 二、现状分析（Current State Analysis）

### 2.1 BOSS 生成与数值

[BOSS.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L209-L270) 的 `create_boss()`：

* 血量 `get_boss_hp()`＝`boss_base_hp_list[boss_index] × getMobHpMul()`（[BOSS.lua#L84-L106](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L84-L106)），基础表 `{60000, 300000, ...}`。

* 护甲 `get_boss_defend()`（[BOSS.lua#L108-L151](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L108-L151)）、攻击 `get_boss_attack()`。

* 保护手段**只有**出生 0.5 秒无敌（[L257-L264](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L257-L264)）。**没有任何减伤 / 护盾 / 受伤上限 / 阶段机制** → 玩家爆发可直接带走 → 「被秒」。

> 数值佐证：小怪 11 波血量已达 `3,000,000`（[刷怪.lua#L62-L64](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/刷怪.lua#L62-L64)），而第 1 个 BOSS 仅 `60000`；BOSS 血量表档位偏保守，且无防御机制。

### 2.2 技能装配（为什么「没啥技能」）

[BOSS技能.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/BOSS技能.lua) 已实现 20+ 个技能，但装配被模式门控（[L657-L670](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/BOSS技能.lua#L657-L670)）：

* `ALWAYS`：仅「XX-致命一击」（阿克蒙德额外有「混乱之雨」）→ **所有模式都有**。

* `ADVANCED`：火球术 / 变身 / 反击螺旋 / 召唤死尸 / 火焰雨 / 死亡一指 / 分身术 等 → **仅「进阶模式 / 追击模式」生效**。

结果：占绝大多数的「正常模式」下，BOSS 只有一击必杀被动，几乎没有主动技能。

### 2.3 特效现状（为什么「没特效」）

现有技能绝大多数走 `extraDamage()`（[L46-L58](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/BOSS技能.lua#L46-L58)）直接结算不可见伤害，**没有预警圈、没有落地特效、没有施法动作**。唯一有视觉的只有出生特效与追击模式的血祭附着（[BOSS.lua#L250-L252](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L250-L252)）。

### 2.4 可复用的「预警圈 / 落地」积木（已就绪，无需新增资源）

[职业工具.lua](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/职业工具.lua#L291-L374) 已封装好，团本「魔君」已在用：

* `job.telegraph({model, x, y, delay, radius|length|width, face, onLand})`：出预警圈 → `delay` 秒后回调落地。

* `job.lineSweep(sourceUnit, face, {model, distance, speed, halfWidth, damage, ...})`：直线冲击波。

* `job.aoeDamageStun(sourceUnit, x, y, {radius, damage, stun, ...})`：范围伤害 + 眩晕。

* `job.pointEffect(model, x, y, z, duration)` / `job.enemiesAround(...)` / `job.isExtraDamage(evt)`。

* 已注册的预警/落地模型（[model\_self.lua#L19-L31](file:///d:/Lua/xlik-jade/projects/demo/assets/model_self.lua#L19-L31)）：`提示圈-通用圆形.mdx`、`提示圈-直线箭头.mdx`、`提示圈-矩形.mdx`、`提示圈-扇形提示1.mdx`、`团队BOSS技能2.mdx`、`团队BOSS投射物2.mdx`。

### 2.5 伤害流程钩子（实现卡点）

[damage.lua#L96-L97](file:///d:/Lua/xlik-jade/library/ability/damage.lua#L96-L97)：`ability.damage` 在**结算前**触发 `eventKind.unitBeforeHurt`，其 `data.damage` 可被改小 → 这是实现「单次受伤上限 / 护盾吸收」的官方卡点（[BOSS技能.lua#L279-L286](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/BOSS技能.lua#L279-L286) 的闪避用法即此）。
[damaging.lua#L138-L169](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/damaging.lua#L138-L169)：`_attr["伤害减免"] / ["法术减免%"] / ["受伤加成%"]` 在 `talent` flux 生效 → 可用于阶段减伤（也可用 `superposition.plus(boss,"invulnerable")` 做完全免伤）。
保护单位可用 `superposition.plus(unit,"invulnerable")` + `superposition.plus(unit,"pause")`（定格，做法同 [存档挑战.lua#L582-L607](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/存档挑战.lua#L582-L607)）。

### 2.6 代码内已有的 TODO（确认此前已知缺口）

* [BOSS.lua#L330](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L330)：`todo 进阶模式和追击模式下给BOSS添加技能`

* [BOSS.lua#L331](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L331)：`todo 超进化时，BOSS减伤 0.95`

## 三、改造方案（Proposed Changes）

### 3.1 新增：`projects/demo/scripts/globals/setup/BOSS玩法.lua`（全局 `bossPlay`）

一个自包含的「保命 + 转阶段 + 场地危险区」系统文件。骨架：

```lua
--- BOSS 玩法强化(防秒 + 转阶段 + 场地危险区), 全局 bossPlay
--- 依赖: 框架 event/time/superposition/effector + 项目 job.*(职业工具.lua) + bossSkill.*(BOSS技能.lua)
bossPlay = bossPlay or {}

--- ===== 可调配置(集中在此, 便于实机调参) =====
local CFG = {
    --- 单次受伤上限(占生命上限比例; 0 = 关闭) —— 防止被一波爆发秒杀
    perHitCapPct   = 0.08,
    --- 周期吸收护盾: 吸收量 = 生命上限 × shieldPct, 每 shieldInterval 秒补一次
    shieldPct      = 0.15,
    shieldInterval = 25,
    shieldEffect   = [[Abilities\Spells\Human\DivineShield\DivineShieldTarget.mdl]],
    --- 转阶段: 血量阈值(降序, 比例) + 每段定格免伤时长(秒)
    phaseThresholds = { 0.70, 0.40, 0.15 },
    phaseInvul      = 1.5,
    --- 每转一次阶段叠加的狂暴(攻击增幅% / 攻速百分比点)
    phaseEnrageAtk   = 30,
    phaseEnrageSpeed = 20,
    --- 周期性场地危险区(点名落点预警); enable=false 可整体关闭
    hazard = { enable = true, interval = 18, radius = 320, delay = 1.3,
               dmgMul = 0.30, dmgPer = 0.15, stun = 0, landModel = '团队BOSS技能2.mdx' },
}
bossPlay.CFG = CFG
```

**包含的函数与职责：**

1. `bossPlay.attach(boss, bossName)`（对外唯一入口）

   * 依次调用 `attachDefense` / `attachPhases` / `attachHazard`；入口首行做 `class.isObject(boss, UnitClass)` 校验。

2. `attachDefense(boss)` —— 保命层

   * 注册一个 `eventKind.unitBeforeHurt` 回调（key `"bossPlay_guard"`），在同一次回调里按顺序处理：

     * **护盾吸收**：若 `boss._shieldAbsorb > 0`，先扣减 `data.damage`，用尽后 `bossPlay.removeShield(boss)`。

     * **单次受伤上限**：`data.damage = math.min(data.damage, (boss:hp() or 0) * CFG.perHitCapPct)`。

   * `time.setInterval(CFG.shieldInterval, ...)`：BOSS 存活且未满盾时调用 `bossPlay.grantShield(boss)`；BOSS 死亡/销毁时自杀该定时器（写法同 [BOSS技能.lua#L129-L141](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/BOSS技能.lua#L129-L141)）。

   * `grantShield(boss)`：`boss._shieldAbsorb = (boss:hp() or 0) * CFG.shieldPct`；`effector.attach(boss, CFG.shieldEffect, "origin")` 附上护盾外观；发 `alerter.message(PlayerLocal(), ...)` 播报「BOSS获得护盾」。

   * `removeShield(boss)`：`effector.detach(boss, CFG.shieldEffect, "origin")`（[effector.lua#L518-L538](file:///d:/Lua/xlik-jade/library/common/effector.lua#L518-L538)）并置零吸收量。

3. `attachPhases(boss, bossName)` —— 转阶段层

   * `time.setInterval(0.2, ...)` 轮询血量比例；`boss._inPhase` 期间跳过。

   * 跨过 `CFG.phaseThresholds[phaseIdx+1]` 时进入 `enterPhase`。

   * `enterPhase(boss, bossName, phaseIdx)`：

     * `superposition.plus(boss,"invulnerable")` + `superposition.plus(boss,"pause")`（定格免伤，防止转阶段被偷伤害）；

     * 视觉：`job.pointEffect('团队BOSS技能2.mdx', boss:x(), boss:y())` + `effector.point([[Abilities\Spells\Undead\AnimateDead\AnimateDeadTarget.mdl]], boss:x(), boss:y(), 0, 1)`，`boss:animate('spell')`；

     * 播报：`alerter.message(PlayerLocal(), '[BOSS]:xxx进入第N阶段!')` + `sound.vcm("war3_warning")`；

     * **释放招牌技能**：`bossSkill.castSignature(boss, bossName)`（落地时刻与免伤结束对齐）；

     * `time.setTimeout(CFG.phaseInvul, ...)` 后解除免伤/定格，并叠加狂暴：`boss:ampl('attack', +phaseEnrageAtk)`、`boss:attackSpeed('+= phaseEnrageSpeed')`。

   * BOSS 死亡/销毁时自杀轮询定时器。

4. `attachHazard(boss)` —— 场地危险区层（`CFG.hazard.enable == false` 时直接返回）

   * `time.setInterval(CFG.hazard.interval, ...)`：随机取一名存活玩家英雄，在其**当前位置**用 `bossSkill.telegraphCircle`（普通技能同一套预警圈口径）出圆形预警圈（半径 `CFG.hazard.radius`、延迟 `CFG.hazard.delay = 1.5`、`bypass = true`）；

   * `onLand`：`job.pointEffect(CFG.hazard.landModel, x, y)` + `job.aoeDamageStun(boss, x, y, {radius, damage = atk×(dmgMul+dmgPer×难度), stun, damageType=魔法, extra={_bossSkill=true,_extraDamage=true}})`。

   * BOSS 死亡/销毁时自杀定时器。

> 所有定时器回调首行统一判 `class.isDestroy(boss) or boss:isDead()` 后 `class.destroy(curTimer)`，避免残留（与现有 BOSS 技能同款写法）。

### 3.2 修改：`projects/demo/scripts/globals/setup/BOSS技能.lua`

**为什么**：把所有主动技能下放到全模式，并为「瞬伤技能」补预警圈 / 落地特效 / 招牌技能。

**怎么做：**

1. **主动技能全模式生效**（改 [L657-L670](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/BOSS技能.lua#L657-L670) 的 `attachByBoss`）：

   * 把 `ADVANCED` 改名 `ACTIVE`，去掉 `if (mode == "进阶模式" or mode == "追击模式")` 门控，改为**无条件**遍历 `ACTIVE[bossName]` 逐个 `bossSkill.attach`。

   * `ALWAYS`（致命一击 + 阿克蒙德混乱之雨）保持不变。

   * 技能内部的难度门控（如 `吸血光环` 的 `diff()<3`、`兽人体质` 的 `diff()>3`）保持不变——它们已用 `diff()` 随难度缩放。

   * 更新文件头注释（“进阶/追击模式再追加各自专属技能” → “所有模式生效”）。

2. **共享预警/落地助手**（新增文件内 local 函数）：

   * `castTelegraphCircle(boss, x, y, opts)`：`job.telegraph({model='提示圈-通用圆形.mdx', x, y, radius, delay, onLand=..})` → 落地时 `job.pointEffect(opts.landModel, x, y)` + `job.aoeDamageStun(...)`。

   * `castTelegraphLine(boss, face, opts)`：`job.telegraph({model='提示圈-直线箭头.mdx', x=boss:x(), y=boss:y(), face, delay, onLand=..})` → 落地时 `job.lineSweep(boss, face, {...})`。

   * `spawnGroundFire(boss, x, y, radius, sec, perSec)`：持续伤害地面（`job.pointEffect` 出燃烧特效 + `time.setInterval(1, ...)` 每秒对圈内敌人 `extraDamage`，到期/自身死亡即销毁）。

3. **现有瞬伤技能改造为「预警 → 落地」**（只改下列「点/自身范围」类，其余被动 / 召唤 / 光环 / 位移类不动）：

   | 技能        | 改造后                                                                                     |
   | --------- | --------------------------------------------------------------------------------------- |
   | 提克迪奥斯-火球术 | 目标方向出**直线预警**（`提示圈-直线箭头.mdx`，face 指向目标）→ 落地后按原「±30° 三道火球」结算，并沿路径补落地特效 |
   | 伊利丹-法力燃烧  | 自身 900 码**圆形预警** → 落地：扣蓝 + 原法术伤害                                              |
   | 麦哥瑟里登-火焰雨 | 目标点 200 码**圆形预警** → 落地后按原「3 波（0.5s 间隔）」结算                                     |
   | 阿克蒙德-死亡一指 | 自身 900 码**圆形预警** → 落地：原法术伤害                                                   |
   | 基尔加丹-炎击   | 目标点 225 码**圆形预警** → 落地：原法术伤害 + 1s 眩晕（**新增 5s CD**，见下）                         |
   | 基尔加丹-连环震荡 | 沿目标方向出**直线预警** → 落地：原「10 波每 0.3s 推进 300 码」结算                                  |

   > 说明：改造只增加「预警 + 落地特效」这一层包装，**伤害数值/范围/眩晕时长与现在完全一致**，不改变强度，只让技能「看得见、能躲」。

4. **预警圈时长统一 + 同屏节流（防"重复播放"）**：
   - 统一时长 `TELEGRAPH_DELAY = 1.5`（与团本 `RAID_SKILL.telegraph` 一致）；圆形模型只有一条循环 `Stand`、直线模型只有 `Birth`，`job.telegraph` 按「速度 = 动作时长 / delay」把一次播放压进 1.5 秒内。
   - 同屏节流 `bossSkill.TELEGRAPH_MAX_ALIVE = 1`：**普通技能**共用 1 个预警圈槽位（槽位占用时该次技能只落地、不画圈，伤害不变）；**招牌技能 / 场地危险区**走 `bypass`，始终显示。
   - 基尔加丹-炎击原为「10% 概率、无 CD」，加预警圈后高频刷圈 → 补 5 秒 CD。

5. **新增招牌技能（`SIGNATURE` 表 + 执行器）**：

   ```lua
   --- 招牌技能配置(每 BOSS 一条); 伤害 = 攻击力 × (dmgMul + dmgPer × 难度)
   --- land=落地/命中特效, cast=起手附着特效, missile=直线投射物 (每个 BOSS 各不相同)
   --- 落地时长统一走 TELEGRAPH_DELAY(1.5s), 与转阶段免伤时长一致
   local SIGNATURE = {
       ["提克迪奥斯"] = { shape='circle', anchor='target', radius=700,  land='FireLordDeathExplode', cast='RainOfFireTarget',    dmgMul=0.6, dmgPer=0.30, stun=0,   burn={radius=700, sec=6, mul=0.15, per=0.10} },
       ["伊利丹"]     = { shape='line',   anchor='target',                land='DemonBoltImpact',     cast='DoomTarget',          missile='AnnihilationMissile', dmgMul=0.8, dmgPer=0.40, stun=1.5 },
       ["地狱咆哮"]   = { shape='circle', anchor='self',   radius=1000, land='VolcanoDeath',        cast='CommandAuraTarget',   dmgMul=0.5, dmgPer=0.25, stun=2   },
       ["阿尔萨斯"]   = { shape='circle', anchor='self',   radius=900,  land='FrostNovaTarget',     cast='FrostArmorTarget',    dmgMul=0.5, dmgPer=0.25, stun=1.5 },
       ["麦哥瑟里登"] = { shape='meteor', anchor='self',   count=6, radius=250, land='RainOfFireTarget', cast='LordofFlameMissile', dmgMul=0.4, dmgPer=0.20, stun=0, spread=900 },
       ["阿克蒙德"]   = { shape='circle', anchor='self',   radius=1200, land='DoomDeath',           cast='DeathandDecayDamage', dmgMul=0.8, dmgPer=0.40, stun=3   },
       ["基尔加丹"]   = { shape='line',   anchor='target',                land='BreathOfFireDamage', cast='MonsoonRain',         missile='LordofFlameMissile', dmgMul=1.0, dmgPer=0.40, stun=1 },
   }
   ```
   - 招牌技能所有预警圈走 `bypass = true`，不受普通技能的同屏上限约束。

   * 新增对外函数 `bossSkill.castSignature(boss, bossName)`：

     * 取 `SIGNATURE[bossName]`，无配置直接返回；

     * `anchor`：`self` → BOSS 坐标；`target` → 当前攻击目标（无则取最近敌人，再退化为自身坐标）；

     * 按 `shape` 分派：`circle` → `castTelegraphCircle`；`line` → `castTelegraphLine`；`meteor` → 随机 `count` 个落点各出圆形预警并按 `dmgMul` 结算；

     * `burn` 存在时在落地后调用 `spawnGroundFire`（提克迪奥斯的灼烧地面）；`cast` 起手特效附着 BOSS 身上（时长 = delay 自动消失）；`missile` 用于直线冲击波投射物。

   * 特效模型**每个 BOSS 单独一套**（火 / 邪能 / 震地 / 冰霜 / 陨石 / 末日 / 烈焰，彼此区分），全部取自 [model_origin.lua](file:///d:/Lua/xlik-jade/projects/demo/assets/model_origin.lua) 已注册别名，无需新增资源。

   * 伤害统一带 `_bossSkill/_extraDamage` 标记（避免触发 BOSS 普攻钩子递归，见 [job.isExtraDamage](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/职业工具.lua#L210-L220)）。

### 3.3 修改：`projects/demo/scripts/process/BOSS.lua`

**为什么**：接入数值强化与 `bossPlay`。

**怎么做：**

1. **数值强化（可调常量，放在文件顶部数值表附近）**：

   ```lua
   --- BOSS 生存向数值倍率(仅作用于主线 BOSS, 不影响 存档BOSS/团本: getBossStat 走原函数)
   local BOSS_HP_MUL     = 2.0
   local BOSS_DEFEND_MUL = 1.5
   ```

   在 `create_boss()` 中改为：

   ```lua
   boss:hp(get_boss_hp() * BOSS_HP_MUL)
   boss:hpCur(boss:hp())
   boss:defend(get_boss_defend() * BOSS_DEFEND_MUL)
   ```

   > 倍率**只加在** **`create_boss`** **调用处**，不改 `get_boss_hp/get_boss_defend/getBossStat`，避免连带影响 `存档BOSS` / 团本「魔君」的取值（[存档挑战.lua#L809](file:///d:/Lua/xlik-jade/projects/demo/scripts/globals/setup/存档挑战.lua#L809) 依赖 `game.method.getBossStat`）。

2. **接入玩法系统**：在 `create_boss()` 末尾、`bossSkill.attachByBoss(boss, boss_name, boss_index)` 之后追加：

   ```lua
   --- BOSS 玩法强化: 保命(单次受伤上限/护盾) + 转阶段 + 场地危险区
   bossPlay.attach(boss, boss_name)
   ```

3. **清理过时 TODO**：删除 [L330-L331](file:///d:/Lua/xlik-jade/projects/demo/scripts/process/BOSS.lua#L330-L331) 两条注释（前者由本次实现，后者见「假设与决策 5」）。

### 3.4 不改动项（明确排除）

* `BOSS.lua` 的出生倒计时 / 击杀时限（180 秒）/ 死亡奖励 / 通关判定逻辑。

* `boss_name_list`、`boss_tpl_list`、`diff_boss_count`、`boss_base_*_list` 等表结构与档位。

* `slkc_boss` UI（血条 / 倒计时 / 全屏预警）。

* `globals/setup/存档挑战.lua`、`tpl/unit/存档BOSS.lua`、`tpl/unit/BOSS.lua`（模板）。

* 玩家方数值与英雄成长。

## 四、假设与决策（Assumptions & Decisions）

1. **范围**：只强化主线 7 个 BOSS；存档/爬塔/团本 BOSS 不动（团本已有预警圈体系）。
2. **覆盖模式**：主动技能在**全部模式**（含正常模式）生效（用户确认「全模式 + 全部 7 个 BOSS」）；技能内部原有的难度门控保留。
3. **保命三重层**：单次受伤上限（`perHitCapPct=8%`）+ 周期吸收护盾（`shieldPct=15%`，每 25s）+ 转阶段定格免伤（阈值 70%/40%/15%，各 1.5s）。
4. **转阶段不改变无敌口径之外的行为**：转阶段期间 BOSS 完全免伤 + 定格，释放招牌技能后恢复并狂暴（攻击 +30% 增幅 / 攻速 +20 点，逐段叠加）。
5. **超进化减伤 TODO 本次不处理**：`switch_nightmare` 相关减伤与本次两问题（被秒 / 没技能）无直接关系，且会显著影响超进化模式平衡，留待后续专项。本次删除该 TODO 注释以免误导，如需保留可改为显式说明。
6. **所有数值均集中在可调常量**：`BOSS.lua` 的 `BOSS_HP_MUL` / `BOSS_DEFEND_MUL` 与 `BOSS技能.lua` 的 `SIGNATURE` 表、`bossPlay.lua` 的 `CFG`。**具体取值需实机试玩微调**（本方案无法在本机验证实际战斗手感）。
7. **击杀时限**：默认维持 180 秒。若实测「变肉后打不完」，只需下调 `BOSS_HP_MUL` 或 `perHitCapPct`，不改时限逻辑。
8. **不新增美术资源**：预警圈 / 落地 / 护盾全部复用已注册模型（`提示圈-*`、`团队BOSS技能2.mdx`、`团队BOSS投射物2.mdx`、标准魔兽路径）。
9. **不做打包 / 游戏内测试**（按用户既往约定），仅做静态检查与逻辑自检。

## 五、验证步骤（Verification）

1. **静态检查**（语法）：

   ```
   luac -p projects/demo/scripts/globals/setup/BOSS玩法.lua
   luac -p projects/demo/scripts/globals/setup/BOSS技能.lua
   luac -p projects/demo/scripts/process/BOSS.lua
   ```
2. **残留引用排查**（应为预期结果）：

   * `ADVANCED`（`BOSS技能.lua`）应无残留（已改名 `ACTIVE`）；

   * `bossPlay.attach` 在 `BOSS.lua` 中存在且仅一处；

   * `BOSS_HP_MUL` / `BOSS_DEFEND_MUL` 仅出现在 `BOSS.lua`；

   * `getBossStat` / `get_boss_hp` / `get_boss_defend` 的**定义未被修改**（倍率只在 `create_boss` 调用处）。
3. **逻辑自检**（人工核对代码）：

   * 正常模式下 7 个 BOSS 均装配了 `ACTIVE` 主动技能（不再是只有一击必杀）。

   * 点/自身范围技能落地前有预警圈与落地特效；伤害数值与改造前一致。

   * 每 BOSS 招牌技能按 `SIGNATURE` 正确分派 circle/line/meteor，伤害带 `_bossSkill` 标记。

   * 单次受伤上限 / 护盾吸收在 `unitBeforeHurt` 中生效；护盾用尽即 `effector.detach`。

   * 血量跌破 70%/40%/15% 各触发一次转阶段：免伤 + 定格 + 招牌技能 + 狂暴，且不重复触发。

   * 场地危险区按间隔点名落点，落地造成范围伤害。

   * BOSS 死亡后所有 `setInterval` 定时器自杀、护盾特效移除、无残留。
4. **游戏内测试（由用户执行）**：

   * 观察 7 个 BOSS 是否在正常模式下也放技能、是否有预警圈与落地特效。

   * 用高爆发职业测试：BOSS 不再被瞬间秒杀，护盾/阶段免伤可见。

   * 观察转阶段播报、定格、招牌技能与狂暴叠加。

   * 观察周期性场地危险区，确认可走位躲避。

   * 确认 180 秒内仍能击杀（若打不完，按「假设 7」调参）。

