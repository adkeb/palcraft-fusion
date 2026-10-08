Follow-up to the full four-source native build: one relink only from the four freshly compiled objects, with the original64-byte output basename. No TU was recompiled, no old project object was used, no system time was changed, and private-delivery080/current33 remained untouched.

The original generic33-byte output basename had different .text/.rdata/.pdata/.buildid sections. With output named PalCraftRender-v16-portable-operator-Mac-raw-host-capture-v3.dll (64bytes), .text,.rdata,.pdata and every other section except .buildid are byte-identical to080. Thus output export-module basename/layout accounts for the prior observed code/layout difference in this one controlled relink. The current resulting DLL10fe967f272c5e201c96d9273e0838e735c6dac33aa3dca1afbc6e77afb1ee7a/485888B is still not whole-file identical: COFF timestamp1791423415 differs from original1791421143, and .buildid differs. No hash normalization or exact-whole-byte claim is made.

For a comparable full source build, use the portable entry with a new output directory and that basename:

```sh
python3 build_native_source.py --source-root /path/to/source --zig /path/to/zig --output /path/to/new/PalCraftRender-v16-portable-operator-Mac-raw-host-capture-v3.dll
```

The entry in the parent source bundle compiles all four TU anew. This follow-up only used that run's fresh objects to test the basename observation once; it is not a new installation candidate. Another user's fresh toolchain environment and actual Game behaviour were not verified. The first full build result and nonexact comparison are retained; the later result supplements rather than erases those observations.
