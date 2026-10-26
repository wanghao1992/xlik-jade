#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

typedef int (*japi_add_t)(unsigned addr, const char *name, const char *sig);

static void wlog(const char *fmt, ...)
{
    char buf[1024];
    char line[1200];
    va_list ap;
    HANDLE h;
    DWORD n;

    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    _snprintf(line, sizeof(line), "[pid=%lu] %s\r\n", (unsigned long)GetCurrentProcessId(), buf);

    h = CreateFileA("D:\\Lua\\xlik-jade\\.exp\\bridge_hit.txt",
                    FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                    NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) {
        WriteFile(h, line, (DWORD)strlen(line), &n, NULL);
        CloseHandle(h);
    }
}

static int readable(const void *p, size_t n)
{
    MEMORY_BASIC_INFORMATION mbi;
    if (!p) return 0;
    if (VirtualQuery(p, &mbi, sizeof(mbi)) != sizeof(mbi)) return 0;
    if (mbi.State != MEM_COMMIT) return 0;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return 0;
    return ((const char *)mbi.BaseAddress + mbi.RegionSize) >= ((const char *)p + n);
}

static float as_float(uint32_t v)
{
    union { uint32_t u; float f; } cv;
    cv.u = v;
    return cv.f;
}

typedef void *(__thiscall *fn_get_sprite)(void *self);

static void rotate_apply(void *frame, float deg, int axis)
{
    void *p, *sprite;
    float rad, s, c;
    float M[9], out[9];
    float *t;
    int i, j, k;

    p = *(void **)((char *)frame + 0x178);
    sprite = p ? *(void **)p : NULL;
    wlog("frame=%p f174=0x%08X p178=%p sprite=%p",
         frame, *(unsigned *)((char *)frame + 0x174), p, sprite);

    if (!sprite || !readable((char *)sprite + 0x108, 40)) {
        wlog("sprite unusable");
        return;
    }

    rad = deg * 3.141592653589793 / 180.0;
    s = sinf(rad);
    c = cosf(rad);

    if (axis == 0) {
        /* 标准 R_x：之前把 s/c 位置写反，导致角度 0 也会转 90 度 */
        float m0[9] = {1,0,0, 0,c,-s, 0,s,c};
        memcpy(M, m0, sizeof(M));
    } else if (axis == 1) {
        float m1[9] = {c,0,-s, 0,1,0, s,0,c};
        memcpy(M, m1, sizeof(M));
    } else {
        float m2[9] = {c,s,0, -s,c,0, 0,0,1};
        memcpy(M, m2, sizeof(M));
    }

    t = (float *)((char *)sprite + 0x108);
    wlog("before %.4f %.4f %.4f | %.4f %.4f %.4f | %.4f %.4f %.4f",
         t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8]);

    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) {
            float v = 0.0f;
            for (k = 0; k < 3; ++k) {
                v += M[k * 3 + i] * t[k * 3 + j];
            }
            out[i * 3 + j] = v;
        }
    }
    memcpy(t, out, sizeof(out));

    wlog("after  %.4f %.4f %.4f | %.4f %.4f %.4f | %.4f %.4f %.4f",
         t[0], t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8]);
}

/*
 * 参数编组未知，按三种可能依次判定：
 *   1) raw 是可读地址 -> 指向 float 的指针（原版内核就是对 arg 做解引用）
 *   2) raw 很小       -> 直接是整数度数
 *   3) 其余           -> float 位模式
 */
static float decode_angle(uint32_t raw)
{
    if (raw > 0x10000u && raw < 0x7FFFFFFFu && readable((void *)(uintptr_t)raw, 4)) {
        float f = *(float *)(uintptr_t)raw;
        if (f > -1.0e6f && f < 1.0e6f) {
            wlog("decode: raw=%p -> *float=%.4f", (void *)(uintptr_t)raw, f);
            return f;
        }
    }
    if (raw <= 100000u) {
        wlog("decode: raw=%u -> int deg", raw);
        return (float)raw;
    }
    wlog("decode: raw=0x%08X -> float bits %.4f", raw, as_float(raw));
    return as_float(raw);
}

typedef int (__cdecl *fn_frame_type)(void *obj);
typedef void *(__thiscall *fn_get_sprite_t)(void *self);
typedef void (__thiscall *fn_sprite_enable_t)(void *sprite);

static unsigned __cdecl F_Fix(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *sprite;
    void *model = NULL;

    if (!g || !readable(obj, 8)) {
        wlog("Fix bad frame=%p", obj);
        return 0;
    }

    sprite = ((fn_get_sprite_t)((char *)g + 0xa3300))(obj);
    wlog("Fix obj=%p sprite=%p", obj, sprite);

    if (sprite && readable(sprite, 0x24)) {
        model = *(void **)((char *)sprite + 0x20);
        wlog("Fix model=%p", model);
        ((fn_sprite_enable_t)((char *)g + 0x185450))(sprite);
        ((fn_sprite_enable_t)((char *)g + 0x185460))(sprite);
        wlog("Fix lights/particles enabled");
    }
    return 0;
}

typedef void *(__thiscall *fn_get_model)(void *self);

static unsigned __cdecl F_Model(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *model = NULL;
    unsigned vt = 0, rva = 0;

    if (!g || !readable(obj, 4)) {
        wlog("Model bad frame=%p", obj);
        return 0;
    }
    vt = *(unsigned *)obj;
    rva = (unsigned)((char *)(uintptr_t)vt - (char *)g);
    model = ((fn_get_model)((char *)g + 0xa4260))(obj);
    wlog("Model obj=%p vtRva=0x%X model=%p", obj, rva, model);
    return 0;
}

typedef void (__thiscall *fn_set_sprite_scale)(void *self, float scale);
typedef void (__thiscall *fn_set_team_color)(void *model, int color);
typedef void (__fastcall *fn_set_vertex_color)(void *self, int flag, uint32_t color);
typedef void (__fastcall *fn_get_vertex_color)(void *self, uint32_t *out);

static void *frame_sprite(void *frame)
{
    void *p = readable(frame, 0x180) ? *(void **)((char *)frame + 0x178) : NULL;
    return (p && readable(p, 4)) ? *(void **)p : NULL;
}

