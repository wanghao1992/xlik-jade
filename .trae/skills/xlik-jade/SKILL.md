---
name: "xlik-jade"
description: "xlik-jade 魔兽争霸3 Lua框架开发技能。提供框架核心模块(事件、类、属性、伤害、时间等)的API参考、设计模式和编码规范。当用户询问xlik-jade框架相关问题、编写地图逻辑、使用框架API或创建技能/物品/单位时调用。"
---

# xlik-jade 框架开发指南

xlik-jade 是一个基于 Lua 的 Warcraft 3 地图开发框架，提供完整的类系统、事件系统、属性系统、伤害流程等基础设施。

## 目录结构

```
library/           # 框架核心库
├── ability/       # 独立技能集合（damage, invisible, stun 等）
├── class/         # 类系统
│   ├── meta/      # 精简元类
│   ├── ui/        # UI界面类
│   └── vast/      # 复合大类（Unit, Item, Ability 等）
├── common/        # 基础库（事件、属性、时间、伤害等）
└── japi/          # JAPI接口层（YD, DZ, KK, LK）
```

加载顺序由 `library.yaml` 的 `require` 字段控制：
```yaml
require:
  - "common"
  - "japi"
  - "ability"
  - "class"
```

## 模块命名规范

每个文件使用全局 namespace 模式：
```lua
--- 模块注释
---@class moduleName
moduleName = moduleName or {}

--- 函数注释
---@param param1 type 描述
---@return returnType
function moduleName.funcName(param1)
    -- 实现
end
```

## 类系统

### 1. Meta（精简元类）

适用于简单数据结构的对象。

```lua
-- 定义 Meta 类
local _index = { _type = "Meta" }
function Meta(name, prototype)
    -- name: 类名（字符串）
    -- prototype: 原型数据
end

-- 示例：Array
local ArrayMeta = Meta("Array", {
    _data = {},
    function _index:count() return #self._data end,
    function _index:set(key, value) self._data[key] = value end,
    function _index:get(key) return self._data[key] end,
})
```

### 2. Vast（复合大类）

适用于功能复杂的大对象（Unit, Item, Ability 等）。

```lua
-- 定义 Vast 类
local _index = Vast(UnitClass)  -- UnitClass = "Unit"

-- 构造方法（非类方法，是全局构造函数）
function Unit(force, tpl, x, y, facing)
    local o = oVast({...}, _index, tpl)
    -- ...
    return o
end

-- 关键方法
_index:set(name, variety, duration, domain)    -- 设置属性（带持续时间/Buff支持）
_index:get(name, domain)                       -- 获取属性
_index:modify(name, variety, ...)              -- 双向（get/set）属性访问
_index:raise(name, variety, duration)          -- 设置过程增幅（百分比）
_index:ampl(name, variety, duration)           -- 设置终结增幅（百分比）
_index:onEvent(evt, ...)                       -- 注册事件
```

### 3. 对象生命周期

```lua
-- 创建对象
local unit = Unit(owner, unitTpl, x, y, facing)

-- 销毁对象
class.destroy(obj)

-- 判断对象状态
class.is(obj)                    -- 是否类对象
class.isObject(obj, UnitClass)   -- 是否特定类型实例
class.isDestroy(obj)             -- 是否已销毁
class.instanceof(obj, name)      -- 是否类实例
```

## 事件系统

事件分为三种类型：
1. **condition** - 原生条件注入事件
2. **sync** - 自定义同步事件（必须在同步环境触发）
3. **async** - 自定义异步事件（可在异步环境触发）

### 注册事件

```lua
-- 同步事件注册
event.syncRegister(symbol, evtKind, key, callback)
event.syncRegister(symbol, evtKind, callback)  -- key 默认为 "default"

-- 异步事件注册
event.asyncRegister(symbol, evtKind, key, callback)

-- 注销事件
event.syncUnregister(symbol, evtKind, key)
event.asyncUnregister(symbol, evtKind, key)
```

### 触发事件

