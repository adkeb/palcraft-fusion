"""Exact existing v5-public-macos13 HUD selection, with one role and original target name."""
import copy
import hashlib

HUD_TARGET = 'PalCraft-Dev/player-tools/bin/hud-overlay-v4'
HUD_SHA256 = '0cc13814ebdb3a14c7e5792cbcf9e7e539a4fcc8d23195bb4db591a6f0302753'
HUD_BYTES = 181520
HUD_SOURCE_SHA256 = '0a74168bb83448b515157882e2883db72c17f3773c8a66c39f4e34b0c16d676e'


def select_v5_public(manifest, data):
    if len(data) != HUD_BYTES or hashlib.sha256(data).hexdigest() != HUD_SHA256:
        raise ValueError('Use the exact existing v5-public-macos13 artifact; do not rebuild or substitute it')
    updated = copy.deepcopy(manifest)
    roles = [entry for entry in updated['files'] if entry.get('role') == 'mac_hud']
    if len(roles) != 1 or roles[0]['target'] != HUD_TARGET:
        raise ValueError('HUD role must be unique and retain its approved original target')
    roles[0].update(sha256=HUD_SHA256, bytes=HUD_BYTES, executable=True,
                   implementation_version='5-public-macos13', source_sha256=HUD_SOURCE_SHA256)
    updated['requirements']['mac_hud'] = {'version': '5-public-macos13', 'sha256': HUD_SHA256,
        'bytes': HUD_BYTES, 'source_sha256': HUD_SOURCE_SHA256,
        'relay_sha256': '685ad3caaef9c9e9792bae77e18a5b3ed3f16ca51d409f3a68a696ab5b700191',
        'port': 25603, 'night_hud_fps': 10, 'source_age_limit_ms': 250, 'titlebar_height': 28,
        'wire': 'MCPT/PHUD2/HCLK unchanged', 'minimum_macos': '13.0', 'sdk_used': '27.0', 'physical_HUD_verified': False}
    return updated
