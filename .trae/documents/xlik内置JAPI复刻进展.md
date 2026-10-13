# xlik 内置 JAPI 复刻进展：LoadToc / GetGameUI 已打通

> 复刻产物：`vendor/japi-replica/`（YDWE 插件形态，链接 `ydwar3.lib`）
> 目标环境：魔兽争霸 III **1.27a**（ydwar3 版本号 `7000`；PE 版本 `52240 = 0xcc10`）
> 本文只记录**已实测验证通过**的能力与数据，未打通部分单列在最后。

---

## 一、已打通的能力（均有实测证据）

| 能力 | native | 状态 |
|---|---|---|
| 指令边界扫描 | （内部基建） | ✅ 与内置插件等价 |
| 分层字符串锚点定位 | （内部基建） | ✅ |
| **LoadToc**（载入 toc/fdf、注册控件类型） | `LoadToc (S)V` | ✅ 端到端 |
| **GetGameUI**（取根控件） | `GetGameUI ()I` | ✅ |
| 按 fdf tag 建控件 | `CreateFrameByTagName (SSISI)I` | ✅ 建出对象 |
| **FrameSetSize**（设尺寸） | `FrameSetSize (IRR)V` | ✅ 视觉闭环 |
| **FrameSetPoint**（设锚点） | `FrameSetPoint (IIIIRR)V` | ✅ 视觉闭环（见第十节） |
| **FrameSetAlpha**（设透明度） | `FrameSetAlpha (II)V` | ✅ 视觉闭环（见第十节） |

---

## 二、基建：指令边界扫描 + 字符串锚点

内置插件的核心技法「零特征码定位」= **字符串锚点 → .text 代码引用 → 解 call 目标**。

| 环节 | 内置插件 | 我们 |
|---|---|---|
| 沿指令边界扫描下一条指令 | `FUN_102c90a0`（内置 udis86） | **直接复用 ydwar3 导出的 `warcraft3::next_opcode(p, opcode, len)`**（内部就是同一份 udis86） |
| 解 `call rel32` 目标 | `p + 5 + *(int*)(p+1)` | `warcraft3::convert_function(p)` |
| 字符串查找 | `FUN_102c8f50` / `FUN_102c9450` | `jr::find_game_string()`（.rdata/.data 精确→子串） |
| 代码引用定位 | 内置循环 | `jr::find_code_ref_in_text()`（.text 逐字节找 `dword == 地址`） |

代码位置：[war3_layer.cpp](../../vendor/japi-replica/src/war3_layer.cpp) 的 `resolve_callsite` / `call_target_of` / `scan_next_call_target`。

> 关键结论：**不需要自己移植 udis86**——YDWE 已把它连同 `next_opcode` 一起导出，直接用即可。

---

## 三、LoadToc（`FUN_10248740` 三步链）

作用是**让 war3 去解析 fdf、把其中的控件类型注册进「frame 类型注册表」**。

```
① FUN_102485b0  找字符串 "UI\FrameDef\FrameDef.toc" 的 .text 引用处 ref，返回 ref - 1
                （ref 是 push imm32 的立即数，在指令第 2 字节 → ref-1 正是指令起始）
                找不到时回退 Game.dll base + 0x282BC
② FUN_10248690  从①出发沿指令边界找第一条 E8，取其目标 = FrameDef 处理函数 base_fn
③ FUN_10248740  在 base_fn 体内依次定位：
                  mov esi, imm32  (0xBE)
                  push imm32      (0x68)
                  mov edx, imm32  (0xBA)  ← 从 push 那条之后找
                  call rel32      (0xE8)  ← 从 mov edx 那条之后找
                取这三条指令的立即数，把 war3 自己那次调用「重放」一遍，
                只把首个参数换成我们传入的 toc 路径：
                  ECX = path
                  EDX = mov-edx 的立即数
                  栈  = (push 的立即数, mov-esi 的立即数)
```

**实测值（1.27a）**：

| 项 | 值 |
|---|---|
| 锚点字符串地址 | `0x6EF61C54` |
| .text 引用处 ref | `0x6E6382BC` |
| `base_fn` | `0x6E6A0B70`（RVA `0x90B70`） |
| 三个立即数 | `esi=0x6F1762CC`、`push=0x6F1C9CFC`、`edx=0x6F1C9CAC` |
| 重放的调用目标 | `0x6E676590` |

