# xlik 沙箱 / kill 报错 排查手册

> 记录时间：2026-10-14　适用环境：Windows + Trae CN（含 sandbox 模块）
> 目的：下次再遇到 `xlik.exe kill` 报错、或 `run` 误报"War3启动失败"，照本文 5 分钟解决，不用重新推导。

---

## 0. TL;DR（先看这个）

| 项 | 内容 |
|---|---|
| **症状** | `xlik.exe kill` 报 `错误 exit status 128` / `exit status 1` + goroutine 堆栈；或 `xlik.exe run` 反复 `War3启动失败`（但实际有 war3 进程） |
| **根因** | **Trae CN 的沙箱给「工作区目录」打了「低完整性(Low)」标签**（带继承），导致工作区里所有 exe 被压到低完整性运行 → 看不到 / 杀不掉更高完整性的 `war3.exe` |
| **一条命令验证** | `icacls "<工作区目录>" \| findstr Mandatory` → 显示 `Low` 就是它 |
| **修复** | 见 §5，核心就两行 `icacls` + 用管理员运行 xlik |

---

## 1. 现象与错误码对照

| 退出码 | taskkill 原文 | 含义 | 说明 |
|---|---|---|---|
| `128` | `ERROR: The process "War3.exe" not found.` | **找不到进程** | xlik 完整性过低（Low），根本枚举不到 war3 |
| `1` | `ERROR: ... could not be terminated. Reason: Access is denied.` | **找到但杀不动** | 权限 / 完整性不足 |
| `0` | `SUCCESS: ... terminated.` | 正常 | 完整性足够 |

⚠️ **另一个也会报 `1` 的坑**：手工给 `kill.bat` 加调试时，若用 **LF 或带 BOM** 写回，cmd 会解析异常 → bat 直接返回 `1`。排查时注意区分"真拒绝访问"和"bat 被写坏"（见 §7）。

---

## 2. 调用链（为什么错误会是个"致命错误"）

```
exe/main.go  case "kill" → app.Kill()
exe/lib/kill.go  Kill()
    → exec.Command( <工作区>/vendor/WE.v4/bin/kill.bat ).Run()
vendor/WE.v4/bin/kill.bat
    → 末尾：taskkill /F /IM War3.exe > nul      ← 最后一条命令，没有 exit /B 0
```

关键点：

1. bat 的最后一条命令是 `taskkill`，且**没有显式 `exit /B 0`** → **taskkill 的退出码 = bat 的退出码 = xlik 看到的退出码**。
2. `Kill()` 对**任何非 0 退出码**都调用 `Panic()` → 打印错误 + `goroutine` 堆栈。
   → 所以"没有进程可关"这种**正常情况**（taskkill 返回 128）也会被当成致命错误报出来。

**连带症状（`run`）**：`exe/lib/run.go` 的 `runTest()` 用 `ExeRunningQty(["war3.exe"])` 判断是否启动成功。xlik 若处于低完整性，同样"看不见"自己刚拉起来的 war3 → 误判"War3启动失败" → 每秒重试，最终留下多个"启动失败"却实际在跑的 war3 进程（日志里 4 次"War3启动失败"就是这么来的）。

---

## 3. 必须知道的 3 个概念（一句话版）

1. **完整性级别（Integrity Level）**：`Low(0x1000) < Medium(0x2000) < High(0x3000)`。
   - 低级进程**枚举不到**（等于"看不见"）更高级别的进程；
   - 终止同级或更高级别，需要足够权限的令牌。
2. **文件/目录可带"完整性标签"**（Mandatory Label），可设为 `(OI)(CI)` 继承给子项 → 目录下所有文件都带同一标签。
3. **本机实测行为：文件标签会"压制"从该文件启动的进程级别**
   - 文件标 Low → 进程低完整性；文件标 Medium → **即使父进程是 High，子进程也会变成 Medium**；
   - **标签只能往下压，不能往上抬**。

> 由此推出让 xlik 跑 High 的两个必要条件：
> **(a)** `xlik.exe` 不带 Low/Medium 标签（或直接标为 High）；
> **(b)** 从**高权限（管理员）**环境启动它。

---

## 4. 根因详解：Trae CN 的沙箱

### 4.1 组件位置
```
d:\Program Files\Trae CN\resources\app\modules\sandbox\
    trae-sandbox.exe     sbox_sdk.dll     aiep_sbox.dll
    aiep_ipc.dll         aiep_vm.dll      run_helper.exe
```

