# Late authoritative snapshot catchup

When the native consumer attaches after a snapshot begin/body but before its end, the original World reducer has the complete stage while the native scheduler has no stage to finish. The native consumer could silently miss blocks and coverage although the original server completed the snapshot.

This source recognizes only a matching actual committed reducer receipt at the received end event. It queues budgeted work on the existing bootstrap queue, reads the current authoritative values, preserves later deltas and clears current missing blocks. Coverage is copied from the original receipt only after that work completes; all native tickets for the same region remain pending. Existing native stages keep the original ingestion behavior. No new timer, producer, snapshot request, ready certificate or ACK is added.

Three bounded synthetic source cases passed. The real initial timeout was recovered once by the original retry, which created a new ticket from the then-complete reducer; this does not prove the new automatic source is installed or accepted. Automatic cold-start and native visual results remain pending.
