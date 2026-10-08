# Configurable normal Minecraft window request

The existing `mac/scripts/prepare_launch.py` can read an optional `mc_window_width` and `mc_window_height` pair from `cfg.performance`. Both values must be integers: width 320..1920 and height 240..1080. Absence keeps all original startup arguments. The upper bounds follow the original 1920x1080 window request; framebuffer scale is still determined by the actual platform.

Store the pair in the existing profile's `standalone.backend_configuration.performance` dictionary, preserving its other performance fields. The original `installer/standalone.py` `generated_files` implementation keeps the preserved backend configuration at lines112..123, so no producer/schema change is required. This pair belongs to backend performance configuration, not the profile's top-level FPS-only performance dictionary.

After the original preserved template and FPS argument selection, only the guest's unique `--width` and `--height` values are copied and replaced. The original template file, server/HUD arguments, world/player identity, credential path, frame path, executable, CWD and original validation remain unchanged.

A 640x360 request is intended for a possible 2x HiDPI 1280x720 target. It is not a framebuffer setter or a live operation. The next normal Minecraft start and existing render-target inspection must prove the actual size and GUI mapping; no live result is claimed. Texture/native-model data and render/physics/freshness requirements are not changed.

The one bounded synthetic source case executes the original generated-configuration function and the actual old/new launch generators with isolated fixture files. It proves preservation, only two argument-value changes, default behavior and invalid pair rejection. Dummy dependency files are only path-existence fixtures and are never loaded. No role, Java process, game, active template, installed options, saved state or GUI/RPC is touched.