```lua
-- 触发同步事件
event.syncTrigger(symbol, evtKind, triggerData)

-- 触发异步事件
event.asyncTrigger(symbol, evtKind, triggerData)
```

### 事件种类（eventKind 参考）

```lua
-- 单位事件
eventKind.unitDamage          -- 造成伤害
eventKind.unitHurt            -- 受伤
eventKind.unitBeforeHurt      -- 受伤前
eventKind.unitAttack          -- 攻击
eventKind.unitBeAttack        -- 被攻击
eventKind.unitDead            -- 死亡
eventKind.unitKill            -- 杀敌
eventKind.unitBorn            -- 出生
eventKind.unitReborn          -- 复活
eventKind.unitAbilitySpell    -- 开始施放技能
eventKind.unitAbilityEffective -- 技能生效
eventKind.unitAbilityCasting  -- 持续施法每周期
eventKind.unitAbilityStop     -- 停止施放
eventKind.unitAbilityOver     -- 施放结束

-- 玩家事件
eventKind.playerChat          -- 聊天
eventKind.playerEsc           -- 按下Esc
eventKind.playerSelect        -- 选择单位
eventKind.playerQuit          -- 离开游戏

-- UI事件
eventKind.uiLeftClick         -- 左键点击
eventKind.uiRightClick        -- 右键点击
eventKind.uiEnter             -- 移入
eventKind.uiLeave             -- 移出

-- Class事件
eventKind.classConstruct      -- 创建
eventKind.classDestruct       -- 毁灭
eventKind.classBeforeChange   -- 参数改变前（需拼接参数名）
eventKind.classAfterChange    -- 参数改变后（需拼接参数名）
```

> **注意**：事件触发数据中的 `triggerData` 会自动根据 symbol 的 className 注入对应的 trigger 字段。
> 例如：Unit 触发时自动生成 `triggerUnit`，Item 触发时自动生成 `triggerItem`。

### 拓扑域事件传播

当 symbol 是类实例时，事件会先触发拓扑域（className）的事件，再触发实例自身的事件：
```lua
-- 注册到 UnitClass 拓扑域，所有 Unit 实例触发 unitDamage 时都会执行
event.syncRegister(UnitClass, eventKind.unitDamage, "globalDamageLog", function(td)
    print(td.triggerUnit:id() .. " dealt " .. td.damage .. " damage")
end)
```

## 属性系统

### 属性配置

```lua
-- 配置属性
-- @param anti boolean 反属性（增加反而不好）
-- @param key string 键值
-- @param label string 显示名称
-- @param form string 单位范式（可选 "%"）
-- @param icon string buff图标
attribute.conf(false, "attack", "攻击力")
attribute.conf(true, "cd", "冷却缩减", "%")

-- 获取属性信息
attribute.label(key)     -- 属性名称
attribute.form(key)      -- 属性单位
attribute.icon(key)      -- 属性图标
attribute.isAnti(key)    -- 是否反属性
attribute.isPercent(key) -- 是否百分比属性
```

### 属性修改

```lua
-- 设置属性（支持 +=\d、-=\d、*=\d 等运算表达式）
unit:set("attack", "+=50")         -- 攻击力增加50
unit:set("attack", "+=50;10")      -- 攻击力增加50，持续10秒（分号后的数字为持续时间）
unit:set("hpCur", "-=100")         -- 扣减当前生命值

-- 进阶修改
unit:set("attack", "+=50", 10)     -- 攻击增加50，持续10秒（带自动Buff）
unit:raise("attack", 20)           -- 过程增幅20%：后续对attack的所有改变量增加20%
unit:ampl("attack", 15)            -- 终结增幅15%：在获取attack最终值时额外增加15%

-- 获取属性
unit:get("attack")                 -- 获取攻击力（受过程增幅、终结增幅综合影响）
unit:modify("attack", nil)         -- 只读方式获取（同 get）
unit:modify("attack", "+=20")      -- 修改并返回 self
```

## 时间系统

