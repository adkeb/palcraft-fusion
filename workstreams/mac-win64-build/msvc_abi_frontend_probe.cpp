static_assert(sizeof(void*) == 8, "Win64 pointers required");
static_assert(sizeof(long) == 4, "Microsoft Windows data model required");
class PalCraftMsvcLayout {
public:
    virtual unsigned long long invoke(unsigned long long value) noexcept;
};
unsigned long long PalCraftMsvcLayout::invoke(unsigned long long value) noexcept { return value + 1; }
extern "C" __declspec(dllexport) unsigned long long palcraft_msvc_abi_prepared(unsigned long long value) {
    PalCraftMsvcLayout object;
    return object.invoke(value) + sizeof(void*);
}

// Toolchain check only: no CRT or SDK-dependent initialization is performed.
extern "C" int __stdcall _DllMainCRTStartup(void*, unsigned int, void*) { return 1; }
