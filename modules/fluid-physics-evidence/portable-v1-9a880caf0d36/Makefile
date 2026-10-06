.PHONY: all
all: PalCraftFluidPhysics-v1.dll
PalCraftFluidPhysics-v1.dll: source/native/fluid_physics.cpp source/launcher/windows_paths.hpp
	"/path/to/workspace/work/palworld-live/research/zig-aarch64-macos-0.15.2/zig" c++ -target x86_64-windows-gnu -shared -O1 -std=c++17 "$<" -o "$@" -lkernel32