```lua
-- 一次性计时器
time.setTimeout(period, function(curTimer)
    -- period 秒后执行一次
end)

-- 周期性计时器
time.setInterval(period, function(curTimer)
    -- 每 period 秒执行一次
    class.destroy(curTimer)  -- 停止计时器
end)

-- 游戏时间
time.ofDay()           -- 获取当前游戏时间（0-24）
time.ofDay(12)         -- 设置游戏时间为正午
time.ofDayScale(2.0)   -- 设置时间流速
time.isNight()         -- 是否夜晚
time.isDay()           -- 是否白天

-- 时间事件
time.onDawn("key", callback)    -- 凌晨
time.onDay("key", callback)     -- 白天
time.onNoon("key", callback)    -- 正午
time.onNight("key", callback)   -- 黑夜
```

## 伤害系统

### 伤害类型与来源

```lua
-- 伤害类型（默认已注册）
injury.damageType.common      -- 常规
injury.damageType.physics     -- 物理
injury.damageType.magic       -- 魔法

-- 伤害来源
injury.damageSrc.common       -- 常规
injury.damageSrc.attack       -- 攻击
injury.damageSrc.ability      -- 技能
injury.damageSrc.item         -- 物品
injury.damageSrc.rebound      -- 反伤
injury.damageSrc.reaction     -- 附魔反应

-- 破防类型
injury.breakArmorType.defend      -- 防御
injury.breakArmorType.avoid       -- 回避
injury.breakArmorType.invincible  -- 无敌
```

> **注意**：自定义伤害类型需使用 `Enchant` 注册才能被识别，参考 `enchant.lua`。

### 造成伤害

```lua
ability.damage({
    sourceUnit = sourceUnit,            -- 源单位
    targetUnit = targetUnit,            -- 目标单位（必填）
    damage = 100,                       -- 伤害值
    damageSrc = injury.damageSrc.ability,   -- 伤害来源
    damageType = injury.damageType.fire,    -- 伤害类型
    damageTypeLevel = 1,                -- 伤害类级别
    breakArmor = {injury.breakArmorType.defend}, -- 破防类型
    extra = { customKey = "value" },    -- 额外数据
})
```

### 注册自定义伤害类型（使用 Mapping）

```lua
local m_dt = Mapping("damageType")
injury.damageType = injury.damageType or {
    common = m_dt:set("common", "常规"),
    physics = m_dt:set("physics", "物理"),
    magic = m_dt:set("magic", "魔法"),
    fire = m_dt:set("fire", "火"),
    -- 继续添加...
}

-- 验证函数
injury.isValidDamageType(whichType)
injury.isValidDamageSrc(whichSrc)
injury.isValidBreakArmorType(whichType)
```

## 叠加态系统（Superposition）

用于管理单位状态的临界值自动处理（如眩晕叠加、免疫叠加等）。

```lua
-- 叠加操作
superposition.plus(unit, "stun")      -- 眩晕层数+1
superposition.minus(unit, "stun")     -- 眩晕层数-1

-- 状态查询
superposition.is(unit, "stun")        -- 是否眩晕中
superposition.is(unit, "dead")        -- 是否死亡
superposition.is(unit, "silent")      -- 是否沉默

-- 直接在 Unit 上查询
unit:isStunning()       -- 眩晕
unit:isSilencing()      -- 沉默
unit:isUnArming()       -- 缴械
unit:isInvulnerable()   -- 无敌
unit:isInvisible()      -- 隐身
unit:isPause()          -- 暂停
unit:isInterrupt()      -- 施法中止
unit:isDead()           -- 死亡

-- 配置自定义叠加态
superposition.config(UnitClass, "myState",
    function(obj)   -- up：状态进入时
        print(obj:id() .. " entered myState")
    end,
    function(obj)   -- down：状态退出时
        print(obj:id() .. " exited myState")
    end
)
```

> **核心机制**：叠加态使用引用计数，当计数 > 0 时触发 `up` 回调，计数 <= 0 时触发 `down` 回调。这确保了多个来源同时施加同一个状态时不会冲突。

## Unit 对象常用方法