### 4.2 它是怎么插进来的
AI/终端执行的命令会被它包裹起来（命令行实锤）：
```
trae-sandbox.exe exec --storage-path ... --config-name 6a465a7a... \
    --shell-path powershell.exe --command-line "..."
    env: TRAE_SANDBOX_SBX_ID=..., TRAE_SANDBOX_TRACE_FILE=..., SAFE_RM_DENIED_PATH=...
```

### 4.3 它对工作区目录做了什么
`icacls "d:\Lua\xlik-jade"` 原文（关键三行）：
```
Everyone:(CI)(DENY)(DC)                              ← 禁止删除子项
S-1-4-911837491-984510044:(OI)(CI)(W,D,DC)           ← 沙箱专用 SID 的写权限（非标准 SID）
Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)     ← 低完整性标签 + 继承  ★就是元凶
```
`xlik.exe` 因此继承了 Low：`Mandatory Label\Low Mandatory Level:(I)(NW)`

### 4.4 判定它是"按路径/标签"生效，而不是"只包 AI 进程"
对照实验（决定性）：

| 被启动的 exe | 位置 | 启动者 | 结果完整性 |
|---|---|---|---|
| 同一份 powershell 副本 | 工作区内 | **High 的计划任务**（非 Trae） | **Low** |
| 同一份 powershell 副本 | `%TEMP%` | 同一个 High 计划任务 | **High** |

→ 与"谁启动"无关，**只与文件所在路径的标签有关**。所以你也一样会遇到：直接开 cmd 也一样报错。

### 4.5 Trae 自己的说法（语言包原文）
- `"企业沙箱配置已更新，当前开发环境已启用企业统一沙箱保护。详情可前往「设置 > 对话流 > 自动运行」查看。"`
- `"这将允许可配置的命令子集在终端中自动运行。它提供*最大限度保护*，并假定代理没有恶意行为。"`

### 4.6 配置落点
`c:\Users\Administrator\.trae-cn\permission\global.json`
```json
"shellSandbox": { "enable": true, "onRestrict": "request_permission_retry_sandbox" },
"filesystem":   { "default": "read_only" }
```

---

## 5. 解决方案（按推荐顺序）

### 方案 A（推荐，最小改动）：恢复标签 + 让 xlik 跑 High
```powershell
# 1) 工作区目录恢复正常（去掉 Low 压制）
icacls "d:\Lua\xlik-jade" /setintegritylevel (OI)(CI)Medium

# 2) 让 xlik.exe 能跑 High（单独抬它，不影响其它文件）
icacls "d:\Lua\xlik-jade\xlik.exe" /setintegritylevel High
```
然后 **以管理员身份**运行 xlik（管理员 cmd/PowerShell）。实测：此时 xlik 以 High 运行，`taskkill` 能成功终止 war3（exit 0）。

> 注意：**普通（非管理员）启动仍只能到 Medium**，可能仍"拒绝访问"。要稳定工作，请用管理员方式运行。

### 方案 B：让 Trae 执行 xlik 时走"宿主机"（沙箱外）
编辑 `permission/global.json`：
```json
"rules": {
  "commandRules": {
    "xlik.exe":    { "approval": "allow", "execEnv": "host" },
    "xlik.exe *":  { "approval": "allow", "execEnv": "host" },
    "xlik *":      { "approval": "allow", "execEnv": "host" },
    "*xlik.exe *": { "approval": "allow", "execEnv": "host" }
  }
}
```
- key 是"命令模式"（Trae 约定 `"<命令> *"`，`*` 为通配）；
- `execEnv: "host"` = 宿主机（沙箱外）执行，`"sandbox"` = 走沙箱（默认）；
- 配置**实时生效**，无需重启。适合"让 AI / 内置终端帮你跑 xlik"的场景。
- 注意：此项**只对经 Trae 命令执行通道（agent/shellExec）的命令生效**；你自己手敲的、或外部 cmd 里的运行，仍受 §4 的目录标签影响 → 需要方案 A。

### 方案 C：从工作区外运行
把 `xlik.exe` 放到工作区**之外**，工作目录仍指向项目即可（已实测成功）：
```powershell
Copy-Item "D:\Lua\xlik-jade\xlik.exe" "C:\xlik\xlik.exe"
cd D:\Lua\xlik-jade ; C:\xlik\xlik.exe kill
```

### 方案 D：从根上关掉沙箱
Trae：**设置 → 对话流 → 自动运行**（或"权限与审批"）里调整/关闭沙箱。
- 若是**企业下发的"统一沙箱保护"**，个人开关可能是灰的 → 需找管理员。
- 或者：把项目放到**不被 Trae 当工作区**的目录（沙箱是打在工作区目录上的）。

