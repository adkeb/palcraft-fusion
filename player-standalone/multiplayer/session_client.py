"""LAN host session binding/scoping. Python stdlib only; no private credential appears in an outbound message."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
import uuid
from pathlib import Path


def b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))


def b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode('ascii').rstrip('=')


def inspect_grant(token: str) -> dict:
    """Read public fields. Signature validation is performed by the MC authority; parsing is not verification."""
    payload, signature = token.split('.')
    if len(token) > 8192 or len(b64decode(signature)) != 64:
        raise ValueError('Invalid certificate encoding')
    grant = json.loads(b64decode(payload))
    if grant.get('v') != 2:
        raise ValueError('Unsupported session protocol')
    for key in ('pal_uid', 'mc_uuid', 'credential_id'):
        if str(uuid.UUID(grant[key])) != grant[key]:
            raise ValueError('Noncanonical player identity')
    identity = {k: grant[k] for k in ('world_id', 'pal_uid', 'mc_uuid', 'mc_name')}
    if not isinstance(grant.get('scopes'), list) or grant['expires_at'] <= grant['issued_at']:
        raise ValueError('Invalid certificate lifetime/scopes')
    return {**grant, 'identity': identity}


def load_credential(path: str | Path) -> dict:
    credential = json.loads(Path(path).read_text(encoding='utf-8'))
    if credential.get('v') != 2 or len(b64decode(credential['host_secret'])) != 32:
        raise ValueError('Invalid host credential')
    grant = inspect_grant(credential['grant'])
    if credential.get('identity') != grant['identity']:
        raise ValueError('Credential identity and certificate differ')
    return credential


def proof_text(challenge: dict, grant: str) -> bytes:
    fields = ['PalCraft/2/host.bind', challenge['nonce'], challenge['endpoint'], challenge['world_id'],
              challenge['server_session_id'], challenge['mc_uuid'], hashlib.sha256(grant.encode('utf-8')).hexdigest()]
    return '\n'.join(fields).encode('utf-8')


def host_answer(credential: dict, hello: dict, *, observer: bool = False, now: int | None = None) -> dict:
    challenge = hello.get('challenge', hello)
    grant = inspect_grant(credential['grant'])
    instant = int(time.time()) if now is None else now
    if instant < grant['issued_at'] - 5 or instant >= grant['expires_at']:
        raise ValueError('Registered credential expired; renew it for the same Pal UID')
    if challenge.get('v') != 2 or challenge.get('purpose') != 'host.bind':
        raise ValueError('Wrong authentication purpose')
    if (challenge['world_id'], challenge['server_session_id'], challenge['mc_uuid']) != (
            grant['world_id'], grant['server_session_id'], grant['mc_uuid']):
        raise ValueError('Guest endpoint is assigned to another player or Pal world/session')
    proof = b64encode(hmac.new(b64decode(credential['host_secret']), proof_text(challenge, credential['grant']), hashlib.sha256).digest())
    return {'t': 'bind', 'v': 2, 'grant': credential['grant'], 'proof': proof, **({'observer': True} if observer else {})}


class HostSession:
    def __init__(self, credential: dict):
        self.credential = credential
        self.grant = inspect_grant(credential['grant'])
        self.session = None
        self.sequence = 0

    def bound(self, message: dict) -> None:
        if message.get('t') != 'bound':
            raise ValueError(message.get('error', 'Expected authenticated bound response'))
        scope = message['session']
        if (scope.get('v') != 2 or scope.get('legacy') or
                {k: scope.get(k) for k in self.grant['identity']} != self.grant['identity'] or
                scope.get('server_session_id') != self.grant['server_session_id'] or
                scope.get('expires_at') != self.grant['expires_at'] or
                type(scope.get('generation')) is not int or scope['generation'] <= 0):
            raise ValueError('Bound response is for another identity or connection')
        uuid.UUID(scope['session_id'])
        self.session = dict(scope)
        self.sequence = 0

    def stamp(self, message: dict) -> dict:
        if self.session is None:
            raise ValueError('Host session has not completed its challenge')
        self.sequence += 1
        result = dict(message)
        if 'session' in result and not isinstance(result['session'], dict):
            result.setdefault('world_session', result.pop('session'))
        return {**result, 'session': dict(self.session), 'seq': self.sequence}

    def receive(self, message: dict) -> dict:
        if message.get('t') == 'session_error':
            return message
        if self.session is None:
            raise ValueError('Unbound event')
        scope = message.get('host_session')
        if not isinstance(scope, dict) or any(scope.get(k) != self.session.get(k) for k in
                ('v', 'world_id', 'pal_uid', 'mc_uuid', 'mc_name', 'server_session_id', 'session_id', 'generation')):
            raise ValueError('Stale or other-player event rejected')
        result = dict(message)
        result.pop('host_session', None)
        return result

    def disconnected(self) -> None:
        self.session = None
        self.sequence = 0


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('credential')
    args = parser.parse_args()
    value = inspect_grant(load_credential(args.credential)['grant'])
    print(json.dumps({'identity': value['identity'], 'server_session_id': value['server_session_id'],
                      'expires_at': value['expires_at'], 'signature_verified': False}, ensure_ascii=False))
