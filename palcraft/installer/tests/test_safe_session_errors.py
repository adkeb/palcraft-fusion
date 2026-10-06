import sys
import unittest
from pathlib import Path
BASE=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(BASE))
from launcher.session_proxy import safe_session_error

class SafeErrorTests(unittest.TestCase):
    def test_known_guest_not_ready_is_actionable(self):
        error=safe_session_error({'t':'session_error','error':'MC guest is waiting for its verified shared-world connection'},'bound','cam')
        self.assertEqual(error['code'],'guest_not_ready');self.assertEqual(error['operation'],'cam')
    def test_sequence_scope_and_hmac_are_separate_codes(self):
        for reason,code in [('Invalid local host proof','invalid_host_hmac'),('Wrong session/player scope','wrong_session_player_scope'),('Replayed or reordered message','replayed_or_reordered_message')]:
            self.assertEqual(safe_session_error({'error':reason},'bind')['code'],code)
    def test_unrecognized_raw_message_never_appears(self):
        reason='host_secret=PRIVATE_SENTINEL grant=PRIVATE_GRANT user_0123'
        value=safe_session_error({'error':reason,'code':'PRIVATE_CODE'},'bound','not-a-player-op')
        self.assertNotIn('PRIVATE',str(value));self.assertIsNone(value['operation'])
        self.assertNotIn('reason',value)
