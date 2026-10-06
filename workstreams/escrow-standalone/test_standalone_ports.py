"""New standalone path/process ports only; no old recovery matrix or game calls."""
from pathlib import Path
import json
import sys
import tempfile
import time
import unittest

BASE=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(BASE/'work/minecraft-fusion/palcraft/mcp'))
import escrow_standalone as S

WORLD='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
UID='00000000-0000-0000-0000-000000000001'
BOOT='abcdefab-1234-5678-9012-123456789abc'

class Ports(unittest.TestCase):
    def fixture(self,root):
        user=root/'private-user';level=user/'Saved'/'SaveGames'/'00000000000000000'/WORLD/'Level.sav'
        level.parent.mkdir(parents=True);level.write_bytes(b'fixture-only-save-not-a-real-Level')
        exchange=root/'exchange';rpc=root/'rpc';exchange.mkdir();rpc.mkdir()
        return {'private_user_dir_host':str(user),'installed_level_path_host':str(level),
                'world_directory':WORLD,'pal_uid':UID,'rpc_root_host':str(rpc),'exchange_root_host':str(exchange)},level
    def binding(self,scope):
        identity={'kind':'palworld_client_process_identity','native_code_matched':True,'read_only':True,
            'executable_sha256':S.CLIENT_SHA,'observed_unix':int(time.time()),'pid':1234,'process_created_filetime':'134000000000000000'}
        b={'kind':'palworld_client_process_binding','boot_id':BOOT,'world_directory':WORLD,'pal_uid':UID,
            'pid':identity['pid'],'process_created_filetime':identity['process_created_filetime'],'executable_sha256':S.CLIENT_SHA,'revision':1}
        (Path(scope['rpc_root_host'])/'escrow-client-process.json').write_text(json.dumps(identity))
        root=Path(scope['exchange_root_host']);(root/'escrow-client-process-binding.json').write_text(json.dumps(b))
        for suffix in ['.json','.durable.json']:(root/('pal-client-process-'+BOOT+'.r000001'+suffix)).write_text(json.dumps(b))
        return identity,b
    def test_actual_private_level_path_without_dedicated_zero_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            scope,level=self.fixture(Path(tmp));self.assertEqual(S.validate_level(scope,level),level.resolve())
            other=Path(tmp)/'other-Level.sav';other.write_bytes(b'unchanged')
            with self.assertRaises(ValueError):S.validate_level(scope,other)
    def test_wine_and_mac_mapping_are_physical_not_alias_claims(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);prefix=root/'wine';(prefix/'dosdevices').mkdir(parents=True)
            (prefix/'dosdevices'/'z:').symlink_to(root,target_is_directory=True)
            scope={'wine_prefix_host':str(prefix)}
            self.assertEqual(S.wine_path(scope,'Z:/共享 🌱/rpc'),(root/'共享 🌱/rpc').resolve())
            with self.assertRaises(ValueError):S.wine_path(scope,'Z:/../production')
    def test_native_singleplayer_authority_tuple_has_no_fake_host_alias(self):
        scope={'pal_uid':UID,'world_directory':WORLD}
        record={'player_uid':UID,'authority':{'mode':'standalone','world_directory':WORLD,'local_controller':True,
            'has_authority':True,'world_multiplayer_enabled':False,'dedicated_server':False,'remote_connected_players':0}}
        self.assertTrue(S.authority_matches(scope,record));record['player_uid']='22222222-0000-0000-0000-000000000000'
        self.assertFalse(S.authority_matches(scope,record))
    def test_process_binding_requires_fresh_native_identity_and_exact_durable_row(self):
        with tempfile.TemporaryDirectory() as tmp:
            scope,_=self.fixture(Path(tmp));identity,b=self.binding(scope)
            self.assertEqual(S.current_process_binding(scope),b)
            path=Path(scope['exchange_root_host'])/('pal-client-process-'+BOOT+'.r000001.durable.json')
            path.write_text(json.dumps({**b,'pid':9999}))
            with self.assertRaises(ValueError):S.current_process_binding(scope)
    def test_stale_process_does_not_make_a_boot_or_allow_a_save(self):
        with tempfile.TemporaryDirectory() as tmp:
            scope,_=self.fixture(Path(tmp));identity,b=self.binding(scope);identity['observed_unix']-=30
            (Path(scope['rpc_root_host'])/'escrow-client-process.json').write_text(json.dumps(identity))
            with self.assertRaises(ValueError):S.current_process_binding(scope)

if __name__=='__main__':unittest.main()