/* sprite 级顶点色：SpriteSetVertexColor(this, flag, color) */
static unsigned __cdecl F_VertexColor(unsigned frame, uint32_t color)
{
    void *sprite = frame_sprite((void *)(uintptr_t)frame);
    HMODULE g = GetModuleHandleA("game.dll");

    if (!g || !sprite || !readable(sprite, 4)) {
        wlog("VC bad frame=%p sprite=%p", (void *)(uintptr_t)frame, sprite);
        return 0;
    }
    ((fn_set_vertex_color)((char *)g + 0x186fc0))(sprite, 1, color);
    wlog("VC set sprite=%p color=0x%08X", sprite, color);
    return 0;
}

/* 读 sprite 级顶点色，用来判断是否被乘成 0 */
static unsigned __cdecl F_VCGet(unsigned frame)
{
    void *sprite = frame_sprite((void *)(uintptr_t)frame);
    HMODULE g = GetModuleHandleA("game.dll");
    uint32_t c = 0;

    if (!g || !sprite || !readable(sprite, 4)) {
        wlog("VCGet bad frame=%p sprite=%p", (void *)(uintptr_t)frame, sprite);
        return 0;
    }
    ((fn_get_vertex_color)((char *)g + 0x185a80))(sprite, &c);
    wlog("VCGet sprite=%p color=0x%08X", sprite, c);
    return (unsigned)c;
}

static unsigned __cdecl F_Color(unsigned frame, uint32_t color)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *sprite, *model;

    if (!g || !readable(obj, 8)) {
        wlog("Color bad frame=%p", obj);
        return 0;
    }
    sprite = ((fn_get_sprite_t)((char *)g + 0xa3300))(obj);
    if (!sprite || !readable(sprite, 0x24)) {
        wlog("Color no sprite");
        return 0;
    }
    model = *(void **)((char *)sprite + 0x20);
    wlog("Color sprite=%p model=%p color=%u", sprite, model, color);
    if (model) {
        ((fn_set_team_color)((char *)g + 0x6f2730))(model, (int)color);
        wlog("Color applied");
    }
    return 0;
}

/* CModelFrame 的队伍色：模型在 +0x170 的数组里（AddModel 路径）或 +0x178 的槽里（SetModel 路径）。
 * 取到 model 后调 ModelSetTeamColor(0x6f2730)，与 sprite 帧的 WhColor 等价。 */
static unsigned __cdecl F_ColorM(unsigned frame, uint32_t color)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *model = NULL;
    unsigned vt_rva = 0;

    if (!g || !readable(obj, 4)) {
        wlog("ColorM bad frame=%p", obj);
        return 0;
    }
    vt_rva = (unsigned)((char *)(uintptr_t)(*(unsigned *)obj) - (char *)g);
    if (vt_rva == 0x95AAE4u) {
        if (readable((char *)obj + 0x174, 4)) {
            unsigned cnt = *(unsigned *)((char *)obj + 0x16c);
            void *arr = *(void **)((char *)obj + 0x170);
            if (cnt > 0 && arr && readable(arr, 4)) {
                model = *(void **)arr;
            }
            if (!model) {
                void *slot = *(void **)((char *)obj + 0x178);
                if (slot && readable(slot, 4)) {
                    model = *(void **)slot;
                }
            }
        }
        wlog("ColorM CModelFrame count16c=%u model=%p color=%u",
             *(unsigned *)((char *)obj + 0x16c), model, color);
    } else {
        void *sprite = frame_sprite(obj);
        if (sprite && readable((char *)sprite + 0x24, 4)) {
            model = *(void **)((char *)sprite + 0x20);
        }
        wlog("ColorM other vtRva=0x%X model=%p color=%u", vt_rva, model, color);
    }
    if (model && readable((char *)model + 0xC0, 4)) {
        wlog("ColorM before: lights_b8=%u byte94=0x%02X",
             *(unsigned *)((char *)model + 0xb8),
             *(unsigned char *)((char *)model + 0x94));
        ((fn_set_team_color)((char *)g + 0x6f2730))(model, (int)color);
        wlog("ColorM applied");
    }
    return 0;
}

static unsigned __cdecl F_Scale2(unsigned frame, uint32_t scale)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    float s = decode_angle(scale);

    if (!g || !readable(obj, 0x1a4)) {
        wlog("Scale2 bad frame=%p", obj);
        return 0;
    }
    wlog("Scale2 before: 0x19c=%.6f 0x1a0=%u", *(float *)((char *)obj + 0x19c),
         *(unsigned *)((char *)obj + 0x1a0));
    ((fn_set_sprite_scale)((char *)g + 0xa3b40))(obj, s);
    wlog("Scale2 set=%.6f after: 0x19c=%.6f 0x1a0=%u", s,
         *(float *)((char *)obj + 0x19c), *(unsigned *)((char *)obj + 0x1a0));
    return 0;
}

static unsigned __cdecl F_Probe(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    HMODULE k = GetModuleHandleA("kkapi_local_plugin.dll");
    unsigned vt = 0, rva = 0;
    int type = -1;

    if (readable(obj, 4)) {
        vt = *(unsigned *)obj;
    }
    if (g && vt) {
        rva = (unsigned)((char *)(uintptr_t)vt - (char *)g);
    }
    if (k && readable(obj, 4)) {
        fn_frame_type fn = (fn_frame_type)((char *)k + 0x541a0);
        type = fn(obj);
    }
    wlog("Probe obj=%p vt=%p rva=0x%X type=%d", obj, (void *)(uintptr_t)vt, rva, type);
    return 0;
}

static void dump_block(const char *tag, void *base, uint32_t len)
{
    uint32_t i, j;
    char line[512];
    if (!base || !readable(base, len)) {
        wlog("%s dump skip base=%p len=0x%X", tag, base, len);
        return;
    }
    for (i = 0; i < len; i += 32) {
        int pos = _snprintf(line, sizeof(line), "%s+%03X:", tag, i);
        for (j = 0; j < 32 && i + j < len; j += 4) {
            pos += _snprintf(line + pos, sizeof(line) - pos, " %08X",
                             *(uint32_t *)((char *)base + i + j));
        }
        wlog("%s", line);
    }
}

