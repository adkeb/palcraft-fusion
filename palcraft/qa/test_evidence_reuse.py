"""New focused offline evidence-retention checks; never replays gameplay."""
import tempfile
from pathlib import Path
import unittest
import acceptance as qa


class EvidenceRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(dir=qa.HERE);self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.dep=self.root/'component.lua';self.dep.write_text('unchanged component')
        self.evidence=self.root/'oracle.json';self.evidence.write_text('{"ok":true,"real_game_runtime_verified":false}')

    def review(self):
        return {'component':'geometry','proof_boundary':'offline_component','dependency_review':'model owner verified all inputs',
                'equivalence_reason':'Same algorithm and frozen inputs; auth-only hotfix is outside this proof boundary',
                'dependency_hashes':{'component.lua':qa.SHA(self.dep.read_bytes())},
                'artifacts':[{'path':'oracle.json','sha256':qa.SHA(self.evidence.read_bytes())}]}

    def test_exact_unchanged_component_proof_can_be_retained(self):
        r=qa.verify_reuse(self.review(),self.root)
        self.assertTrue(r['equivalent_component_evidence']);self.assertFalse(r['runtime_boundary_passed'])
        self.assertFalse(r['full_case_passed'])

    def test_changed_dependency_requires_review_not_automatic_reuse(self):
        r=self.review();self.dep.write_text('changed component')
        self.assertFalse(qa.verify_reuse(r,self.root)['equivalent_component_evidence'])

    def test_changed_or_missing_artifact_is_not_equivalent(self):
        r=self.review();self.evidence.write_text('{"ok":false}')
        self.assertFalse(qa.verify_reuse(r,self.root)['equivalent_component_evidence'])

    def test_missing_dependency_review_cannot_promote_old_evidence(self):
        r=self.review();r.pop('dependency_review')
        self.assertFalse(qa.verify_reuse(r,self.root)['equivalent_component_evidence'])

    def test_auth_health_runtime_boundary_cannot_be_inherited(self):
        r=self.review();r['proof_boundary']='runtime_boundary'
        self.assertFalse(qa.verify_reuse(r,self.root)['equivalent_component_evidence'])

    def test_saved_data_is_outside_retention_reader_scope(self):
        r=self.review();r['dependency_hashes']={'Saved/player.sav':'a'*64}
        self.assertFalse(qa.verify_reuse(r,self.root)['equivalent_component_evidence'])

    def test_jar_version_metadata_does_not_invalidate_model_scope(self):
        before={'palcraft/client/models.lua':'same','palcraft/mc/src/main/resources/fabric.mod.json':'version8'}
        after={**before,'palcraft/mc/src/main/resources/fabric.mod.json':'version8-hotfix'}
        self.assertEqual(qa.case_dependency_changes({'id':'W02'},before,after),[])

    def test_world_logic_change_is_inside_model_runtime_boundary(self):
        before={'palcraft/mc/src/main/java/dev/rehan/passthrough/WorldBridge.java':'old'}
        after={k:'new'for k in before}
        self.assertEqual(len(qa.case_dependency_changes({'id':'W02'},before,after)),1)


if __name__=='__main__':unittest.main()
