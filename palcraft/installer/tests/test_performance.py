import json
import sys
import unittest
from pathlib import Path
BASE=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(BASE))
from installer.core import PlayerError,get_state
from installer.performance import PRESETS,with_preset,set_performance,remote_plan
import test_player_tools as fixtures

class PerformanceTests(unittest.TestCase):
    def test_normal_and_night_are_explicit_portable_choices(self):
        original={'fps':15,'connection':{'identity':{'mc_uuid':'fixture'}}}
        normal=with_preset(original,'normal');night=with_preset(original,'night')
        self.assertEqual(normal['performance'],{**PRESETS['normal'],'preset':'normal'})
        self.assertEqual(night['performance'],{**PRESETS['night'],'preset':'night'})
        self.assertEqual(original['fps'],15)
        self.assertFalse(remote_plan(normal)['remote_applied'])
        self.assertNotIn('policy_path',normal)
    def test_custom_can_change_all_three_caps(self):
        selected=with_preset({'fps':15},'normal',pal_fps=45,mc_fps=30,hud_fps=20)
        self.assertEqual(selected['fps'],45)
        self.assertEqual(selected['performance']['preset'],'custom')
        self.assertEqual(remote_plan(selected)['hud_relay_arguments'],['--fps','20'])
    def test_invalid_cap_rejected(self):
        with self.assertRaises(PlayerError):with_preset({'fps':15},'custom',pal_fps=1)
        with self.assertRaises(PlayerError):with_preset({'fps':15},'normal',mc_fps=120)
    def test_managed_config_writes_only_personal_target_request(self):
        f=fixtures.PlayerTests(methodName='test_dry_run_has_no_files_or_network_or_processes');f.setUp()
        try:
            f.installed();before=get_state(f.root)
            result=set_performance(f.root,'night',dry_run=True)
            self.assertTrue(result['dry_run']);self.assertEqual(get_state(f.root)['profile']['fps'],before['profile']['fps'])
            result=set_performance(f.root,'night')
            self.assertEqual(get_state(f.root)['profile']['fps'],15)
            request=json.loads((f.root/'PalCraft-Dev/bridge/personal-performance-request.json').read_text())
            self.assertEqual(request['targets'],{'pal_fps':15,'mc_fps':10,'hud_fps':10})
            self.assertFalse(request['remote_applied']);self.assertFalse(request['hardware_controls'])
        finally:f.tearDown()