/* 结构体转储：分辨 model/sprite 里的光照与材质字段 */
static unsigned __cdecl F_Dump(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *sprite = NULL;
    void *model = NULL;
    uint32_t i;
    uint32_t vt_rva = 0;

    if (g && readable(obj, 4)) {
        vt_rva = (uint32_t)((char *)(uintptr_t)(*(uint32_t *)obj) - (char *)g);
    }
    if (vt_rva == 0x95AAE4u) {
        /* CModelFrame：直接取模型 */
        model = ((fn_get_model)((char *)g + 0xa4260))(obj);
        wlog("Dump CModelFrame obj=%p vtRva=0x%X model=%p", obj, vt_rva, model);
    } else {
        sprite = frame_sprite(obj);
        if (sprite && readable((char *)sprite + 0x24, 4)) {
            model = *(void **)((char *)sprite + 0x20);
        }
        wlog("Dump frame=%p vtRva=0x%X sprite=%p model=%p", obj, vt_rva, sprite, model);
        dump_block("sprite", sprite, 0x1C0);
    }
    dump_block("model", model, 0x160);

    /* 进一步看 model 里像堆指针的字段指向的对象头部 */
    if (model && readable(model, 0x160)) {
        for (i = 0x80; i < 0x160; i += 4) {
            uint32_t p = *(uint32_t *)((char *)model + i);
            if (p > 0x01000000u && p < 0x7F000000u &&
                readable((void *)(uintptr_t)p, 0x40)) {
                dump_block("  modelptr", (void *)(uintptr_t)p, 0x40);
            }
        }
    }

    /* sprite 里疑似光源/渲染上下文的指针，逐个转储头部 */
    if (sprite && readable((char *)sprite + 0x40, 4)) {
        static const int offs[] = { 0x18, 0x1C, 0x28, 0x30, 0x34, 0x38, 0x3C };
        int k;
        for (k = 0; k < (int)(sizeof(offs) / sizeof(offs[0])); ++k) {
            uint32_t p = *(uint32_t *)((char *)sprite + offs[k]);
            if (p > 0x01000000u && p < 0x7F000000u &&
                readable((void *)(uintptr_t)p, 0x40)) {
                dump_block("  spriteptr", (void *)(uintptr_t)p, 0x60);
            }
        }
    }
    return 0;
}

/* 在进程内存里做大小写不敏感扫描，用来确认模型贴图是否真的被加载 */
static int mem_scan(const char *needle, uint32_t *hits, int maxhits)
{
    SYSTEM_INFO si;
    char *p, *end;
    int found = 0;
    size_t nlen = strlen(needle);

    GetSystemInfo(&si);
    p = (char *)si.lpMinimumApplicationAddress;
    end = (char *)si.lpMaximumApplicationAddress;

    while (p < end && found < maxhits) {
        MEMORY_BASIC_INFORMATION mbi;
        size_t i, size;
        char *base;

        if (VirtualQuery(p, &mbi, sizeof(mbi)) != sizeof(mbi)) break;
        base = (char *)mbi.BaseAddress;
        size = mbi.RegionSize;
        p = base + size;

        if (mbi.State != MEM_COMMIT) continue;
        if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD | PAGE_EXECUTE)) continue;
        if (!(mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY))) continue;

        for (i = 0; i + nlen <= size && found < maxhits; ++i) {
            size_t k;
            if ((base[i] | 0x20) != (needle[0] | 0x20)) continue;
            for (k = 1; k < nlen; ++k) {
                if ((base[i + k] | 0x20) != (needle[k] | 0x20)) break;
            }
            if (k == nlen) {
                hits[found++] = (uint32_t)(uintptr_t)(base + i);
            }
        }
    }
    return found;
}

static unsigned __cdecl F_Scan(unsigned unused)
{
    static const char *needles[] = { "footman.blp", "footman.mdl", ".blp", "grunt.blp" };
    uint32_t hits[4];
    int i;

    (void)unused;
    for (i = 0; i < 4; ++i) {
        int n = mem_scan(needles[i], hits, 4);
        int j;
        wlog("Scan '%s' count=%d", needles[i], n);
        for (j = 0; j < n; ++j) {
            wlog("  hit=%p", (void *)(uintptr_t)hits[j]);
        }
    }
    return 0;
}

/* 模型镜头的源/目标点：CModelFrame 的相机对象在 frame+0x140，
 * 源点写 +0x3C/+0x40/+0x44，目标点写 +0x64/+0x68/+0x6C */
static float dec_real(uint32_t raw)
{
    if (raw > 0x10000u && raw < 0x7FFFFFFFu && readable((void *)(uintptr_t)raw, 4)) {
        float f = *(float *)(uintptr_t)raw;
        if (f > -1.0e7f && f < 1.0e7f) {
            return f;
        }
    }
    return as_float(raw);
}

static unsigned __cdecl F_Cam(unsigned frame, uint32_t sx, uint32_t sy, uint32_t sz,
                              uint32_t tx, uint32_t ty, uint32_t tz)
{
    void *obj = (void *)(uintptr_t)frame;
    void *cam = NULL;

    if (readable((char *)obj + 0x144, 4)) {
        cam = *(void **)((char *)obj + 0x140);
    }
    wlog("Cam frame=%p cam=%p src=(%.1f,%.1f,%.1f) tgt=(%.1f,%.1f,%.1f)",
         obj, cam, dec_real(sx), dec_real(sy), dec_real(sz),
         dec_real(tx), dec_real(ty), dec_real(tz));
    if (!cam || !readable((char *)cam + 0x70, 4)) {
        wlog("Cam no camera object");
        return 0;
    }
    *(float *)((char *)cam + 0x3C) = dec_real(sx);
    *(float *)((char *)cam + 0x40) = dec_real(sy);
    *(float *)((char *)cam + 0x44) = dec_real(sz);
    *(float *)((char *)cam + 0x64) = dec_real(tx);
    *(float *)((char *)cam + 0x68) = dec_real(ty);
    *(float *)((char *)cam + 0x6C) = dec_real(tz);
    wlog("Cam applied: %p +3C=%.1f +40=%.1f +44=%.1f +64=%.1f +68=%.1f +6C=%.1f",
         cam, *(float *)((char *)cam + 0x3C), *(float *)((char *)cam + 0x40),
         *(float *)((char *)cam + 0x44), *(float *)((char *)cam + 0x64),
         *(float *)((char *)cam + 0x68), *(float *)((char *)cam + 0x6C));
    return 0;
}

