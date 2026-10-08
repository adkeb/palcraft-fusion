# ChunkPos API correction

One production call changes from ChunkPos.asLong(int,int) to the actual Minecraft26.3 ChunkPos.pack(int,int). The preceding production compiler rejected the old call (c2fb07 exit1); local class metadata confirmed pack (5e917c exit0). The older synthetic lifecycle case did not validate that production API name.

The previous frozen source and failure are preserved. Client options, gateway plumbing/cancellation, fabric version, all remaining MC source and gameplay semantics are unchanged. The included complete MC source uses the corrected call. No tests or production compiler were rerun here; the approved assembler performs the necessary fresh build. No Game, GUI, RPC, input, installed/current file, saved world, credentials or Git action was performed.