**效果验证**：`japi.Exec("LoadToc", "UI\\xlik.toc")` 之后，`UI\xlik.fdf` 里定义的条目**全部**注册成功：

```
JKFrameTypeLookup: "LK_BACKDROP"   -> entry=0x0FBC1B28 flags(bit1)=1
JKFrameTypeLookup: "LK_TEXT"       -> entry=0x0FB67C40 flags(bit1)=1
JKFrameTypeLookup: "LK_MODEL"      -> entry=0x0F8317A8 flags(bit1)=1
JKFrameTypeLookup: "LK_TEXTAREA"   -> entry=0x0FA20088 flags(bit1)=1
JKFrameTypeLookup: "LK_BACKDROP_NIL/TOOLTIP/INPUTBOX" -> 均命中
```

> ⚠️ 之前用 `LoadToc("UI\\FrameDef\\FrameDef.toc")` 是**错的路径**；框架自己的 `xlik.toc` 才是要载的那份。

---

## 四、GetGameUI

```
内置插件 FUN_10246610:  call game();  ecx=0; edx=0;  call [obj+0x24];  ret
我们:                    warcraft3::get_war3_searcher().get_gameui(0, 0)
```
实测返回非 0 的根控件指针（如 `0x28590088`）。

---

## 五、按 fdf tag 建控件 & 类型注册表机制

**注册表**（逆向 Game.dll 得到）：

| 项 | RVA | 说明 |
|---|---|---|
| frame 类型注册表对象 | `base+0xBB9CFC` | 哈希表 |
| 查表函数 | `base+0x6AEF0` | `entry = lookup(table, typeName)`，内部 `6F120694` 算哈希、`6F12070C` 比字符串 |
| frame 构造器 | `base+0x909C0` | `ctor(ECX=类型名, EDX=parent, 栈=(0,0,a5))`，`ret 0Ch` |

构造器一进去就查表，**查不到就返回 0**：

```
push ecx(类型名) → ecx=注册表 → call 查表
test ecx,ecx ; je → return 0
test byte [ecx+0x48],2 ; je → return 0
```

**关键结论**：注册表的键是 **fdf 条目名**（`LK_BACKDROP`、`CinematicPanel`、`Leaderboard`…），
**不是** `FRAME`/`BUTTON`/`TEXT` 这类基类型——实测这些基类型名一律 `entry=0`。
所以「必须先 `LoadToc` 载入包含该类型的 fdf，才能 `CreateFrame`」。

**实测**：`LoadToc` 之后

```
CreateFrameByTagName: type="LK_BACKDROP" name="JKApiFrame" parent=0x28590088 -> ok 0x30A4A050
CreateFrameByTagName: type="LK_TEXT"     name="JKApiText"  parent=0x00000000 -> ok 0x30B56940
```

---

## 六、框架侧的关键事实

- 框架实际调用的是 **`CreateFrameByTagName(frameType, name, parent, template, id)`**（`(SSISI)I`），
  **不是** `CreateFrame`。见 [xlik接入内置JAPI适配层方案.md](./xlik接入内置JAPI适配层方案.md)。
- fdf 来源：`exe/lib/embeds/lni/assets/UI/xlik.toc` → `xlik.fdf` / `slkc_fdf.fdf` / `xlik_overhead.fdf`
  （打包后位于地图内 `UI\xlik.toc`）。