---

## 6. 复发时的检查清单（照做即可）

1. `icacls "d:\Lua\xlik-jade" | findstr Mandatory` → 应为 **Medium**（若是 Low，跑方案 A 第 1 行）
2. `icacls "d:\Lua\xlik-jade\xlik.exe" | findstr Mandatory` → 应为 **High**（否则跑方案 A 第 2 行）
3. 用**管理员**终端运行 `xlik.exe kill`
4. 仍报 **128** → xlik 又被压低了（回到第 1 步重跑）
5. 报 **1** 且 taskkill 原文是 `Access is denied` → 权限不足（用管理员运行；确认标签是 High）
6. 报 **1** 且 bat 毫无输出 → 可能是 `kill.bat` 被写坏了（见 §7）

---

## 7. 附：诊断命令与坑

### 常用命令
```powershell
# 自己（当前进程）的完整性级别
whoami /groups | findstr S-1-16      # S-1-16-4096=Low / 8192=Medium / 12288=High

# 文件 / 目录的完整性标签
icacls "<路径>" | findstr Mandatory

# 某镜像名当前是否"可见"
tasklist /FI "IMAGENAME eq War3.exe"

# 手动终止（在 High/管理员上下文里可成功）
taskkill /F /IM War3.exe
```

### 读任意进程完整性级别（P/Invoke，按需）
```powershell
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class TokIL {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(int a, bool b, int p);
 [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, int a, out IntPtr t);
 [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr t, int c, IntPtr i, int l, out int r);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
 public static string Get(int pid){
   IntPtr ph=OpenProcess(0x1000,false,pid); if(ph==IntPtr.Zero) return "ERR"+Marshal.GetLastWin32Error();
   IntPtr th; if(!OpenProcessToken(ph,0x0008,out th)){CloseHandle(ph);return "ERR2 "+Marshal.GetLastWin32Error();}
   int len=0; GetTokenInformation(th,25,IntPtr.Zero,0,out len);
   IntPtr buf=Marshal.AllocHGlobal(len); string res="?";
   if(GetTokenInformation(th,25,buf,len,out len)){ IntPtr sid=Marshal.ReadIntPtr(buf); byte c=Marshal.ReadByte(sid,1); int last=Marshal.ReadInt32(sid,8+(c-1)*4);
     res= last==0x1000?"Low":(last==0x2000?"Medium":(last==0x3000?"High":("0x"+last.ToString("X")))); } else res="ERR3";
   Marshal.FreeHGlobal(buf); CloseHandle(th); CloseHandle(ph); return res; }
}
'@
[TokIL]::Get((Get-Process war3).Id)
```

### 排查时改 `kill.bat` 的坑 ★
- **必须用 ASCII + CRLF 写回**（不能有 BOM、不能用 LF），否则 cmd 解析异常 → bat 返回 `exit 1`，会污染结论（把"权限问题"误判成"bat 问题"或反之）。
- 插桩建议：在 bat 开头/分支处把 `whoami /groups`（看完整性）、`cacls` 的 errorlevel、`taskkill` 的真实输出重定向到固定文件；**排查完务必还原**（原始 33 行）。

### 原始 `kill.bat` 关键行（勿改坏）
```bat
:gotAdmin
if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
pushd "%CD%"
CD /D "%~dp0"

:MENU
taskkill /F /IM War3.exe > nul
```

---

## 8. 备注 / 教训

- `Kill()` 把**任何非 0 退出码**都当致命错误，粒度太粗：`128`（没有进程可关）本应是"正常"。可考虑改成"128/1 视为无进程可关"。**但这只消除误导信息，不解决沙箱降级问题。**
- 机制上，**"文件夹降级"不是 xlik 的 bug，也不是针对你**；是 Trae 沙箱按设计把"工作区（AI 可操作区域）"用操作系统级隔离圈起来，只是它同时把你一起罩进去了。
- 标签只能**往下压**：所以"管理员运行"必须配合"xlik.exe 是 High 标签"才有效。

### 相关文件
- [exe/main.go](../../exe/main.go)
- [exe/lib/kill.go](../../exe/lib/kill.go)（`Kill()` 的 `Panic`）
- [exe/lib/run.go](../../exe/lib/run.go)（`runTest` / `ExeRunningQty`）
- [vendor/WE.v4/bin/kill.bat](../../vendor/WE.v4/bin/kill.bat)
- `c:\Users\Administrator\.trae-cn\permission\global.json`（沙箱 profile / commandRules）
- `d:\Program Files\Trae CN\resources\app\modules\sandbox\`（沙箱组件）
