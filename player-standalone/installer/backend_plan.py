"""Generate operator service metadata only. Never starts, stops or reads a save."""
import re
from pathlib import PureWindowsPath
from installer.core import fail


def build_backend_plan(spec):
    required = ('python', 'watcher_script', 'exchange_dir', 'level_sav', 'parser_vendor', 'pal_settings')
    if any(not isinstance(spec.get(k), str) or not spec[k] for k in required):
        fail('BACKEND_CONFIG', '后端配置缺少 python、watcher_script、exchange_dir、level_sav、parser_vendor 或 pal_settings。')
    for key in required:
        value = spec[key]
        if '\x00' in value or not PureWindowsPath(value).is_absolute():
            fail('BACKEND_PATH', '后端路径必须是绝对 Windows 路径：' + key)
    level = str(PureWindowsPath(spec['level_sav'])).lower()
    settings = str(PureWindowsPath(spec['pal_settings'])).lower()
    if not level.startswith('d:\\palworldserver-lan\\bridgelab\\pal\\saved\\') or not level.endswith('\\level.sav'):
        fail('BACKEND_SCOPE', '当前 watcher 管理配置仅支持隔离 BridgeLab 的 Level.sav。', '其他专服需 owner 先完成保存端点与存档路径的参数化。')
    if settings != 'd:\\palworldserver-lan\\bridgelab\\pal\\saved\\config\\windowsserver\\palworldsettings.ini':
        fail('BACKEND_SCOPE', '仅接受 BridgeLab 的 PalWorldSettings.ini。')
    server_root = PureWindowsPath(spec['pal_settings']).parents[4]
    rpc_root = server_root / 'rpc'
    interval = spec.get('interval', 0.5)
    if type(interval) not in (int, float) or not 0.25 <= interval <= 30:
        fail('BACKEND_INTERVAL', 'watcher 间隔应为 0.25 到 30 秒。')
    argv = [spec['python'], spec['watcher_script'], 'witness', '--root', spec['exchange_dir'],
            '--level', spec['level_sav'], '--parser-vendor', spec['parser_vendor'], '--watch',
            '--interval', str(interval), '--pal-settings', spec['pal_settings'],
            '--pal-server-root', str(server_root), '--rpc-root', str(rpc_root),
            '--pal-save-url', 'http://127.0.0.1:8322/v1/api/save']
    return {'schema': 1, 'kind': 'palcraft-backend-service-plan', 'executed': False,
            'scope': 'BridgeLab-only until backend owner parameterizes save verification',
            'services': [{'id': 'exchange_witness', 'required_for': ['durable_material_exchange_credit'],
                          'argv': argv, 'restart_policy': {'when': 'failure', 'backoff_seconds': 5},
                          'dependencies': ['pal_server', 'minecraft_shared_server'],
                          'save_verification': 'parse exact current Level.sav slots after transaction save barrier',
                          'boot_verification': 'escrow_bootstrap.verifier(exchange_root, pal_server_root, level); lifecycle owner issues prepare/bind/finalize receipts',
                          'dependencies_versions': ['patched palworld-save-tools vendor', 'pyooz 0.0.8'],
                          'credential_sources': ['pal_settings read only by backend watcher'],
                          'health': {'condition': 'process_alive_and_witness_progress_or_no_pending_transactions',
                                     'blocked_exchange_behavior': 'hold credit; never grant/free items to compensate'}}],
            'player_stop_scope': ['personal_client', 'personal_ssh', 'personal_udp', 'personal_hud'],
            'player_commands_must_not_stop': ['pal_server', 'minecraft_shared_server', 'exchange_witness', 'other_player_guests']}
