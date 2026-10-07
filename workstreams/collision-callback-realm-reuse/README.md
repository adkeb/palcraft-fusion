# Reuse the exact realm proof inside the original collision callback

The independent collision callback used the real standalone realm repeatedly without opening its existing callback scope. Each consumer therefore rediscovered player/world/save/account objects. This source opens the original realm frame only for that callback, includes its status output, and closes only the frame it acquired. The original main/server callbacks, realm implementation, permission checks, cadence and native freshness remain unchanged.

Three bounded synthetic cases cover one complete fresh permission check per callback, early return/error/status-write cleanup, nested-frame ownership and the unchanged network branch. Real current timing identified the repeated lookup; the performance effect of this source has not been tested in the game.
