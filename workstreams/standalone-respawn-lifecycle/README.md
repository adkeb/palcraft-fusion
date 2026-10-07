# Normal respawn lifecycle: two source slots

This delta targets the exact candidate14 standalone bootstrap and shared-view facade. Candidate15 changes the realm implementation and HUD runtime, so these two source baselines remain valid. SOURCE-MANIFEST.json pins the old and new bytes and managed targets.

The observed failure was individual feature error latching, rather than loss of the entire server-feature global. After a normal Pal respawn, the saved world and player authority recovered, but server entities, the bootstrap observer and travel remained in error. The original Compose tick excludes error features permanently. The outer dispatcher therefore returned successfully while the sole bootstrap observer no longer called the original standalone save consumer. The MC view remained waiting for ACK; a locally idle client travel worker did not prove acceptance.

The bootstrap now pauses the existing dispatcher when the fresh realm/owned-save gate fails. It publishes the original reason with authority=false and dispatcher_ok=false. The next original callback performs the original validation again before native workers advance. All original native/permission assertions are retained. Serious scope, process or ownership failures remain rejected. No worker is automatically reset, no success proof is reused across a failed callback, and no extra timer, reader or service is added.

The shared-view release function also recognizes a lease whose original client Worker.stop has completed. That worker sets stopped only after its shared native cleanup succeeds. Such an old owned lease uses the existing abandon bookkeeping, without calling its old native release method. A live owner still requires the original valid realm and native release. A failed client stop does not permit abandonment.

Three targeted source fixtures passed once. They load the actual original Compose/server features and client-options Worker.stop with explicitly simulated IO/native objects: level or saved-host gate failure followed by validation recovery; a serious process-permission failure after earlier success; and successful-stop abandonment versus failed-stop/live-owner release. These tests do not create an actual permission, save, world ACK, native process or gameplay proof.

The unchanged standalone_service remains the only save consumer. Its latest-record check for the existing SaveID still forbids replay of any intent or uncertain/requested result. This source delta does not resubmit a save or alter WAL records. Existing latched instances may be recovered only through the existing normal palcraft_features_start lifecycle, within the owner's authorized scope. The source task did not execute that recovery or touch a running installation.

Use the ordinary package composition/save/off/update/reload path after review. Actual normal respawn-to-view ACK, life/inventory conservation, normal stop/save completion and frame rate remain runtime acceptance work. The whole R01/F06/42 goal is not marked passed.

The relative source-check invocation is recorded in checks/receipt.json. It uses the existing Lua interpreter and original JSON module. The private base folder and HANDOFF are excluded from the source bundle; no SDK/game binary or commercial asset is bundled.
