# Normal late game-save observation

A normal save can write Level again after the early successful save witness and before the original host exits. The original normal shutdown completed Save, Title/Quit, native exit 0 and all actual child waits, but its first port check was not yet quiet. A later normal finalizer correctly rejected the changed early witness.

This source adds a separate final observation on the original normal finalizer. It preserves the original successful save witness and durable save rows, verifies the original Title/Quit observations, stopped exit-0 host, empty job and a Level write between the original save and host exit. The existing standard codec reparses the final owned Level and Player and confirms the original UID; quiet inventories and hashes are still checked by the original receipt issuer. No save, process, transaction, world or ownership metadata is repaired. The new final observation is checked again before the original archive-only cold boot.

Saved-crash and unsaved-crash kinds and their truth remain separate. Existing normal receipts without a late observation remain valid. Three bounded temporary-file source cases cover the separate observation, rejected host/write boundaries and readback binding. Their codec callback is synthetic; real normal finalization and later cold boot require actual runtime evidence.
