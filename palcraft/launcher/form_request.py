"""Queue only the packaged form scripts through the existing personal client-op mailbox."""
import json
import time
from pathlib import Path

from installer.core import DEV, fail, get_state, operation_lock, owned_path
from launcher.runtime import executable_role


def request_form(root, mode, dry_run=False):
    if mode not in ('on', 'off', 'status'):
        fail('FORM_REQUEST', '变身操作只能为 on、off 或 status。')
    root = Path(root).absolute()
    state = get_state(root)
    options = state['manifest'].get('requirements', {}).get('player_runtime', {})
    if options.get('features', {}).get('operator_enabled') is not True:
        fail('FORM_DISABLED', '本版未启用变身接口。')
    script = executable_role(root, state, 'operator_form_' + mode)
    mailbox = owned_path(root, DEV + '/bridge/client-op.lua')
    result = owned_path(root, DEV + '/bridge/client-op-result.json')
    if dry_run:
        return {'ok': True, 'dry_run': True, 'mode': mode, 'script': str(script),
                'mailbox': str(mailbox), 'result': str(result), 'new_RPC_protocol': False}
    with operation_lock(root):
        if mailbox.exists():
            fail('FORM_BUSY', '个人客户端尚有一个待执行操作。')
        old = result.stat().st_mtime_ns if result.exists() else 0
        pending = owned_path(root, DEV + '/bridge/client-op.pending')
        pending.write_bytes(script.read_bytes())
        pending.replace(mailbox)
        for _ in range(100):
            if result.exists() and result.stat().st_mtime_ns != old:
                try:
                    answer = json.loads(result.read_text(encoding='utf-8'))
                except json.JSONDecodeError:
                    time.sleep(0.1)
                    continue
                return {'mode': mode, 'native_request_result': answer,
                        'effect_requires_observed_form_state': mode != 'status'}
            time.sleep(0.1)
    fail('FORM_TIMEOUT', '10 秒内没有个人客户端执行结果。')