```lua
-- 坐标与移动
unit:x(), unit:y(), unit:z()        -- 获取坐标
unit:h()                             -- 凌空高度
unit:position(x, y)                  -- 移动到坐标
unit:facing()                        -- 面向角度
unit:facing(90)                      -- 设置面向角度
unit:move()                          -- 移速
unit:move("+=50")                    -- 移速增加

-- 状态
unit:isAlive() | isDead() | isStunning() | isSilencing()
unit:isUnArming() | isInvulnerable() | isInvisible()
unit:isBuilding() | isGround() | isAir() | isWater()
unit:isMelee() | isRanged()
unit:isHurting() | isDamaging()

-- 战斗属性
unit:attack()                        -- 攻击力
unit:attack("+=50")                  -- 攻击增加
unit:attackRange()                   -- 攻击范围
unit:attackSpeed()                   -- 攻击速度加成[%]
unit:attackRipple()                  -- 随机浮动攻击
unit:attackSpace()                   -- 攻击频率[当前实际]
unit:defend()                        -- 防御（直接扣减伤害）
unit:hp() | unit:hpCur()             -- 最大血量 / 当前血量
unit:hpCur("-=100")                  -- 扣血
unit:hpRegen()                       -- 生命恢复
unit:mp() | unit:mpCur()             -- 最大魔法 / 当前魔法
unit:mpRegen()                       -- 魔法恢复
unit:sight() | unit:nsight()         -- 白昼视野 / 黑夜视野
unit:str() | unit:agi() | unit:int() -- 力量 / 敏捷 / 智力
unit:assault()                       -- 获取攻击模式
unit:owner()                         -- 所有者

-- 技能相关
unit:cost() | unit:costPercent()     -- 技能消耗修正[值/%]
unit:coolDown() | unit:coolDownPercent() -- 冷却修正[秒/%]
unit:castChant() | unit:castChantPercent() -- 施法前摇修正[秒/%]
unit:castKeep() | unit:castKeepPercent()   -- 持续施法修正[秒/%]
unit:castDistance() / castRange()    -- 施法距离/范围修正
unit:odds("crit", 20)                -- 通用几率[%]
unit:resistance("fire", 15)          -- 通用抵抗[%]

-- 物品与技能
unit:itemSlot()                      -- 物品栏
unit:abilitySlot()                   -- 技能栏
unit:hasAbility(tpl)                 -- 是否有某技能
unit:hasItem(tpl)                    -- 是否有某物品

-- 命令
unit:orderStop()                     -- 停止
unit:orderHold()                     -- 伫立
unit:orderMove(x, y)                 -- 移动
unit:orderAttack(x, y)               -- 攻击点
unit:orderAttackTargetUnit(target)   -- 攻击单位
unit:pickItem(targetItem)            -- 捡物品
unit:kill()                          -- 杀死
unit:animate("attack")               -- 播放动画

-- 属性增益修正（Vast 基类方法）
unit:raise("attack", 20)             -- 过程增幅20%：对attack的所有改变量增幅20%
unit:ampl("attack", 15)              -- 终结增幅15%：获取最终值时额外乘1.15
```

## Ability（技能）开发

框架内置的技能库位于 `library/ability/`，包括：
- `damage` - 伤害技能
- `invisible` - 隐身
- `invulnerable` - 无敌
- `reborn` - 复活
- `sight` - 视野
- `silent` - 沉默
- `stun` - 眩晕
- `unArm` - 缴械
- `visible` - 反隐
- `missile` - 弹射物

```lua
-- 使用技能
ability.stun(targetUnit, duration)      -- 眩晕
ability.invisible(unit, duration)       -- 隐身
ability.invulnerable(unit, duration)    -- 无敌
```

### 注册技能事件

在技能 TPL 中使用 `onUnitEvent` 注册事件：

```lua
-- 在 Ability TPL 中注册事件
-- 事件会按照 Ability > Unit 的优先级触发，
-- 如果 Ability 事件中技能被注销，Unit 事件将不会触发
```

> **事件优先级**：Ability 事件 > Unit 事件。如果 Ability 事件处理中技能被注销，Unit 级别的事件将不会触发。

## TPL（模板系统）