/* 扫描堆里所有 CModelFrame / CSpriteFrame 实例，比较它们的 model 结构 */
static void report_frame(HMODULE g, void *obj, int *cm, int *sp)
{
    uint32_t vt = *(uint32_t *)obj;
    uint32_t rva = (uint32_t)((char *)(uintptr_t)vt - (char *)g);

    if (rva == 0x95AAE4u) {
        void *model = ((fn_get_model)((char *)g + 0xa4260))(obj);
        void *cam = readable((char *)obj + 0x144, 4) ?
                    *(void **)((char *)obj + 0x140) : NULL;
        wlog("FindFrames CModelFrame obj=%p model=%p cam=%p", obj, model, cam);
        if (model && *cm < 2) {
            dump_block("  cmmodel", model, 0x120);
            (*cm)++;
        }
        if (cam && readable(cam, 0x120) && *cm <= 3) {
            wlog("  nativeCam vtRva=0x%X",
                 (unsigned)((char *)(uintptr_t)(*(unsigned *)cam) - (char *)g));
            dump_block("  nativecam", cam, 0x120);
        }
    } else if (rva == 0x95A8A4u) {
        void *sprite = NULL, *model = NULL;
        if (readable((char *)obj + 0x17C, 4)) {
            void *q = *(void **)((char *)obj + 0x178);
            if (q && readable(q, 4)) sprite = *(void **)q;
        }
        if (sprite && readable((char *)sprite + 0x24, 4)) {
            model = *(void **)((char *)sprite + 0x20);
        }
        wlog("FindFrames SpriteFrame obj=%p sprite=%p model=%p", obj, sprite, model);
        if (model && *sp < 2) {
            dump_block("  spmodel", model, 0x120);
            (*sp)++;
        }
    }
}

/* 只在进程私有堆页里找帧对象（不碰代码段/只读段），用 ReadProcessMemory 避免越界 */
static unsigned __cdecl F_FindFrames(unsigned unused)
{
    HMODULE g = GetModuleHandleA("game.dll");
    SYSTEM_INFO si;
    char *p, *end;
    uint32_t want_cm, want_sp;
    int cm = 0, sp = 0;
    HANDLE me = GetCurrentProcess();
    char *buf;
    const size_t CHUNK = 0x80000;

    (void)unused;
    if (!g) return 0;
    want_cm = (uint32_t)(uintptr_t)g + 0x95AAE4u;
    want_sp = (uint32_t)(uintptr_t)g + 0x95A8A4u;
    wlog("FindFrames begin base=%p want_cm=0x%08X want_sp=0x%08X",
         (void *)g, want_cm, want_sp);

    buf = (char *)VirtualAlloc(NULL, CHUNK, MEM_COMMIT, PAGE_READWRITE);
    if (!buf) {
        wlog("FindFrames no buffer");
        return 0;
    }

    GetSystemInfo(&si);
    p = (char *)si.lpMinimumApplicationAddress;
    end = (char *)si.lpMaximumApplicationAddress;

    while (p < end) {
        MEMORY_BASIC_INFORMATION mbi;
        size_t size, off;
        char *base;

        if (VirtualQuery(p, &mbi, sizeof(mbi)) != sizeof(mbi)) break;
        base = (char *)mbi.BaseAddress;
        size = mbi.RegionSize;
        p = base + size;

        if (mbi.State != MEM_COMMIT) continue;
        if (mbi.Type != MEM_PRIVATE) continue;
        if (mbi.Protect != PAGE_READWRITE) continue;

        for (off = 0; off < size; off += CHUNK) {
            SIZE_T got = 0;
            size_t len = (size - off < CHUNK) ? (size - off) : CHUNK;
            size_t i;

            if (!ReadProcessMemory(me, base + off, buf, len, &got) || got < 4) {
                continue;
            }
            for (i = 0; i + 4 <= got; i += 4) {
                uint32_t v = *(uint32_t *)(buf + i);
                if (v == want_cm || v == want_sp) {
                    report_frame(g, (void *)(base + off + i), &cm, &sp);
                }
            }
        }
    }
    VirtualFree(buf, 0, MEM_RELEASE);
    wlog("FindFrames end cm=%d sp=%d", cm, sp);
    return 0;
}

/* 模型光照开关：走引擎自己的 0x1330e0(model, on) 入口（与 SpriteEnableLights 同一函数），
 * 不直接改结构体位，避免崩溃 */
typedef void (__thiscall *fn_model_lights_t)(void *model, int on);

static unsigned __cdecl F_Lights(unsigned frame, uint32_t on)
{
    void *sprite = frame_sprite((void *)(uintptr_t)frame);
    void *model = NULL;
    HMODULE g = GetModuleHandleA("game.dll");

    if (sprite && readable((char *)sprite + 0x24, 4)) {
        model = *(void **)((char *)sprite + 0x20);
    }
    if (!g || !model || !readable((char *)model + 0x98, 1)) {
        wlog("Lights bad frame=%p sprite=%p model=%p", (void *)(uintptr_t)frame, sprite, model);
        return 0;
    }
    wlog("Lights before model=%p on=%u byte94=0x%02X", model, on,
         *(unsigned char *)((char *)model + 0x94));
    ((fn_model_lights_t)((char *)g + 0x1330e0))(model, (int)on);
    wlog("Lights after byte94=0x%02X count_b8=%u", *(unsigned char *)((char *)model + 0x94),
         *(unsigned *)((char *)model + 0xb8));
    return 0;
}

/* 用引擎自己的光源构造函数造一个 CLight，只构造+转储，不挂载（先看默认结构） */
static unsigned __cdecl F_MakeLight(unsigned unused)
{
    HMODULE g = GetModuleHandleA("game.dll");
    void *L;

    (void)unused;
    if (!g) return 0;
    L = VirtualAlloc(NULL, 0x400, MEM_COMMIT, PAGE_READWRITE);
    if (!L) {
        wlog("MakeLight alloc fail");
        return 0;
    }
    /* 该构造函数只有 this 一个参数（内部自己 push 版本号），多传栈参会破坏栈 */
    ((void (__thiscall *)(void *))((char *)g + 0x830a00))(L);

    /* 构造函数只搭了轨道骨架，光照参数全 0；按 LITE 解析器 0x831740 的字段顺序补值。
     * 写的是我们自己 VirtualAlloc 的缓冲区，不触碰引擎内部结构。 */
    *(int *)((char *)L + 0xA4) = 2;      /* 光源类型：ambient */
    *(float *)((char *)L + 0xC0) = 1.0f;
    *(float *)((char *)L + 0xDC) = 1.0f;
    *(float *)((char *)L + 0x11C) = 1.0f;
    wlog("MakeLight light=%p", L);
    dump_block("  light", L, 0x180);
    return (unsigned)(uintptr_t)L;
}

