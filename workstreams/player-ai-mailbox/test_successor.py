import importlib.util
import json
import subprocess
import sys
import threading
import time
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

SOURCE=Path('/path/to/workspace/work/minecraft-fusion/palcraft/mcp')
sys.path.insert(0,str(SOURCE))
spec=importlib.util.spec_from_file_location('ai_client',Path(__file__).with_name('ai_client.py'))
ai=importlib.util.module_from_spec(spec);sys.modules['ai_client']=ai;spec.loader.exec_module(ai)
spec=importlib.util.spec_from_file_location('ai_local_cases',SOURCE/'test_ai_local.py')
cases=importlib.util.module_from_spec(spec);spec.loader.exec_module(cases)


class SharedMailboxTests(cases.LocalQueueTests):
    def test_original_lab_control_completion_then_AI_preserves_public_AI_whitelist(self):
        for method in ('palcraft_start','palcraft_stop','palcraft_status'):
            previous_id=str(uuid.uuid4())
            cases.write(self.rpc/'agent-request.json',{'id':previous_id,'method':method})
            pending=(self.rpc/'agent-request.json').read_bytes()
            client=ai.LocalQueueClient(self.root,timeout_seconds=.01,poll_seconds=.005)
            with self.assertRaisesRegex(TimeoutError,'request not submitted'):
                client.call('status',{},str(uuid.uuid4()))
            self.assertEqual((self.rpc/'agent-request.json').read_bytes(),pending)
            cases.write(self.rpc/('agent-result-'+previous_id+'.json'),{'id':previous_id,'ok':True,'result':{'original_lab':method}})
            request_id=str(uuid.uuid4())
            def reply():
                deadline=time.monotonic()+1
                while time.monotonic()<deadline:
                    req=json.loads((self.rpc/'agent-request.json').read_text())
                    if req['id']==request_id:
                        cases.write(self.rpc/('agent-result-'+request_id+'.json'),{'id':request_id,'ok':True,'result':{'echo':req}})
                        return
                    time.sleep(.002)
                self.fixture_errors.append('AI request did not follow completed Lab request')
            thread=threading.Thread(target=reply);thread.start()
            self.assertEqual(self.client.call('status',{},request_id)['echo']['id'],request_id)
            thread.join(timeout=1);self.assertFalse(thread.is_alive())
            with self.assertRaises(ValueError):self.client.call(method,{},str(uuid.uuid4()))
        self.assertEqual(len(ai.METHODS),16)


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SharedMailboxTests))
    raise SystemExit(0 if result.wasSuccessful()else 1)