TPL 是框架的对象模板，用于定义 Unit、Item、Ability 的初始属性。

```lua
-- 定义单位模板
local myUnitTpl = UnitTpl("MyUnit", {
    _attack = 50,
    _defense = 20,
    _hp = 1000,
    _model = "units\\human\\Footman\\Footman.mdx",
})

-- 创建单位
local unit = Unit(Player(1), myUnitTpl, 0, 0, 270)
```

## 常用 Utility 函数

```lua
-- 数据处理
datum.default(value, defaultValue)  -- 默认值处理
datum.ternary(bool, tVal, fVal)     -- 三目运算
datum.keyFunc(...)                   -- key-function 复合参数解析
datum.enumKey(enum)                  -- 获取对象唯一key
datum.enumXY(enum)                   -- 获取对象坐标

-- 数学
math.rand(min, max)                  -- 随机整数
math.round(num)                      -- 四舍五入
vector2.angle(x1,y1,x2,y2)           -- 向量角度
vector2.polar(x,y,dist,angle)        -- 极坐标
vector2.distance(x1,y1,x2,y2)        -- 距离

-- 字符串
string.explode(sep, str)             -- 分割字符串
mbstring.split(str, n)               -- 按字符数分割
colour.hex(colorCode, text)          -- 颜色文本

-- 同步与异步
sync.must()                          -- 强制同步环境
async.is()                           -- 是否异步环境
async.must()                         -- 强制异步环境
async.call(player, callback)         -- 某玩家异步调用
async.loc(callback)                  -- 本地异步调用
```

## 与原生 Warcraft 3 交互

通过 `J` 前缀调用原生 API：
```lua
J.CreateUnit(ownerHandle, slkId, x, y, facing)
J.GetUnitX(handle)
J.SetUnitPosition(handle, x, y)
J.TriggerAddCondition(trigger, condition)
```

通过 `japi` 调用扩展 API：
```lua
japi.YD_SetEffectSpeed(eff, speed)
japi.DZ_UnitDisableAttack(handle, true)
japi.Z(x, y)  -- 获取地面高度
```

## Buff/Debuff 系统

框架的 `set` 方法在指定 `duration > 0` 时会自动创建 Buff：

```lua
-- 自动创建 Buff
unit:set("attack", "+=50", 10)  -- 攻击+50，持续10秒，带视觉效果

-- 手动创建 Buff
Buff({
    key = "myBuff",
    object = unit,
    signal = buffSignal.up,        -- 上箭头（增益）
    duration = 10,
    description = {"效果描述", "持续时间"},
    purpose = function(o)          -- 应用效果
        o:modifier(true, "_attack", 50)
    end,
    rollback = function(o)         -- 回滚效果
        o:modifier(true, "_attack", -50)
    end,
})
```

## 常用编码模式

### 1. 模块初始化模式

```lua
--- 模块注释
---@class myModule
myModule = myModule or {}
```

### 2. 事件注册模式

```lua
-- 在构造方法中注册实例事件
function MyClass(...)
    local o = oVast({...}, _index, tpl)
    event.syncRegister(o, eventKind.unitHurt, function(td)
        -- 受伤回调
    end)
    return o
end
```

### 3. 混合修改模式

```lua
-- 使用 +=、-=、*= 表达式
unit:set("attack", "+=20")     -- 增加
unit:set("attack", "-=10")     -- 减少
unit:set("attack", "*=2")      -- 翻倍
```

### 4. 事件数据模式

```lua
-- triggerData 会自动根据 symbol 类型注入对应字段
-- symbol 为 Unit 对象时，自动生成 triggerUnit
-- symbol 为 Item 对象时，自动生成 triggerItem
```

### 5. 异步操作模式

```lua
-- 只能在异步环境运行的操作
async.call(player, function()
    -- 在此执行异步操作
end)

-- 异步计时器（帧计数器）
async.setTimeout(30, function(curTimer)
    -- 30帧后执行
end)
async.setInterval(10, function(curTimer)
    -- 每10帧执行一次
end)
```

## 三层层级架构