/* 保守版挂接：只把引擎构造好的光源挂进 model 的光源数组，不猜测写任何字段。
 * 配套 WhDetachLight 用于换模型前摘除，避免引擎销毁模型时踩到我们的数组。 */
static unsigned __cdecl F_AttachLight(unsigned frame, uint32_t ptr)
{
    void *sprite = frame_sprite((void *)(uintptr_t)frame);
    void *model = NULL;
    void *L = (void *)(uintptr_t)ptr;
    void **arr;
    unsigned count;

    if (sprite && readable((char *)sprite + 0x24, 4)) {
        model = *(void **)((char *)sprite + 0x20);
    }
    if (!model || !readable((char *)model + 0xC0, 4)) {
        wlog("AttachLight bad model=%p frame=%p", model, (void *)(uintptr_t)frame);
        return 0;
    }
    if (!L || !readable(L, 0x178)) {
        wlog("AttachLight bad light=%p", L);
        return 0;
    }
    count = *(unsigned *)((char *)model + 0xb8);
    if (count != 0) {
        wlog("AttachLight model already has %u lights, skip", count);
        return 0;
    }

    arr = (void **)VirtualAlloc(NULL, 8, MEM_COMMIT, PAGE_READWRITE);
    if (!arr) {
        wlog("AttachLight array alloc fail");
        return 0;
    }
    arr[0] = L;
    arr[1] = NULL;
    *(void **)((char *)model + 0xbc) = arr;
    *(unsigned *)((char *)model + 0xb8) = 1;
    wlog("AttachLight model=%p light=%p array=%p count=%u byte94=0x%02X", model, L, arr,
         *(unsigned *)((char *)model + 0xb8), *(unsigned char *)((char *)model + 0x94));
    /* 回读光源字段，确认参数是否真的写进去了、有没有被引擎改写 */
    wlog("LightFields +A4=%d +C0=%.3f +DC=%.3f +F8=%.3f +FC=%.3f +100=%.3f +11C=%.3f",
         *(int *)((char *)L + 0xA4),
         *(float *)((char *)L + 0xC0), *(float *)((char *)L + 0xDC),
         *(float *)((char *)L + 0xF8), *(float *)((char *)L + 0xFC),
         *(float *)((char *)L + 0x100), *(float *)((char *)L + 0x11C));
    return 0;
}

static unsigned __cdecl F_DetachLight(unsigned frame)
{
    void *sprite = frame_sprite((void *)(uintptr_t)frame);
    void *model = NULL;

    if (sprite && readable((char *)sprite + 0x24, 4)) {
        model = *(void **)((char *)sprite + 0x20);
    }
    if (!model || !readable((char *)model + 0xC0, 4)) {
        wlog("DetachLight bad model=%p", model);
        return 0;
    }
    *(unsigned *)((char *)model + 0xb8) = 0;
    *(void **)((char *)model + 0xbc) = NULL;
    wlog("DetachLight model=%p cleared", model);
    return 0;
}

/* 直接调用引擎的 CModelFrame::AddModel（0xA3FA0）：this=模型帧，参数(path, 0)。
 * 原版内核的 UI 模型就是走这条“模型帧 + AddModel”的路，而不是 sprite 帧。 */
typedef void (__thiscall *fn_addmodel_t)(void *self, const char *path, int arg2);

static unsigned __cdecl F_AddModel(unsigned frame, const char *path)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");

    if (!g || !obj || !path) {
        wlog("AddModel bad frame=%p path=%p", obj, path);
        return 0;
    }
    wlog("AddModel frame=%p path=%s vtRva=0x%X", obj, path,
         (unsigned)((char *)(uintptr_t)(*(unsigned *)obj) - (char *)g));
    ((fn_addmodel_t)((char *)g + 0xA3FA0))(obj, path, 0);
    wlog("AddModel done");
    return 0;
}

/* 硬编码步兵路径的 AddModel：绕开 japi 字符串参数编组问题，仅用于实验 */
static unsigned __cdecl F_AddModelF(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");

    if (!g || !obj) {
        wlog("AddModelF bad frame=%p", obj);
        return 0;
    }
    wlog("AddModelF frame=%p vtRva=0x%X", obj,
         (unsigned)((char *)(uintptr_t)(*(unsigned *)obj) - (char *)g));
    ((fn_addmodel_t)((char *)g + 0xA3FA0))(obj, "units\\human\\footman\\footman.mdl", 0);
    wlog("AddModelF done count_16c=%u slot_178=%p",
         *(unsigned *)((char *)obj + 0x16c), *(void **)((char *)obj + 0x178));
    return 0;
}

/* 模型是否已设置：CModelFrame 看 +0x16c 数组计数和 +0x178 单模型槽，其他帧看 sprite+0x20 */
static unsigned __cdecl F_ModelCount(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    unsigned vt_rva = 0;

    if (!g || !readable(obj, 4)) {
        wlog("ModelCount bad frame=%p", obj);
        return 0;
    }
    vt_rva = (unsigned)((char *)(uintptr_t)(*(unsigned *)obj) - (char *)g);
    if (vt_rva == 0x95AAE4u) {
        unsigned cnt = readable((char *)obj + 0x170, 4) ? *(unsigned *)((char *)obj + 0x16c) : 0;
        void *slot = readable((char *)obj + 0x17C, 4) ? *(void **)((char *)obj + 0x178) : NULL;
        wlog("ModelCount CModelFrame count16c=%u slot178=%p", cnt, slot);
        return (cnt > 0 ? 1u : 0u) | (slot ? 2u : 0u);
    }
    {
        void *sprite = frame_sprite(obj);
        void *model = (sprite && readable((char *)sprite + 0x24, 4)) ?
                      *(void **)((char *)sprite + 0x20) : NULL;
        wlog("ModelCount other vtRva=0x%X sprite=%p model=%p", vt_rva, sprite, model);
        return model ? 1u : 0u;
    }
}

