---
name: war3-mdx-texture-path
description: 通用编辑 mdx 模型 TEXS 贴图路径, 列出或改写任意旧路径到新路径, 支持按槽位/文件名替换、批量替换与结构校验. Use when the user asks to change, swap, list or fix a model texture path (贴图路径, TEXS, 换贴图).
---

# MDX 贴图路径编辑器

通用地把 mdx 模型里 `TEXS` 的贴图路径改成任意别的位置：单条改、全部改、跨文件批量按文件名替换，
并可顺手统一成本图的 `war3mapTextures\<文件名>.blp` 相对路径。改完自动校验 chunk 链。

脚本：[scripts/mdx_texture_path.py](scripts/mdx_texture_path.py)（纯 Python，无第三方依赖）。

## 结构前提

- MDX = `MDLX` 头 + 若干 `tag(4) + size(u32) + data`，**没有全局长度**，所以只改 260 字节的路径字段、不动长度，就不会破坏结构。
- `TEXS` 每条 **268 字节**：`replaceableId(u32) + path[260] + flags(u32)`；路径按字节计，NUL 结尾，上限 260 字节。
- `replaceableId != 0` 的条目是内置替换贴图（队伍色/水等），写路径无效，脚本一律跳过。
- 文本 `.mdl`（`Version { ... Bitmap { Image "路径" } }`）也支持：只替换 `Image "..."` 引号内的路径。
  mdl 的路径长度会变，所以脚本**按偏移倒序写**（否则后面条目偏移会失效、文件被改坏）。

## 用法

脚本的 4 个子命令，`--dry-run` 都能先看差异不落盘。

```bash
# 1. 看现状: chunk 链 + 每条 TEXS
python .trae/skills/war3-mdx-texture-path/scripts/mdx_texture_path.py list "vendor/assets/war3mapModel/特效/溅射.mdx"

# 2. 单条改: 按槽位号 / 旧文件名 / *(全部)
python .trae/skills/war3-mdx-texture-path/scripts/mdx_texture_path.py set "…/溅射.mdx" 0 "war3mapTextures\\Shockwave.blp"
python .trae/skills/war3-mdx-texture-path/scripts/mdx_texture_path.py set "…/溅射.mdx" "Shockwave.blp" "Textures\\Shockwave.blp"
python .trae/skills/war3-mdx-texture-path/scripts/mdx_texture_path.py set "…/某个模型.mdx" "*" "war3mapTextures\\Ghost.blp" --dry-run

# 3. 批量替换: 一批模型里所有引用某贴图的条目换掉
python .trae/skills/war3-mdx-texture-path/scripts/mdx_texture_path.py replace "old.blp" "war3mapTextures\\new.blp" "vendor/assets/war3mapModel/特效/*.mdx"

# 4. 便捷: 统一成本图贴图目录的相对路径(仅当该贴图确实存在时才改)
python .trae/skills/war3-mdx-texture-path/scripts/mdx_texture_path.py localize "vendor/assets/war3mapModel/**/*.mdx" --assets vendor/assets/war3mapTextures --dry-run
```

新路径可以是任意形式：`Textures\xxx.blp`、`war3mapTextures\xxx.blp`、`units\human\Footman\Footman.blp`，
也可以是另一个模型的贴图子目录。脚本只管字符串，不做路径存在性判断（`localize` 除外）。

## 什么时候不该改

- 引用 MPQ 原生贴图（`Textures\…`、`Abilities\…`）且地图没把它放进 `war3mapTextures` 时——保持原路径，引擎直接从 MPQ 读。
- `replaceableId != 0` 的条目。
- 只想要“换颜色/换形状”时：改路径只是换图，观感还取决于材质 `filterMode`（3=加色，黑底不发光）和动画（如骨骼 `KGSC` 缩放做扩散）。
- 动画、几何、材质结构的改写不归本技能，本技能只碰 `TEXS` 的 path 字段。

## 改完必须复核

1. 脚本保存后会自动重走 chunk 链（末尾必须正好等于文件长度）。
2. 重新打包 `xlik.exe run demo -l!`。
3. 产物核对：

```bash
Get-FileHash "vendor/assets/war3mapModel/特效/溅射.mdx", ".tmp/_local/demo/resource/war3mapModel/溅射.mdx" -Algorithm MD5
Test-Path ".tmp/_local/demo/resource/war3mapTextures/Shockwave.blp"
```

只有被打包流程收录的贴图才在包里；缺图要去资源/入口处补登记，光改模型路径没用。

## 坑

- 分隔符用单反斜杠 `\`（Lua 源码里写 `\\`），别写成 `/`。
- 长度按**字节**算，中文文件名会撑长；超长直接报错，不会静默截断。
- 路径必须 NUL 结尾，脚本会整段 260 字节重写（旧名残留一并清掉）。
- 同名不同图（不同子目录里的同名 blp）只能靠完整路径区分，批量 `replace` 是按**文件名**匹配的，混用时先 `list` 看清。