xlik-jade 框架分为三个层级：

| 层级 | 路径 | 语言 | 职责 |
|------|------|------|------|
| **构建工具层** | `exe/` | Go + Lua | 资源打包、SLK 生成、脚本加密、地图构建 |
| **运行时核心层** | `library/` | Lua | 类系统、事件、属性、伤害流程等游戏逻辑 |
| **项目业务层** | `projects/*/` | Lua | 地图业务代码、TPL 定义、流程控制 |

### 构建流水线（Build Pipeline）

`xlik.exe run demo -l` 的执行流程：

```
1. Lua Assets 处理 → assets_model, assets_speech, assets_image 等注册资源
2. SLK 数据生成 → slk_unit 创建物编数据
3. Go 工具后处理：
   a. 模型别名解析：asModelAlias["Footman"] → "units\\human\\Footman\\Footman.mdl"
   b. 资源去重检测、未使用检测
   c. 自动复制 Portrait 文件（xxx_Portrait.mdx）
   d. 写入 SLK/INI 文件 → map/table/unit.ini
4. Script 合并与加密
5. 打包为 w3x 并启动 War3
```

## Assets 资源系统

资源在 `assets/` 目录下通过 Lua 函数声明引入，由 Go 工具处理。

### 模型 Model

```lua
-- war3mapModel 目录下的相对路径
assets_model("buff/Echo")
-- 带别称（推荐）
assets_model("buff/Echo", "echo")
```

模型处理细节（`luaAssets.go:515-555`）：
- 自动检测 `xxx_Portrait.mdx` 并复制到地图资源目录
- 解析模型内引用的 `.blp` 贴图，自动从 `war3mapTextures` 引入
- 别名注册到 `asModelAlias`，供 SLK 处理时 `model` → `file` 别名解析

### 语音 Speech（SLK 单位定义）

语音模版是**内置魔兽语音**的单位定义，也是框架中**创建 SLK 单位的核心方式**。

```lua
-- 基础引用（无模型）
assets_speech("Footman")

-- 在 tpl 中使用
UnitTpl("Footman")
```

#### SpeechExtra 变体系统

`assets_speech` 的第二个参数是 `extra` 表，可以为语音模版创建变体：

```lua
-- 为语音模版创建 "avatar" 变体
assets_speech("Footman", {
    avatar = assets_speech_extra({ model = "Footman" }), -- 模型头像模组
})

-- 在 tpl 中使用变体
UnitTpl("Footman", "avatar")
```

**工作原理**：

1. `assets_speech("Footman")` 创建基础 SLK 单位，`Name = "Footman|D"`，`file = ".mdl"`
2. 传入 `extra` 表时，为每个 key 创建变体 SLK 单位，`Name = "Footman|EX|avatar"`
3. 变体继承基础单位的所有字段，然后用 extra 中的字段覆盖
4. **Go 工具处理**（`luaDev.go:263-271`）：
   - 跳过自定义 `model` 字段（不直接写入 SLK INI）
   - 在处理 `file` 字段时检查 `_slk["model"]`，如果存在则通过 `asModelAlias` 解析为完整路径
   - 最终写入 INI 的是 `file = "units\\human\\Footman\\Footman.mdl"`
5. 运行时 `UnitTpl("Footman", "avatar")` → `slk.n2i("Footman|EX|avatar")` 找到变体 → 单位创建时就有正确模型

**不传 speechExtra 时**：`slk.n2i("Footman|D")` 回退到 `.mdl` 模型，需要 `:model("Footman")` 运行 `DZ_SetUnitModel` 换模型（不更新肖像）。

### 肖像 Portrait 系统

肖像显示需要单位 SLK 定义中有真实的模型路径（`file` 字段），机制如下：

| 方式 | 模型来源 | 肖像 | 说明 |
|------|----------|------|------|
| `assets_speech("Footman")` + `:model("Footman")` | `DZ_SetUnitModel` 运行时换 | ❌ 不更新 | 原始 `.mdl` 无肖像 |
| `assets_speech("Footman", { avatar = { model = "Footman" } })` | SLK `file` 直接指定 | ✅ 自动显示 | Go 工具解析别名到路径 |
| `assets_speech("Footman", { avatar = { file = "full\\path.mdl" } })` | SLK `file` 直接指定 | ✅ 自动显示 | 直接写路径也行 |