/* 取帧上的模型：CModelFrame 走 +0x170 数组 / +0x178 槽，其它帧走 sprite+0x20 */
static void *cmodel_from_frame(void *obj, HMODULE g)
{
    unsigned rva;

    if (!obj || !g || !readable(obj, 4)) {
        return NULL;
    }
    rva = (unsigned)((char *)(uintptr_t)(*(unsigned *)obj) - (char *)g);
    if (rva == 0x95AAE4u) {
        if (readable((char *)obj + 0x174, 4)) {
            unsigned cnt = *(unsigned *)((char *)obj + 0x16c);
            void *arr = *(void **)((char *)obj + 0x170);
            if (cnt > 0 && arr && readable(arr, 4)) {
                return *(void **)arr;
            }
            {
                void *slot = *(void **)((char *)obj + 0x178);
                if (slot && readable(slot, 4)) {
                    return *(void **)slot;
                }
            }
        }
        return NULL;
    }
    {
        void *sprite = frame_sprite(obj);
        return (sprite && readable((char *)sprite + 0x24, 4)) ?
               *(void **)((char *)sprite + 0x20) : NULL;
    }
}

/* 给 CModelFrame 的模型挂光源（WhMakeLight 造好的 CLight），验证模型帧渲染是否消费光源数组 */
static unsigned __cdecl F_AttachLightM(unsigned frame, uint32_t ptr)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *model = cmodel_from_frame(obj, g);
    void *L = (void *)(uintptr_t)ptr;
    void **arr;

    if (!model || !readable((char *)model + 0xC0, 4) || !L || !readable(L, 0x178)) {
        wlog("AttachLightM bad model=%p light=%p", model, L);
        return 0;
    }
    if (*(unsigned *)((char *)model + 0xb8) != 0) {
        wlog("AttachLightM model already has %u lights", *(unsigned *)((char *)model + 0xb8));
        return 0;
    }
    arr = (void **)VirtualAlloc(NULL, 8, MEM_COMMIT, PAGE_READWRITE);
    if (!arr) {
        wlog("AttachLightM alloc fail");
        return 0;
    }
    arr[0] = L;
    arr[1] = NULL;
    *(void **)((char *)model + 0xbc) = arr;
    *(unsigned *)((char *)model + 0xb8) = 1;
    wlog("AttachLightM model=%p light=%p count=%u byte94=0x%02X",
         model, L, *(unsigned *)((char *)model + 0xb8),
         *(unsigned char *)((char *)model + 0x94));
    return 0;
}


/* 光照上下文诊断：基类构造 0xA0B80 会读 frame+0x20（场景对象）的 +0x114，
 * 再通过 0xA26B0 写进 frame+0xb4 的子对象。UI 场景下该值若为 0，材质就会全黑。 */
typedef void (__thiscall *fn_sub_float_t)(void *self, float v);

static unsigned __cdecl F_LightCtx(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    void *scene;
    void *sub;

    if (!readable((char *)obj + 0x24, 4)) {
        wlog("LightCtx bad frame=%p", obj);
        return 0;
    }
    scene = *(void **)((char *)obj + 0x20);
    sub = (char *)obj + 0xb4;
    wlog("LightCtx frame=%p scene=%p sub=%p scene114=%s", obj, scene, sub,
         (scene && readable((char *)scene + 0x118, 4)) ? "readable" : "null");
    if (scene && readable((char *)scene + 0x118, 4)) {
        wlog("LightCtx scene+114=%.6f scene+110=%.6f",
             *(float *)((char *)scene + 0x114), *(float *)((char *)scene + 0x110));
        dump_block("  scene", scene, 0x100);
    }
    dump_block("  sub", sub, 0x80);
    return 0;
}

static unsigned __cdecl F_SetLit(unsigned frame, uint32_t value)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    float v = dec_real(value);

    if (!g || !readable((char *)obj + 0xb4, 4)) {
        wlog("SetLit bad frame=%p", obj);
        return 0;
    }
    wlog("SetLit sub=%p value=%.4f", (char *)obj + 0xb4, v);
    ((fn_sub_float_t)((char *)g + 0xA26B0))((char *)obj + 0xb4, v);
    wlog("SetLit done");
    return 0;
}


/* 复刻 whp_core FrameAddModel：new 0x264 + 头像帧构造 0x3835C0(this, parent)。
 * 这个类才是原生单位头像用的帧类型（vtable 0x9922FC），自带 sprite/相机/渲染上下文，
 * 能正常显示带材质和颜色的模型；返回帧指针，模型路径仍用 DZ_FrameSetModel 设置。 */
typedef void *(__thiscall *fn_portrait_ctor_t)(void *self, void *parent);
typedef void *(__cdecl *fn_new_t)(unsigned size, const char *file, int line, int flag);

static unsigned g_last_model_frame = 0;

static unsigned __cdecl F_AddModelFrame(unsigned parent)
{
    HMODULE g = GetModuleHandleA("game.dll");
    void *p = (void *)(uintptr_t)parent;
    void *obj;
    void *fr;

    if (!g || !p || !readable(p, 4)) {
        wlog("AddModelFrame bad parent=%p", p);
        return 0;
    }
    obj = ((fn_new_t)((char *)g + 0x120628))(0x264, "wh_bridge.cpp", 0, 0);
    if (!obj) {
        wlog("AddModelFrame alloc fail");
        return 0;
    }
    fr = ((fn_portrait_ctor_t)((char *)g + 0x3835C0))(obj, p);
    wlog("AddModelFrame parent=%p obj=%p ret=%p vtRva=0x%X", p, obj, fr,
         (unsigned)((char *)(uintptr_t)(*(unsigned *)fr) - (char *)g));
    {
        void *cam = readable((char *)fr + 0x144, 4) ? *(void **)((char *)fr + 0x140) : NULL;
        void *q = readable((char *)fr + 0x17C, 4) ? *(void **)((char *)fr + 0x178) : NULL;
        void *sp = (q && readable(q, 4)) ? *(void **)q : NULL;
        void *md = (sp && readable((char *)sp + 0x24, 4)) ? *(void **)((char *)sp + 0x20) : NULL;
        wlog("AddModelFrame cam=%p spriteSlot=%p sprite=%p model=%p", cam, q, sp, md);
        dump_block("  pfframe", fr, 0x120);
        if (sp) dump_block("  pfsprite", sp, 0x120);
        if (md) dump_block("  pfmodel", md, 0x140);
    }
    g_last_model_frame = (unsigned)(uintptr_t)fr;
    wlog("AddModelFrame saved last=%u", g_last_model_frame);
    return (unsigned)(uintptr_t)fr;
}