- 运行时 [init.lua](../../exe/lib/embeds/lua/engine/init.lua#L17) 本就有 `japi.LoadToc("UI\\xlik.toc")`，
  但它内部走 `japi.DZ_LoadToc` → `japi.Exec("DzLoadToc", ...)`；**我们的插件没注册 `DzLoadToc`**，
  所以那条路径一直没生效（本次是靠显式 `japi.Exec("LoadToc", ...)` 打通的）。

---

## 七、未打通的部分（含原因）

| 部分 | 现象 | 原因 |
|---|---|---|
| `FrameSetSize` | ✅ **已打通**（视觉闭环，见第十节） | 尺寸单位是**屏幕比例**，见第十节 |
| `FrameSetPoint` | ✅ **已打通**（视觉闭环，见第十节） | `relFrame` 必须是 core 指针，见第十节 |
| `FrameSetAlpha` | ✅ **已打通**（视觉闭环，见第十节） | `this` 必须是**控件本体**（不是 core），见第十节 |
| `CreateFrameByTagName` 完整实现 | 只做了"建出对象" | ⚠️ 见下方「关于 `FUN_102492e0` 的重要修正」——它很可能**不是**框架 `CreateFrameByTagName` 的真正实现 |

### ⚠️ 已知问题：关窗口时崩溃（退出期链表摘除收到空节点）

**只发生在关闭游戏窗口时**，游戏内功能不受影响（本局能正常跑完）。

**现象**：关窗口弹 `FATAL ERROR!`（每局 Game.dll 基址不同，RVA 固定）：

```
Exception: 0xC0000005 (ACCESS_VIOLATION) at 0023:XXXXXXXX
The instruction at '0xXXXXXXXX' referenced memory at '0x00000008'.
```

**崩溃点**：`Game.dll + 0xA08A7`，落在函数 `+0xA08A0`（「把自己从双向链表摘除」）里：

```
0xA08A0: 55 8B EC         push ebp; mov ebp,esp
         56               push esi
         8B 75 08         mov esi,[ebp+8]        ; 节点指针
0xA08A7: 83 7E 08 00      cmp dword [esi+8],0    ; ← esi = NULL → 读 [8] 崩
         8B 7E 04 / 8B 4E 08 / 89 39 / 89 41 04 …   ; node->prev / node->next 摘除
```

**调用链**（VEH 转储调用栈 + 调用点反汇编确认）：

```
退出流程
 → 调用者 RVA 0x9EFB1：遍历一张「4 项全局注册表」（全局变量 RVA 0xBB9EA4 → 表指针）
       表项 12 字节：{ int=4, ptr, ptr }
 → 对某表项：call 0xA01D0（按 key 查哈希表；0xA01D0 = 字符串键哈希查找，bucket@this+0x1C、mask@this+0x24）
 → 返回 0（查不到）
 → call 0xA08A0（摘除）(arg = NULL) → 崩
```

**关键证据**：VEH 转储里「查找 key」的残留栈槽所指对象，头 4 字节是**控件 vtable（RVA 0x95AC3C）**
—— 即退出时这段代码确实在处理**我们创建的控件**，对它做一次「按名字的反查」，查不到就摘空节点。

**结论 / 缺的东西**：war3 退出时会清理一张 UI 注册表；我们创建的控件被它认领，但
**缺一条按名字的注册** —— 与第七节开头「`CreateFrameByTagName` 缺少创建后注册/挂接」是同一个坑。

**为什么暂时搁置**：继续定位需要解码那张 4 项注册表与 `0x95A6FC` 那个类，估计还要 2+ 轮游戏内验证，
收益仅为「关窗口不弹框」。等框架实际用起来后，若同类问题在**运行期**暴露，再带着真实用法回来收尾
（那时更容易知道要注册哪个名字）。

**复现与取证**：把 `FrameSetSize` + `FrameSetPoint` 作用到同一个控件，然后关窗口即稳定复现。
插件里已备好只读取证工具：`JKDumpSetters` / `JKDumpFrame` / `JKDumpMem` / `JKDumpCode` /
`JKDumpCallers` / `JKTrialSetPoint` / `JKTrialSetAlpha` / `JKProbeExitCrash`（VEH，转储崩溃现场）。

### 两个关键修复（让 SetSize 从"崩溃"变"成功"）

1. **`this` 必须是「控件 + 0xB4」，不是控件本身**
   依据是游戏自身的调用（创建 `CinematicPanel` 后）：
   ```
   6F34B3AA: call 6F0909C0        ; 构造器
   6F34B3BA: lea  ecx,[eax+0xB4]  ; ← this = 控件 + 0xB4
   6F34B3D4: call 6F0BD8A0        ; setPoint
   ```
   与插件 `FrameSetSize_a/Point_real` 里的 `LEA ESI,[frame+0xb4]` + `CMOVZ` 一致：
   若 `[frame+0xB4]` 是"可读指针"（正常控件）→ `this = frame+0xB4`；否则（simple 控件）→ `this = frame`。
   **之前传 `frame`**，`movss [ecx+0x58]` 就写到了 `frame+0x58`（错误位置）→ 写坏控件 → 崩。
2. **`R` 参数是指向实数的指针**（不是裸位模式）——见上一节。

**修复后实测**（`japi_replica.log`）：
```
resolve "ToolTipCost" -0x100 -> 0x6E6CD960  序言: 55 8B EC F3 0F 10
FrameSetSize: 准备调用 frame=0x3153A238 self=0x3153A2EC w=200.000 h=100.000
FrameSetSize: 完成
```
`self = frame + 0xB4` 成立、`w/h` 正确、无异常、游戏不崩。

### 关于 `FUN_102492e0` 的重要修正（下一步的关键）

对 `FUN_102492e0` 依赖的 8 个全局件做「交叉引用 → 反编译写入方」后，有两点结论：

**① 所有函数指针都是「可复刻」的** —— 它们全部由初始化函数 `FUN_1024e670` 用**同一套锚点+偏移**从 Game.dll 解析出来，没有外部注入：

| 全局 | 锚点字符串 / 来源 |
|---|---|
| `DAT_106e4ddc` | `(%s//%d) Error, unrecognized frametype %s!` |
| `DAT_106e4e04` | `(%s//%d) Error, frame %s cannot inherit from %s: conflicting types` |
| `DAT_106e4c38` | `FUN_10249200()` 结果 `+0x67` 处的 `convert_function` |
| `DAT_106e4de0` | 同上另一处（`FUN_10249200()` 结果 `+0x71`） |
| `DAT_106e4e00` | ` model preloaded` |
| `DAT_106e5e14` | `ResourceBarFrame` |

**② 但 `DAT_106e6158` 是插件自己的固定类型表** —— `FUN_1024e670` 末尾有：

```c
local_218[0..0x1f] = { 0x1064ce00, 0x1064cb80, ... , 0x1064cdac };   // 32 个固定字符串
for (i = 0; i < 0x20; i++) { *FUN_10254460(&DAT_106e6158, name[i]) = i; }   // map[name] = 0..31
```

循环前还插入了约 10 个 war3 现成控件名：`WORLDFRAME` / `PORTRAIT` / `MINIMAP` /
`TimeOfDayIndicator` / `TimeOfDayIndicatorTooltip` / `ResourceBarFrame` / `SimpleConsole` /
`SimpleTexture` / `SimpleString` / `SIMPLESTATUSBAR` / `SIMPLEFRAME`，
以及 32 个固定名中的一个已确认是 `SIMPLESTATUSBAR`。

**推论**：`FUN_102492e0` 处理的是**基类型控件**，并依赖插件自建的类型表。
即：`CreateFrameByTagName(frameType, name, parent, template, id)` 的正确语义是
**`frameType` = fdf 基类型**（`FRAME`/`BUTTON`/…，用于查 `DAT_106e6158` 拿索引），
**`template` = fdf 条目名**（如 `LK_BACKDROP`，交给创建函数实例化）——**两者不能混用**。

#### 已定位的 native 注册表（决定性证据）

注册表本体在 `FUN_102520f0` 内，格式为 `FUN_102ca4e0(函数地址, "名字", "签名")`。摘录：

| native | C 函数 | 签名 |
|---|---|---|
| `LoadToc` | `0x10248740` | `(S)V` |
| `CreateFrame` | `0x102483b0` | `(SII)I` |
| **`CreateFrameByTagName`** | **`0x10249740`** | `(SSISI)I` |
| `DestroyFrame` | `0x102491a0` | |
| `FrameSetSize` | `0x10247ed0` | `(IRR)V` |
| `FrameSetPoint` | `0x10248210` | `(IIIIRR)V` |
| `FrameSetAlpha` | `0x10248eb0` | `(II)V` |
| `FrameShow` | `0x10249050` | `(IB)V` |
| `FrameSetTexture` | `0x10248bd0` | `(ISI)V` |
| `FrameSetText` | `0x1024a4b0` | `(IS)V` |
| `FrameClearAllPoints` | `0x1024de00` | |
| `FrameFindByName` | `0x1024b2f0` | `(SI)I` |

即：此前假设的 `CreateFrameByTagName = FUN_10249740` **是正确**的。

#### `DAT_106e6158` 的 32 个基类型名（实测读出）

```
BASE, FRAME, CONTROL, BUTTON, SPRITE, MESSAGE, TEXT, BACKDROP,
TEXTBUTTON, CHECKBOX, EDITBOX, SLIDER, SCROLL, SCROLLBAR, RADIOGROUP,
LISTBOXITEM, LISTBOX, STATUSBAR, HIGHLIGHT, MODEL, DIALOG, MENU, POPUPMENU,
CHATDISPLAY, TEXTAREA, LISTBUTTON, SIMPLETOP, SIMPLEFRAME, SIMPLEGRID,
SIMPLEBUTTON, SIMPLECHECKBOX, SIMPLESTATUSBAR
```

> ⚠️ 注意：这些基类型名在 war3 自己的 frame 注册表（`base+0xBB9CFC`）里查不到
> （实测 `FRAME`/`BUTTON`/`TEXT` 全部 `entry=0`）——它们**只存在于插件自建的这张表**里。

#### 当前实现与插件的差异

我们的 `CreateFrameByTagName` 走 **Game.dll 的 fdf-tag 构造器**（认 fdf 条目名），
所以实现上取 `template` 作为构造类型；插件则走 `FUN_102492e0`（认基类型 + 插件表 + 模板）。
两者建出的对象**等价**，但插件路径包含额外的「创建后注册/挂接」——这正是 `FrameSetPoint` 仍然异常的原因。

**setter 的逆向结论（已验证正确，暂未启用）**：

共用锚点解析器 `FUN_10246540()` = `.text` 中引用字符串 **`"ToolTipCost"`** 的位置；
各 setter 由此位置减固定偏移得到一条 `E8`，取其目标即 war3 内部方法；
调用形态统一为 **`resolved(ECX=控件+0xB4, EDX=0, 栈=参数…)`**（见「两个关键修复」）。

| setter | 锚点 | 偏移(1.27a) | 目标函数 | 实际动作 |
|---|---|---|---|---|
| SetSize 宽 | `ToolTipCost` | `-0x100` | `base+0xBD960` | `movss [ecx+0x58], xmm0` |
| SetSize 高 | `ToolTipCost` | `-0x114` | `base+0xBD7C0` | `movss [ecx+0x5C], xmm0` |
| SetPoint | `ToolTipCost` | `-0x31` | `base+0xBD8A0` | — |
| SetAlpha | `RealmListContainer` | `-0x16` | （待验证） | — |

> 崩溃链：`setW/setH` 结尾 `jmp 0x6F0BD630`（改尺寸后的通知/重排）→ 遍历控件树 → 因控件未注册读到野指针。

### 另一个已修的坑：`R` 参数传的是**指针**

本环境下 japi 的 `R` 参数不是裸位模式，而是**指向实数的指针**（依据：插件 `FrameSetSize` 反汇编
`MOV EAX,[EBP+0xc]; MOV EAX,[EAX]`）。之前当成位模式，导致 `w=0.000`。已在
`natives.cpp` 的 `read_real()` 里按"能安全读则当指针、否则当位模式"处理。

---

## 八、当前实验开关（`projects/demo/scripts/process/start.lua`）

- **已启用**：`JKWar3Version`、`GetGameUI`、`CreateFrameByTagName`、`LoadToc`、`JKFrameTypeLookup`、
  `FrameSetSize`、`FrameSetPoint`、`FrameSetAlpha`

插件共注册 **25 个 native**（`japi_replica.log` 可见）。

---

## 九、构建 / 部署 / 日志

```powershell
# 构建（32 位）
cd vendor/japi-replica
& $cmake --build build --config Release

# 部署到运行时目录（关键：CMake 的插件输出目录不是运行时目录）
Copy-Item build/Release/japi_replica.dll vendor/WE.v4/plugin/warcraft3/japi_replica.dll -Force
```

- 插件日志：`vendor/WE.v4/plugin/warcraft3/japi_replica.log`
- Lua 打印落盘：`vendor/WE.v4/plugin/warcraft3/xlik_lua.log`

---

## 十、setter 三件套打通（SetSize / SetPoint / SetAlpha）

### 调用形态（已由机器码证实）

游戏自身在建完控件后设锚点的调用序列（RVA `0x34B3D4`，与我们完全一致）：

```
8D 88 B4 00 00 00   lea  ecx,[eax+0xB4]      ; this = 控件 + 0xB4
6A 07 56 6A 07      push 7; push esi; push 7  ; relPoint=7, relFrame=esi, point=7
E8 ...              call setPoint
```

setPoint（RVA `0xBD8A0`）的真实签名（反汇编解出）：

```
ecx        = this（控件 + 0xB4）
edx        = 未使用（函数内不读）
[ebp+0x08] = point      （0~8，见下「点序」）
[ebp+0x0C] = relFrame   ← 必须是 core 指针（控件 + 0xB4），不是原控件指针
[ebp+0x10] = relPoint
[ebp+0x14] = x          （float，屏幕比例）
[ebp+0x18] = y          （float，屏幕比例）
[ebp+0x1C] = 1
```

函数头关键指令：

```
8B 5D 08        mov  ebx,[ebp+8]        ; point
8B 74 9F 08     mov  esi,[edi+ebx*4+8]  ; 以 point 索引 this+8 起的 9 个「锚点槽」
...
8B 4D 0C        mov  ecx,[ebp+0xC]      ; relFrame → 作为内层调用的 this
8B 55 10        mov  edx,[ebp+0x10]     ; relPoint
```

### 三条关键事实（都是踩坑换来的）

1. **尺寸与偏移都是「屏幕比例」，不是像素。**
   框架侧证据：[library/class/ui/_ui.lua](../../library/class/ui/_ui.lua) 的注释
   `设置宽高尺寸[0-0.8,0-0.6]`；UI 套件里用的是 `width = 0.12` 这种量级
   （见 `vendor/assets/war3mapUI/ability_select/main.lua` 的 `relation(UI_ALIGN_CENTER, UIGame, UI_ALIGN_CENTER, 0, 0.2)`）。
   ⚠️ 我们曾误传 `FrameSetSize(f, 200, 100)` → 相当于 200 倍屏幕 → 控件被拉满全屏。

2. **点序 = 暴雪 `UI_ALIGN_*`（0~8）**，实测 `7 = BOTTOM`、`4 = CENTER` 均正确：

   ```
   0 左上   1 上   2 右上
   3 左     4 中   5 右
   6 左下   7 下   8 右下
   ```

3. **只有「有尺寸 + 有锚点」的控件才会被绘制。**
   只 `FrameSetSize`、不设锚点的控件不会被绘制——这解释了「单独 SetSize 看不出任何变化」。

### ⚠️ `this` 不是「一刀切」的 core —— SetAlpha 要的是控件本体

| setter | `this` | 依据 |
|---|---|---|
| `FrameSetSize` / `FrameSetPoint` | **控件 + 0xB4**（core） | 游戏自身调用序列 `lea ecx,[eax+0xB4]` |
| `FrameSetAlpha` | **控件本体** | `frame[+0xAC]=255`（默认不透明 alpha）而 `core[+0xAC]=24`；`this=控件本体` 试验返回 ok、`this=core` 抛异常 |

`FrameSetAlpha`（RVA `0x9CA50`）的真实签名（反汇编 + 实测）：

```
ecx        = this（控件本体）
edx        = 未使用
[ebp+0x08] = alpha     （按 bl 低字节使用，0~255；框架侧 _ui.lua 注释也写 [0-255]）
[ebp+0x0C] = 递归标志  （游戏自身传 0）
```

函数头关键指令：

```
8B 5D 08            mov  ebx,[ebp+8]          ; alpha
8B 7D 0C            mov  edi,[ebp+0xC]        ; 递归标志
38 9E AC 00 00 00   cmp  byte [esi+0xAC], bl   ; 与当前 alpha 比较（相同且不递归则早退）
88 9E AC 00 00 00   mov  [esi+0xAC], bl       ; 写 alpha
FF 90 A4 00 00 00   call [eax+0xA4]           ; 通知
```

⚠️ 两个坑：① 之前只压 1 个栈参 → `[ebp+0xC]` 读到栈上垃圾 → 崩；
② 补上第 2 个栈参后 `this` 还必须是**控件本体**才能通过（core 会在 `call [eax+0xA4]` 处异常）。

### 实测证据（`japi_replica.log` + 肉眼）

```
FrameSetSize: 准备调用 frame=0x312BA238 self=0x312BA2EC w=0.120 h=0.060
FrameSetSize: 完成
FrameSetPoint: 完成
FrameSetAlpha: frame=0x312BA420 alpha=100 fn=0x6E6ACA50      ← 无「调用异常」
```

肉眼（模板 `LK_BACKDROP_NIL`、尺寸 `0.12×0.06`）：
`FrameSetPoint(7, GameUI, 7)` → 屏幕**底部中央**出现小方块；
`FrameSetPoint(4, GameUI, 4)` → 出现在**屏幕正中央**；
对中央那个 `FrameSetAlpha(…, 100)` → 它明显比底部那个**淡**（底部保持默认 255）。
（`LK_BACKDROP_NIL` 的 `BackdropEdgeFile` 是 `PathTextures\4x4Unflyable.tga`（近乎纯白），
所以外观是「白色边框 + 中间半透明黑底」——正好同时证明 fdf 的边框层与背景层都被正确绘制。）

### ⚠️ 踩坑：不要用「故意传错参」的方式试探

`relFrame` 传原控件指针（而非 core）会**先写坏控件内部的 9 个锚点槽、然后才抛异常**；
被 SEH 拦下不代表没破坏，游戏会在之后某次清理时崩溃：

```
Exception: 0xC0000005 (ACCESS_VIOLATION) at 0x52D9D2D8
  referenced memory at 0x0000040C   （槽里的对象首 dword 被写成 0x400 → call [0x40C]）
```

该处是 RVA `0xBD280`（9 个锚点槽的清理/析构）里的 `call [eax+0xC]`。
**结论：参数试验只做「确定正确」的调用，不要再做破坏性试探。**

### 本次新增的诊断 native（均为复刻期的取证工具）

| native | 签名 | 用途 |
|---|---|---|
| `JKDumpSetters` | `()I` | 转储 4 个 setter 的函数头 + `.text` 里「游戏自身调用点」前的参数装配 |
| `JKDumpFrame` | `(I)I` | 转储控件本体 / core（控件 + 0xB4）内存，查锚点槽与 alpha 字段 |
| `JKTrialSetPoint` | `(IIII)I` | 试验性调 setPoint（指定 point / relFrame / relFrame 形态），返回是否抛异常 |
| `JKTrialSetAlpha` | `(III)I` | 试验性调 SetAlpha（指定 this 形态：core / 控件本体 / `[控件+0x1E8]`+0xB4） |
| `JKDumpCode` | `(II)I` | 按 RVA 转储任意 `.text` 机器码（崩溃弹窗绝对地址 − Game.dll 基址 = RVA） |

---

## 十一、下一步

1. **【进行中】框架侧接入**：按 [xlik接入内置JAPI适配层方案.md](./xlik接入内置JAPI适配层方案.md) 增加 `library/japi/wh.lua`
   与归一化 shim（注意框架的 toc 归一化名用 `japi.FrameLoadToc` 避开已占用的 `japi.LoadToc`）。
   setter 三件套已全通，接线后 `class/ui` 即可在内置 JAPI 上跑起来。
2. **【已搁置】关窗口崩溃**：见第七节「已知问题：关窗口时崩溃」。只影响退出，不影响游戏内；
   等框架实际用起来、在运行期暴露同类线索时再回来收尾（那时更容易知道要注册哪个名字）。
3. **其余 setter / 能力**：`FrameShow` / `FrameSetTexture` / `FrameSetText` / `FrameSetModel` /
   `FrameClearAllPoints` / `FrameFindByName` / `DestroyFrame` 等（native 注册表已定位，逐个照「锚点+偏移」解析；
   注意 `this` 需逐个用 `JKDumpFrame` 取证，不要假设都是 core）。
4. **`CreateFrameByTagName` 完整实现**（可选）：见第七节「关于 `FUN_102492e0` 的重要修正」——
   当前走 Game.dll 的 fdf 构造器已能满足框架用法。
