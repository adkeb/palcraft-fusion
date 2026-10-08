#pragma once
#include <cstdint>

// Written in place through a shared handle. Readers accept only matching even
// sequence numbers; the producer marks the first sequence odd before copying.
// Mirrors Lua's <c8I8I8di8i8I4i4i4I4I4I4I8. Existing JSON remains available.
#pragma pack(push,1)
struct PalCraftInputSnapshot {
 char magic[8];
 uint64_t sequence;
 uint64_t tick_ms;
 double unix_time;
 int64_t mouse_x,mouse_y;
 uint32_t flags;
 int32_t forward,strafe;
 uint32_t generation;
 uint32_t viewport_width,viewport_height;
 uint64_t sequence_end;
};
#pragma pack(pop)
static_assert(sizeof(PalCraftInputSnapshot)==80);
enum PalCraftInputFlag : uint32_t {
 PalCraftMenu=1, PalCraftBuild=2, PalCraftFocus=4,
 PalCraftJump=8, PalCraftSneak=16, PalCraftSprint=32
};