/* 取最近一次创建的头像帧指针（构造调用会中断 Lua 执行流，用 C 全局中转） */
static unsigned __cdecl F_LastFrame(unsigned unused)
{
    (void)unused;
    wlog("LastFrame=%u", g_last_model_frame);
    return g_last_model_frame;
}

/* 复刻原版内核的相机路线：
 *   HCAMERA 创建入口 0x18FAE0（operator new 0x170 + 构造 0x18F180）
 *   CModelFrame::SetCamera 0xA2570（内部对相机 AddRef，替换旧的并 Release）
 * 相机对象挂到 frame+0x140 后，WhCam 写的源点/目标点才会被渲染使用。 */
typedef void *(__cdecl *fn_new_camera_t)(void);
typedef void (__thiscall *fn_set_camera_t)(void *self, void *cam);
typedef void (__thiscall *fn_release_t)(void *obj);

static unsigned __cdecl F_NewCam(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *cam;
    void *before;

    if (!g || !readable((char *)obj + 0x144, 4)) {
        wlog("NewCam bad frame=%p", obj);
        return 0;
    }
    before = *(void **)((char *)obj + 0x140);
    wlog("NewCam frame=%p vtRva=0x%X oldcam=%p", obj,
         (unsigned)((char *)(uintptr_t)(*(unsigned *)obj) - (char *)g), before);

    cam = ((fn_new_camera_t)((char *)g + 0x18FAE0))();
    wlog("NewCam created cam=%p", cam);
    if (!cam) return 0;

    ((fn_set_camera_t)((char *)g + 0xA2570))(obj, cam);
    wlog("NewCam attached frame+140=%p ref=%u", *(void **)((char *)obj + 0x140),
         *(unsigned *)((char *)cam + 4));
    dump_block("  newcam", cam, 0x120);
    /* SetCamera 已为引擎持有一次引用，释放我们这次创建产生的引用 */
    ((fn_release_t)((char *)g + 0x4F1A0))(cam);
    return (unsigned)(uintptr_t)cam;
}

/* 复刻头像帧构造里的渲染/光照设置对象（0x1913B0 创建，0x18ED50/0x18EBA0/0x18EC20 配置，
 * 0xA12B0 挂到帧上）。头像帧正是靠它带颜色，把它挂到普通 CModelFrame 上试试。 */
/* 注意：这三个设置函数是 fastcall 风格——self 在 ECX、idx 在 EDX，其余在栈上。
 * 原实现写成 __thiscall，idx 被压栈而 EDX 为垃圾值，导致内部按 idx 索引时越界崩溃。 */
typedef void (__attribute__((fastcall)) *fn_setf_t)(void *self, int idx, float v);
typedef void (__attribute__((fastcall)) *fn_setv_t)(void *self, int idx, float *v);
typedef void (__attribute__((fastcall)) *fn_setv4_t)(void *self, int idx, float *v, int flag);
typedef void (__thiscall *fn_attach_t)(void *self, void *o, int flag);
typedef void *(__cdecl *fn_newlit_t)(void);

static unsigned __cdecl F_AttachLit(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *s;
    float v0[3] = {1.0f, 1.0f, 1.0f};
    float v1[3] = {1.0f, 1.0f, 1.0f};
    float v4[3] = {-1.0f, 0.8f, -1.0f};

    if (!g || !readable(obj, 4)) {
        wlog("AttachLit bad frame=%p", obj);
        return 0;
    }
    s = ((fn_newlit_t)((char *)g + 0x1913B0))();
    wlog("AttachLit settings=%p vtRva=0x%X", s,
         s ? (unsigned)((char *)(uintptr_t)(*(unsigned *)s) - (char *)g) : 0);
    if (!s) return 0;

    ((fn_setf_t)((char *)g + 0x18ED50))(s, 2, 0.33f);
    wlog("AttachLit set idx2");
    ((fn_setv_t)((char *)g + 0x18EBA0))(s, 0, v0);
    wlog("AttachLit set vec0");
    ((fn_setf_t)((char *)g + 0x18ED50))(s, 3, 1.0f);
    wlog("AttachLit set idx3");
    ((fn_setv_t)((char *)g + 0x18EBA0))(s, 1, v1);
    wlog("AttachLit set vec1");
    ((fn_setv4_t)((char *)g + 0x18EC20))(s, 4, v4, 0);
    wlog("AttachLit set vec4");

    ((fn_attach_t)((char *)g + 0xA12B0))(obj, s, 0);
    wlog("AttachLit attached ref=%u", *(unsigned *)((char *)s + 4));
    ((fn_release_t)((char *)g + 0x4F1A0))(s);
    wlog("AttachLit released");
    return 0;
}

static unsigned __cdecl F_CamInfo(unsigned frame)
{
    void *obj = (void *)(uintptr_t)frame;
    HMODULE g = GetModuleHandleA("game.dll");
    void *cam;

    if (!readable((char *)obj + 0x144, 4)) {
        wlog("CamInfo bad frame=%p", obj);
        return 0;
    }
    cam = *(void **)((char *)obj + 0x140);
    wlog("CamInfo frame=%p cam=%p", obj, cam);
    if (cam && readable(cam, 0x120)) {
        wlog("  cam vtRva=0x%X ref=%u src=(%.1f,%.1f,%.1f) tgt=(%.1f,%.1f,%.1f)",
             g ? (unsigned)((char *)(uintptr_t)(*(unsigned *)cam) - (char *)g) : 0,
             *(unsigned *)((char *)cam + 4),
             *(float *)((char *)cam + 0x3C), *(float *)((char *)cam + 0x40),
             *(float *)((char *)cam + 0x44), *(float *)((char *)cam + 0x64),
             *(float *)((char *)cam + 0x68), *(float *)((char *)cam + 0x6C));
        dump_block("  camdump", cam, 0x120);
    }
    return 0;
}

static unsigned __cdecl F_RotateX(unsigned frame, uint32_t angle)
{
    wlog("RotateX raw=0x%08X as_float=%.4f as_int=%u", angle, as_float(angle), angle);
    rotate_apply((void *)(uintptr_t)frame, decode_angle(angle), 0);
    return 0;
}

static unsigned __cdecl F_RotateY(unsigned frame, uint32_t angle)
{
    rotate_apply((void *)(uintptr_t)frame, decode_angle(angle), 1);
    return 0;
}

static unsigned __cdecl F_RotateZ(unsigned frame, uint32_t angle)
{
    rotate_apply((void *)(uintptr_t)frame, decode_angle(angle), 2);
    return 0;
}

