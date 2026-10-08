#include "compositor.h"
#include <windows.h>
#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <vector>
#include <reshade.hpp>

using namespace reshade::api;

namespace {
effect_uniform_variable uniform(effect_runtime *runtime, const char *name) {
#if defined(__GNUC__) && !defined(_MSC_VER)
    // ReShade's MSVC eight-byte handle return uses a hidden result pointer;
    // Windows GNU virtual-member return uses RAX. Adapt only this SDK slot.
    auto method = &effect_runtime::find_uniform_variable;
    struct Member { intptr_t entry, adjustment; } member{};
    static_assert(sizeof(method) == sizeof(member));
    std::memcpy(&member, &method, sizeof(member));
    auto *self = reinterpret_cast<uint8_t *>(runtime) + member.adjustment;
    auto **table = *reinterpret_cast<void ***>(self);
    using Call = void *(*)(void *, effect_uniform_variable *, const char *, const char *);
    effect_uniform_variable result{};
    reinterpret_cast<Call>(table[(member.entry - 1) / sizeof(void *)])(self, &result, "MCPassthrough.fx", name);
    return result;
#else
    return runtime->find_uniform_variable("MCPassthrough.fx", name);
#endif
}
constexpr uint32_t kMagic = 0x5450434D, kMaxW = 3840, kMaxH = 2160;
constexpr size_t kHeader = 4096, kDesc = 256, kDescSize = 128;
constexpr uint64_t kMaxAgeMs = 250;
std::atomic<bool> g_registered{false}, g_active{false};
std::atomic<uint32_t> g_bbWidth{0}, g_bbHeight{0};
HANDLE g_mapping = nullptr, g_producer = nullptr;
const uint8_t *g_view = nullptr;
size_t g_mappedSize = 0;
int32_t g_slots = 0, g_pid = 0;
int64_t g_stride = 0, g_lastPublish = -1, g_lastFrame = 0;
int32_t g_seenPid = 0;
int64_t g_seenPublication = -1;
uint64_t g_nextOpen = 0, g_lastFresh = 0, g_lastCheck = 0;
resource g_texture{0};
resource_view g_overlay{0};
uint32_t g_width = 0, g_height = 0, g_flags = 2, g_state = 1;
bool g_hasFrame = false, g_wasFocused = false;
std::vector<uint8_t> g_pixels;

template <typename T> T read(const uint8_t *p) {
    T value;
    std::memcpy(&value, p, sizeof(value));
    return value;
}
uint64_t epoch_ms() {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER v;
    v.LowPart = ft.dwLowDateTime; v.HighPart = ft.dwHighDateTime;
    return v.QuadPart / 10000 - 11644473600000ULL;
}
void close_mapping() {
    if (g_view) UnmapViewOfFile(g_view);
    if (g_mapping) CloseHandle(g_mapping);
    if (g_producer) CloseHandle(g_producer);
    g_view = nullptr; g_mapping = g_producer = nullptr;
    g_mappedSize = 0; g_pid = 0; g_lastPublish = -1; g_lastFrame = 0;
    g_hasFrame = false;
}
bool open_mapping() {
    if (g_view) return true;
    const auto now = GetTickCount64();
    if (now < g_nextOpen) return false;
    g_nextOpen = now + 500;
    wchar_t name[256] = L"Local\\MCPassthroughFrame";
    wchar_t configured[256]{};
    if (GetEnvironmentVariableW(L"PALCRAFT_FRAME_NAME", configured, 256) > 0)
        wcscpy_s(name, 256, configured);
    g_mapping = OpenFileMappingW(FILE_MAP_READ, FALSE, name);
    if (!g_mapping) return false;
    g_view = static_cast<const uint8_t *>(MapViewOfFile(g_mapping, FILE_MAP_READ, 0, 0, 0));
    MEMORY_BASIC_INFORMATION info{};
    if (!g_view || !VirtualQuery(g_view, &info, sizeof(info)) || info.RegionSize < kHeader) {
        close_mapping(); return false;
    }
    g_mappedSize = info.RegionSize;
    g_slots = read<int32_t>(g_view + 12);
    g_stride = read<int64_t>(g_view + 16);
    if (read<uint32_t>(g_view) != kMagic || read<int32_t>(g_view + 4) != 1 ||
        read<int32_t>(g_view + 8) != kHeader || g_slots < 1 || g_slots > 8 ||
        g_stride <= 0 || g_stride > int64_t(kMaxW) * kMaxH * 12 ||
        kHeader + size_t(g_stride) * g_slots > g_mappedSize) {
        close_mapping(); return false;
    }
    g_lastCheck = now;
    reshade::log::message(reshade::log::level::info, "PalCraft: HUD-only shared memory connected");
    return true;
}
bool producer_alive(int32_t pid) {
    if (pid != g_pid) {
        if (g_producer) CloseHandle(g_producer);
        g_producer = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, DWORD(pid));
        g_pid = pid; g_lastPublish = -1; g_lastFrame = 0; g_hasFrame = false;
    }
    DWORD code = 0;
    return g_producer && GetExitCodeProcess(g_producer, &code) && code == STILL_ACTIVE;
}
void destroy_texture(device *dev) {
    if (g_overlay.handle) dev->destroy_resource_view(g_overlay);
    if (g_texture.handle) dev->destroy_resource(g_texture);
    g_overlay = resource_view{0}; g_texture = resource{0};
    g_width = g_height = 0; g_hasFrame = false;
}
void bind(effect_runtime *runtime) {
    runtime->update_texture_bindings("MCOVERLAY", g_overlay, g_overlay);
}
void upload(effect_runtime *runtime) {
    const auto now = GetTickCount64();
    const int32_t pid = read<int32_t>(g_view + 44);
    if (!producer_alive(pid)) { close_mapping(); return; }
    const int64_t publication = read<int64_t>(g_view + 32);
    if (publication == g_lastPublish || (pid == g_seenPid && publication == g_seenPublication)) {
        if (now - g_lastFresh > kMaxAgeMs) g_hasFrame = false;
        if (now - g_lastCheck > 2000) { close_mapping(); g_lastCheck = now; }
        return;
    }
    const int32_t slot = read<int32_t>(g_view + 40);
    if (slot < 0 || slot >= g_slots) return;
    const uint8_t *desc = g_view + kDesc + kDescSize * slot;
    uint8_t snapshot[kDescSize];
    std::memcpy(snapshot, desc, sizeof(snapshot));
    const int64_t seq = read<int64_t>(snapshot), frame = read<int64_t>(snapshot + 8);
    if (seq <= 0 || (seq & 1) || frame <= g_lastFrame) return;
    const uint32_t w = read<uint32_t>(snapshot + 24), h = read<uint32_t>(snapshot + 28);
    if (!w || w > kMaxW || !h || h > kMaxH) return;
    const size_t layer = size_t(w) * h * 4;
    if (layer * 3 > size_t(g_stride)) return;
    const uint32_t flags = read<uint32_t>(snapshot + 44);
    if (flags & 8) {
        const auto capture = read<uint64_t>(snapshot + 104), publish = read<uint64_t>(snapshot + 112), wall = epoch_ms();
        if (!capture || publish < capture || capture > wall + 1000 || wall > capture + kMaxAgeMs) {
            g_hasFrame = false; return;
        }
    }
    const uint8_t *base = g_view + kHeader + size_t(g_stride) * slot + 2 * layer;
    g_pixels.resize(layer);
    std::memcpy(g_pixels.data(), base, layer);
    // Validate before touching the GPU: a torn slot never overwrites the visible texture.
    std::atomic_thread_fence(std::memory_order_acquire);
    if (read<int64_t>(desc) != seq || read<int64_t>(g_view + 32) != publication ||
        read<int32_t>(g_view + 44) != pid || read<int32_t>(g_view + 40) != slot) return;
    device *dev = runtime->get_device();
    if (w != g_width || h != g_height) {
        destroy_texture(dev);
        if (!dev->create_resource(resource_desc(w, h, 1, 1, format::r8g8b8a8_unorm, 1,
                memory_heap::default_, resource_usage::shader_resource | resource_usage::copy_dest),
                nullptr, resource_usage::shader_resource, &g_texture) ||
            !dev->create_resource_view(g_texture, resource_usage::shader_resource,
                resource_view_desc(format::r8g8b8a8_unorm), &g_overlay)) {
            destroy_texture(dev); return;
        }
        g_width = w; g_height = h; bind(runtime);
    }
    subresource_data data{};
    data.data = g_pixels.data(); data.row_pitch = w * 4; data.slice_pitch = uint32_t(layer);
    dev->update_texture_region(data, g_texture, 0);
    g_lastPublish = publication; g_lastFrame = frame; g_flags = flags;
    g_seenPid = pid; g_seenPublication = publication;
    g_state = flags & 8 ? read<uint32_t>(snapshot + 120) : 1;
    g_lastFresh = g_lastCheck = now;
    g_hasFrame = true;
}
void on_begin_effects(effect_runtime *runtime, command_list *, resource_view, resource_view) {
    // Force this each frame, even after preset reload. The shader has no world pass.
    if (auto v = uniform(runtime, "NativeBlocks"); v.handle) runtime->set_uniform_value_bool(v, true);
    DWORD foregroundPid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &foregroundPid);
    const bool focused = foregroundPid == GetCurrentProcessId();
    if (focused != g_wasFocused) {
        g_wasFocused = focused; g_hasFrame = false;
        // Require a new publication after returning from Alt-Tab.
        if (g_view) g_lastPublish = read<int64_t>(g_view + 32);
    }
    // Keep exporter dimensions separate from the host backbuffer.
    uint32_t bw = 0, bh = 0;
    runtime->get_screenshot_width_and_height(&bw, &bh);
    g_bbWidth = bw; g_bbHeight = bh;
    if (g_active && focused && open_mapping()) upload(runtime);
    const bool on = g_active && focused && g_hasFrame && (g_state & 1) &&
                    GetTickCount64() - g_lastFresh <= kMaxAgeMs;
    if (auto v = uniform(runtime, "McActive"); v.handle) runtime->set_uniform_value_bool(v, on);
    if (auto v = uniform(runtime, "RowsBottomUp"); v.handle) runtime->set_uniform_value_bool(v, (g_flags & 2) != 0);
}
void on_reloaded_effects(effect_runtime *runtime) { if (g_overlay.handle) bind(runtime); }
void on_destroy_effect_runtime(effect_runtime *runtime) {
    destroy_texture(runtime->get_device()); close_mapping(); g_pixels.clear();
}
void on_present(effect_runtime *runtime) {
    static uint64_t next = 0;
    static FILETIME last{};
    static wchar_t path[MAX_PATH]{};
    const auto now = GetTickCount64();
    if (now < next) return;
    next = now + 1000;
    if (!path[0]) {
        GetModuleFileNameW(nullptr, path, MAX_PATH);
        if (wchar_t *slash = wcsrchr(path, L'\\'))
            wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - path), L"reshade-shaders\\Shaders\\MCPassthrough.fx");
    }
    WIN32_FILE_ATTRIBUTE_DATA info;
    if (GetFileAttributesExW(path, GetFileExInfoStandard, &info)) {
        if ((last.dwLowDateTime || last.dwHighDateTime) && CompareFileTime(&info.ftLastWriteTime, &last) != 0)
            runtime->reload_effect_next_frame("MCPassthrough.fx");
        last = info.ftLastWriteTime;
    }
}
} // namespace

namespace compositor {
bool try_register(void *module) {
    if (g_registered) return true;
    if (!reshade::register_addon(module)) return false;
    reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
    reshade::register_event<reshade::addon_event::reshade_present>(on_present);
    reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(on_reloaded_effects);
    reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_effect_runtime);
    g_registered = true;
    reshade::log::message(reshade::log::level::info, "PalCraft: registered single-pass HUD compositor");
    return true;
}
void unregister(void *module) { if (g_registered.exchange(false)) reshade::unregister_addon(module); close_mapping(); }
void set_active(bool active) { g_active = active; }
void backbuffer_size(int &width, int &height) { width = int(g_bbWidth.load()); height = int(g_bbHeight.load()); }
// ABI-compatible legacy entry points. Pal's native renderer owns camera/world
// effects; HUD and original hand animation must remain in screen space.
void set_host_planes(float, float) {}
void set_camera_locked(bool) {}
void set_screen_fx(float, float, float, float) {}
void set_look(float, float, float) {}
void set_host_pose(float, float, float, float, double, double, double) {}
void set_pose_lag(int) {}
} // namespace compositor
