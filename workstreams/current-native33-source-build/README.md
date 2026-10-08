Build the public native source as four fresh translation units. Requires Python3 and an existing Zig0.15.2 toolchain; the source root must contain render/*.cpp, render/sdk and launcher/windows_paths.hpp. No previous DLL/object files or game install are inputs.

```sh
python3 build_native_source.py --source-root /path/to/native-raw-host-capture/source --zig /path/to/zig --output /path/to/new/PalCraftRender.dll
```

The entry creates a new output-specific work directory, four objects and an isolated compiler cache, uses the original x86_64-windows-gnu/C++17/O2/DNOMINMAX/full warning/fno-lto flags, and links original ws2_32/user32/d3d11/dxgi libraries. It never runs or installs the DLL and refuses existing output/build directories. Each compiler call and source/object pin is recorded.

Optional read-only comparison with an existing reference uses:

```sh
python3 compare_native.py --reference /path/to/reference.dll --candidate /path/to/new.dll --report /path/to/comparison.json
```

The comparison reports actual whole-file, .text and section byte equality, PE format/machine, exports/import modules, timestamp/checksum and .buildid differences. Code-section equality alone is not whole-binary equality; a changed hash is not changed into a claim of exact reproduction. Local compiler/toolchain validation does not prove another user's fresh environment works.

Recorded local result: all four TU compiler calls plus link passed once, with no old project object inputs. The fresh485888B DLL SHA is e2231117f38e63ddea8fa9d3fa166226a951dda97a4b54cf7417226091578b73. Reference33 private-delivery SHA080ed405 remains untouched. PE/7exports/import modules match; whole-file and .text bytes do not. Different sections are .text,.rdata,.pdata,.buildid; COFF timestamps also differ. This does not prove solely relocation/layout differences or runtime equivalence.

All current33 native source pins match the public tree, including the unchanged ws/compositor source from the old object origin. palcraft/controls have recorded immutable matching compile flag families and link order/libraries match. The historical ws/compositor compile argv was not retained in the frozen object-origin manifest, so strict old flag equivalence is not claimed. Full four-source compilation success is verified locally; exact reproduction and another user's fresh environment are not. See PROVENANCE.json and COMPARISON.json.

A controlled follow-up linked the same four fresh objects once with the original output basename. All sections except .buildid, including .text, then matched the reference. COFF timestamp and build-id still differ; whole-file identity and runtime/another-user acceptance are not claimed. See [the observed comparison](basename-layout/README.md).
