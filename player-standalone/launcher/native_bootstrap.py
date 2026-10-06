"""Public native-MC state from messages already accepted by HostSession.receive."""
import copy
import math
import time
import uuid
from pathlib import Path

from installer.core import atomic_json


IDENTITY_KEYS = ('world_id', 'pal_uid', 'mc_uuid', 'mc_name')
LEASE_KEYS = ('v',) + IDENTITY_KEYS + ('server_session_id', 'session_id', 'generation', 'expires_at', 'legacy')


class NativeBootstrap:
    def __init__(self, path, public, writer=atomic_json, clock=time.time):
        self.path, self.write, self.clock = Path(path), writer, clock
        self.identity = {key: public['identity'][key] for key in IDENTITY_KEYS}
        self.pal_boot = public['server_session_id']
        self.host = self.native = self.view = None
        self.source_observed = None

    def _lease(self, value, native=False):
        if not isinstance(value, dict) or value.get('v') != 2 or value.get('legacy') is not False:
            raise ValueError('BOOTSTRAP_LEASE')
        if any(value.get(key) != expected for key, expected in self.identity.items()) or value.get('server_session_id') != self.pal_boot:
            raise ValueError('BOOTSTRAP_IDENTITY')
        for key in ('pal_uid', 'mc_uuid', 'session_id'):
            if not isinstance(value.get(key), str) or str(uuid.UUID(value[key])) != value[key]:
                raise ValueError('BOOTSTRAP_UUID')
        if type(value.get('generation')) is not int or value['generation'] < 1:
            raise ValueError('BOOTSTRAP_GENERATION')
        expiry = value.get('expires_at')
        if type(expiry) not in (int, float) or not math.isfinite(expiry) or expiry <= self.clock():
            raise ValueError('BOOTSTRAP_EXPIRED')
        result = {key: value[key] for key in LEASE_KEYS}
        if native:
            if not isinstance(value.get('mc_epoch'), str) or not value['mc_epoch']:
                raise ValueError('BOOTSTRAP_MC_EPOCH')
            result['mc_epoch'] = value['mc_epoch']
        return result

    def _world(self, value):
        if not isinstance(value, dict) or value.get('player') != self.identity['mc_uuid']:
            raise ValueError('BOOTSTRAP_WORLD_PLAYER')
        if any(not isinstance(value.get(key), str) or not value[key] for key in ('world_session', 'dim')):
            raise ValueError('BOOTSTRAP_WORLD_SCOPE')
        if type(value.get('view')) is not int or value['view'] < 1 or type(value.get('waiting_ack')) is not bool:
            raise ValueError('BOOTSTRAP_WORLD_VIEW')
        return {key: copy.deepcopy(value.get(key)) for key in ('player', 'world_session', 'dim', 'view', 'waiting_ack', 'mapping', 'bounds')}

    @staticmethod
    def _connection(value):
        return value['session_id'], value['generation']

    def bound(self, lease):
        host = self._lease(lease.session)
        if self.host is None or self._connection(host) != self._connection(self.host):
            self.native = self.view = None
            self.source_observed = None
        self.host = host

    def message(self, message, lease):
        """Call only after the existing host receiver has accepted the envelope."""
        host = self._lease(lease.session)
        if self.host is None or self._connection(host) != self._connection(self.host):
            raise ValueError('BOOTSTRAP_HOST_CHANGED')
        kind = message.get('t')
        if kind == 'session_error':
            self.unbound('session_error')
            return
        changed = False
        if kind == 'blocks' and 'native_binding' in message:
            native = self._lease(message['native_binding'], native=True)
            view = self._world(message.get('world_view'))
            self.native, self.view = native, view
            changed = True
        elif self.native is not None and kind == 'blocks':
            for row in message.get('lifecycle', []):
                if not isinstance(row, dict) or row.get('op') != 'player_view' or row.get('player') != self.identity['mc_uuid']:
                    continue
                view = self._world({'player': row['player'], 'world_session': message.get('session'),
                                    'dim': row.get('to'), 'view': row.get('view'), 'waiting_ack': row.get('waiting_ack')})
                if self.view and view['world_session'] == self.view['world_session'] and view['view'] < self.view['view']:
                    continue
                self.view = view
                changed = True
        elif self.native is not None and self.view is not None and kind == 'world_view_applied':
            if message.get('applied') is True and all(message.get(key) == self.view[key] for key in ('player', 'world_session', 'dim', 'view')):
                self.view = dict(self.view, waiting_ack=False)
                changed = True
        if changed:
            self.source_observed = self.clock()
            self.heartbeat(lease)

    def heartbeat(self, lease):
        """Use the proxy's existing two-second heartbeat, without inventing MC events."""
        host = self._lease(lease.session)
        if self.host is None or self._connection(host) != self._connection(self.host):
            self.bound(lease)
        self.host = host
        if self.native is not None and self.native['expires_at'] <= self.clock():
            self.native = self.view = None
            self.source_observed = None
        self._publish()

    def unbound(self, reason=None):
        self.host = self.native = self.view = None
        self.source_observed = None
        self._publish(reason)

    def _publish(self, reason=None):
        state = 'unbound' if self.host is None else 'waiting_world'
        if self.native is not None and self.view is not None:
            state = 'waiting_world' if self.view['waiting_ack'] else 'bound'
        # Initial home scope is usable without travel having happened first.
        # Native scene mapping/coverage remain the renderer/travel owner's evidence.
        missing = []
        if self.native is None:
            missing.append('native_binding')
        if self.view is None:
            missing.append('world_view')
        self.write(self.path, {'schema': 1, 'protocol': 2, 'state': state,
                              'updated_unix': self.clock(), 'source_observed_unix': self.source_observed,
                              'authenticated_host': self.host is not None, 'native_mc_verified': self.native is not None,
                              'identity': dict(self.identity), 'host_scope': copy.deepcopy(self.host),
                              'native_binding': copy.deepcopy(self.native), 'world_view': copy.deepcopy(self.view),
                              'missing_dependencies': missing, 'code': reason})
