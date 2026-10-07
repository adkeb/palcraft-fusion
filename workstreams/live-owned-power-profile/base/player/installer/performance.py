"""Portable personal display profiles. No hardware policy or remote process control."""
import copy
from installer.core import configure, fail, get_state

PRESETS = {
    'normal': {'pal_fps': 60, 'mc_fps': 60, 'hud_fps': 30},
    'night': {'pal_fps': 15, 'mc_fps': 10, 'hud_fps': 10},
}


def validate_performance(value, pal_fps):
    if not isinstance(value, dict) or value.get('preset') not in ('normal', 'night', 'custom'):
        fail('CONFIG_PERFORMANCE', '帧率配置请选择 normal、night 或 custom。')
    for key, maximum in (('pal_fps', 120), ('mc_fps', 60), ('hud_fps', 120)):
        minimum = 10 if key == 'pal_fps' else 1
        if type(value.get(key)) is not int or not minimum <= value[key] <= maximum:
            fail('CONFIG_PERFORMANCE', key + ' 的帧率值不合法。')
    if value['pal_fps'] != pal_fps:
        fail('CONFIG_PERFORMANCE', 'fps 与 performance.pal_fps 必须一致。')
    return dict(value)


def with_preset(profile, preset, pal_fps=None, mc_fps=None, hud_fps=None):
    if preset not in PRESETS and preset != 'custom':
        fail('CONFIG_PERFORMANCE', '请选择 normal、night 或 custom。')
    result = copy.deepcopy(profile)
    values = dict(PRESETS.get(preset, result.get('performance', PRESETS['normal'])))
    values['preset'] = preset
    for key, value in (('pal_fps', pal_fps), ('mc_fps', mc_fps), ('hud_fps', hud_fps)):
        if value is not None:
            values[key] = value
    if any(x is not None for x in (pal_fps, mc_fps, hud_fps)):
        values['preset'] = 'custom'
    result['fps'] = values['pal_fps']
    result['performance'] = validate_performance(values, values['pal_fps'])
    return result


def remote_plan(profile):
    values = profile.get('performance', {**PRESETS['night'], 'preset': 'night'})
    return {'schema': 1, 'kind': 'palcraft-personal-performance-request',
            'identity': profile.get('connection', {}).get('identity'),
            'preset': values['preset'], 'targets': {key: values[key] for key in ('pal_fps', 'mc_fps', 'hud_fps')},
            'guest_jvm_argument': '-Dpalcraft.maxFps=' + str(values['mc_fps']),
            'hud_relay_arguments': ['--fps', str(values['hud_fps'])],
            'remote_applied': False, 'hardware_controls': False,
            'operator_action': 'Apply targets only to this assigned personal guest/relay; the player launcher does not control backend processes.'}


def set_performance(root, preset, pal_fps=None, mc_fps=None, hud_fps=None, dry_run=False):
    state = get_state(root)
    profile = with_preset(state['profile'], preset, pal_fps, mc_fps, hud_fps)
    configured = configure(root, profile, dry_run=dry_run)
    return {'ok': configured['ok'], 'dry_run': dry_run, 'performance': profile['performance'],
            'local_client_applies': 'on next personal client start', 'remote_plan': remote_plan(profile),
            'remote_applied': False, 'hardware_controls': False,
            'message': '个人帕鲁帧率已配置；MC/HUD目标需运营者应用到对应个人guest/relay。'}
