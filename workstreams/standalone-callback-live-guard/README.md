# Same-callback local realm guard, next15

This is a one-file source delta against local_realm SHA dc0f2d1fafdc6e07ff6a1400c30879ad37dc802f15a8bf788d0c99df5cac1446. The inherited main frame wrapper SHA daa598cabb14b300eb24d247b25c22abed17302baac7cc350d9c8821d162c9a9 is unchanged.

The callback boundary still performs the complete native context check and original owned-save permission verification. Subsequent operations in that same callback check live local possession, PC/Pawn/World/GameState references, authority/initialization, and transmitter/player-component ownership. A changed relationship triggers the existing complete rediscovery path. There is no time-based context lease, widened native freshness window, fabricated focus/ready signal, or change to native resource mutations.

The three existing-object source fixtures passed once: stable repeated work, changed pawn/world, and rejected permission with no reuse of prior success. For the same 20 rounds of current/validate/same_world/status, the fixture recorded GetFullName 2530 to 160 and GetSaveGameManager 80 to 1. Original permission calls remain 1 in each compared callback. These are synthetic call counts; they do not measure the game.

The parent runtime's existing full candidate14 profiles reported callback means 168.7, 170.8, and 154.8 ms, with discovery 93, 72.8, and 68.4 ms. Candidate14 had already completed natural view acknowledgment and released the held state. This candidate removes redundant work but has no actual next15 frame-rate result. The once-per-callback complete native proof and other feature work remain potential costs. Neither 60 FPS nor the full gameplay acceptance set is marked passed.

Apply the patch only to the pinned baseline through the existing ordinary package composition and normal save/off/update/reload path. The source task did not touch an installation, game, world, process, RPC, UI, or Git.

Run the source check in the original workspace using the relative command in checks/receipt.json. It requires the existing Lua interpreter and original json.lua/readers.lua modules; its object fixture is explicitly simulated. No compiled artifacts or commercial SDK/game assets are included.