/* 取本模块文件名(去扩展名)：用于验证加载器是否按文件名/扩展名筛选插件 */
static const char *module_stem(void)
{
    static char stem[128];
    char path[MAX_PATH];
    HMODULE h = NULL;
    char *base, *dot;
    DWORD n;

    if (stem[0] != 0) return stem;
    if (!GetModuleHandleExA(0x00000004 /*FROM_ADDRESS*/, (LPCSTR)&module_stem, &h) || !h) {
        return "yd_leak_monitor";
    }
    n = GetModuleFileNameA(h, path, MAX_PATH);
    if (n == 0) return "yd_leak_monitor";
    base = strrchr(path, '\\');
    base = base ? base + 1 : path;
    _snprintf(stem, sizeof(stem), "%s", base);
    dot = strrchr(stem, '.');
    if (dot) *dot = 0;
    return stem;
}

__declspec(dllexport) const char *PluginName(void)
{
    /* 实验：声明自己所在的文件名，验证 yd_loader 是否接受新文件名（不覆盖原版插件） */
    return module_stem();
}

__declspec(dllexport) int Initialize(void)
{
    HMODULE y = GetModuleHandleA("ydbase.dll");
    japi_add_t add;
    char self[MAX_PATH];

    {
        HMODULE hm = NULL;
        if (GetModuleHandleExA(0x00000004, (LPCSTR)&Initialize, &hm) && hm
            && GetModuleFileNameA(hm, self, MAX_PATH)) {
            wlog("loaded module=%s stem=%s", self, module_stem());
        } else {
            wlog("loaded module=<unknown> stem=%s", module_stem());
        }
    }
    y = GetModuleHandleA("ydbase.dll");

    if (!y) {
        y = LoadLibraryA("ydbase.dll");
    }
    if (!y) {
        wlog("ydbase missing");
        return 0;
    }

    add = (japi_add_t)GetProcAddress(y, "?japi_add@jass@warcraft3@base@@YA_NIPBD0@Z");
    if (!add) {
        wlog("japi_add missing");
        return 0;
    }

    wlog("game=%p", (void *)GetModuleHandleA("game.dll"));
    wlog("reg rotateX=%d", add((unsigned)(uintptr_t)&F_RotateX, "FrameSetModelRotateX", "(IR)V"));
    wlog("reg rotateY=%d", add((unsigned)(uintptr_t)&F_RotateY, "FrameSetModelRotateY", "(IR)V"));
    wlog("reg rotateZ=%d", add((unsigned)(uintptr_t)&F_RotateZ, "FrameSetModelRotateZ", "(IR)V"));
    wlog("reg probe=%d", add((unsigned)(uintptr_t)&F_Probe, "WhProbe", "(I)I"));
    wlog("reg fix=%d", add((unsigned)(uintptr_t)&F_Fix, "WhFix", "(I)I"));
    wlog("reg scale=%d", add((unsigned)(uintptr_t)&F_Scale2, "WhScale", "(IR)V"));
    wlog("reg color=%d", add((unsigned)(uintptr_t)&F_Color, "WhColor", "(II)V"));
    wlog("reg model=%d", add((unsigned)(uintptr_t)&F_Model, "WhModel", "(I)I"));
    wlog("reg vc=%d", add((unsigned)(uintptr_t)&F_VertexColor, "WhVC", "(II)V"));
    wlog("reg vcget=%d", add((unsigned)(uintptr_t)&F_VCGet, "WhVCGet", "(I)I"));
    wlog("reg dump=%d", add((unsigned)(uintptr_t)&F_Dump, "WhDump", "(I)I"));
    wlog("reg scan=%d", add((unsigned)(uintptr_t)&F_Scan, "WhScan", "(I)I"));
    wlog("reg cam=%d", add((unsigned)(uintptr_t)&F_Cam, "WhCam", "(IRRRRRR)V"));
    wlog("reg findframes=%d", add((unsigned)(uintptr_t)&F_FindFrames, "WhFindFrames", "(I)I"));
    wlog("reg lights=%d", add((unsigned)(uintptr_t)&F_Lights, "WhLights", "(II)V"));
    wlog("reg makelight=%d", add((unsigned)(uintptr_t)&F_MakeLight, "WhMakeLight", "(I)I"));
    wlog("reg attachlight=%d", add((unsigned)(uintptr_t)&F_AttachLight, "WhAttachLight", "(II)V"));
    wlog("reg detachlight=%d", add((unsigned)(uintptr_t)&F_DetachLight, "WhDetachLight", "(I)V"));
    wlog("reg addmodel=%d", add((unsigned)(uintptr_t)&F_AddModel, "WhAddModel", "(IS)V"));
    wlog("reg addmodelf=%d", add((unsigned)(uintptr_t)&F_AddModelF, "WhAddModelF", "(I)I"));
    wlog("reg modelcount=%d", add((unsigned)(uintptr_t)&F_ModelCount, "WhModelCount", "(I)I"));
    wlog("reg colorm=%d", add((unsigned)(uintptr_t)&F_ColorM, "WhColorM", "(II)V"));
    wlog("reg attachlightm=%d", add((unsigned)(uintptr_t)&F_AttachLightM, "WhAttachLightM", "(II)V"));
    wlog("reg lightctx=%d", add((unsigned)(uintptr_t)&F_LightCtx, "WhLightCtx", "(I)I"));
    wlog("reg setlit=%d", add((unsigned)(uintptr_t)&F_SetLit, "WhSetLit", "(IR)V"));
    wlog("reg addmodelframe=%d", add((unsigned)(uintptr_t)&F_AddModelFrame, "WhAddModelFrame", "(I)I"));
    wlog("reg lastframe=%d", add((unsigned)(uintptr_t)&F_LastFrame, "WhLastFrame", "(I)I"));
    wlog("reg attachlit=%d", add((unsigned)(uintptr_t)&F_AttachLit, "WhAttachLit", "(I)V"));
    wlog("reg newcam=%d", add((unsigned)(uintptr_t)&F_NewCam, "WhNewCam", "(I)I"));
    wlog("reg caminfo=%d", add((unsigned)(uintptr_t)&F_CamInfo, "WhCamInfo", "(I)I"));
    return 0;
}

__declspec(dllexport) void SetAllowDll(int allow) { (void)allow; }
__declspec(dllexport) void SetWindow(void *window) { (void)window; }



