The fix uses the existing LoadAsset and UObject:IsValid/GetAddress APIs. No AddToRoot/RemoveFromRoot or unsupported flag mutation is called. Lua userdata tables are not claimed to be engine GC roots; the original component SetMaterial and MID texture parameter reference chain remains in place. Stop/abandon only release this Lua instance's cache references, and never destroy original assets or borrowed materials.

Official API: https://docs.ue4ss.com/dev/lua-api/classes/uobject.html
Pinned2281fa31 binding: https://github.com/UE4SS-RE/RE-UE4SS/blob/2281fa31/UE4SS/include/LuaType/LuaUObject.hpp

The pinned binding documents IsValid and flag queries, but has no Lua AddToRoot/RemoveFromRoot writer entry. The source therefore reacquires the same original parent through the supported loader immediately before creation and validates cached material/texture pairs rather than inventing a root-pinning capability.
