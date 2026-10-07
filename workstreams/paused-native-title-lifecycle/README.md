# Pause native callbacks before returning to Title

The normal saved-world return path previously called ClientReturnToMainMenu without the existing world cleanup/pause entry. After a client stop, the original timer also accessed its cached controller and realm before checking the paused flag.

This delta connects the existing sp.world.stop(serverFeatures) after the original save completion and requires its original stop_ok result before returning to Title. The paused timer consumes only the existing operation mailbox with a non-UObject clock, allowing the original Title observation and Quit commands. Active input, save requests, identity checks and receipt requirements remain.

The actual repeated access violation was inside Shipping; the exact native function is unknown. These changes repair demonstrated lifecycle ordering, but actual crash-free exit remains unverified.

Run the three bounded source cases with a locally available Lua 5.4 interpreter:

    lua checks/check_paused_title.lua .

The checker runs extracted production pause/queue code and the Python-generated normal lifecycle commands with synthetic native objects and in-memory IO. It does not start Game, access actual saves or perform desktop input. One initial fixture extraction error was corrected before the recorded three cases passed; production sources did not change during that correction.