`model` vs `file` 字段的选择：
- `model = "Footman"`（推荐）：Go 工具通过 `asModelAlias` 将别名解析为完整路径后写入 SLK 的 `file` 字段
- `file = "units\\human\\Footman\\Footman.mdl"`：直接写完整路径，Go 工具原样写入

标准魔兽模型会自动加载 `_Portrait.mdx`（如 `Footman_Portrait.mdx`），Go 工具构建时也自动复制自定义模型的肖像文件。

## 对象构造系统

### oVast（Vast 对象构造）

```lua
-- oVast(params, index, ...)
-- params: 初始数据
-- index: 类元表（Vast返回的_index）
-- ...: 额外的原型链（如 Tpl）
function oVast(params, ...)
    local indexes = { ... }
    local o = params
    if (#indexes == 1) then
        setmetatable(o, { __index = indexes[1], __reality = true })
    else
        -- 多原型链：先查找 Tpl，再查找类
        setmetatable(o, {
            __reality = true,
            __indexes = indexes,
            __index = function(_, key)
                for _, es in ipairs(indexes) do
                    local v = es[key]
                    if (nil ~= v) then return v end
                end
            end
        })
    end
    class.id(o, true)     -- 分配唯一ID
    -- 沿原型链自底向上调用 construct 回调
    -- 触发 classConstruct 事件
end
```

### VastModifierAct

`VastModifierAct(o)` 在 `oVast` 之后调用，遍历 Unit 实例的所有属性，触发注册在 `_vastModifier.lua` 中的属性修改回调（如 `_model` → `DZ_SetUnitModel`）。

## Flow 流系统

Flow 用于组织业务片段的顺序执行，常用于伤害流程（`damage` flow）：

```lua
local damageFlow = Flow("damage")

-- 中止条件：伤害 <= 0 时中止后续流程
damageFlow:abort(function(data)
    return data.damage <= 0
end)

-- 注册流程片段
damageFlow:flux("prop", function(data)
    -- 处理暴击、护甲穿透等
end)

damageFlow:flux("breakArmor", function(data)
    -- 处理破防
end)

damageFlow:flux("enchant", function(data)
    -- 处理附魔加成
end)

-- 触发流程
Flow("damage"):run(options)
```

## Process 流程管理系统

流程以 `start` 为入口，可以在流程间跳转、重置：

```lua
local process = Process("start")
function process:onStart()
    -- 初始化
    self:next("test")  -- 跳转到 test 流程
end

function process:onOver()
    -- 流程结束时的清理
end

-- 泡影数据（流程结束时自动清理对象）
function process:onStart()
    local bubble = self:bubble()
    bubble.boss = Unit(Player(12), TPL_UNIT.BOSS, 0, 0, 0)
end
```

## 开发注意事项

1. **同步环境**：所有修改游戏状态的操作必须在同步环境（`sync.must()`）中执行
2. **异步环境**：UI 操作、本地玩家操作必须在异步环境（`async.must()`）中执行
3. **属性验证**：使用 `must()` 函数对参数进行运行时的严格类型检查
4. **对象销毁**：使用 `class.destroy(obj)` 统一销毁对象，不要直接 `obj = nil`
5. **事件生命周期**：对象销毁时会自动触发 `classDestruct` 事件
6. **文件加载**：框架自动按文件名顺序加载，**不需要**也不应该使用 `require`
7. **混淆支持**：`library.yaml` 中配置的混淆规则会自动处理变量名替换
8. **模型别名**：所有模型路径建议通过 `assets_model` 注册别名，构建工具会自动解析
9. **SLK 变体**：使用 `speechExtra` 可以创建 SLK 单位变体，提供不同模型/属性
10. **流量检测**：Go 工具会自动检测未使用的资源（中文字符串、路径引用）并警告
