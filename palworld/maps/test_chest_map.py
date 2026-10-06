import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('chest_map', HERE / 'generate-chest-map.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
BASE = '11111111-1111-1111-1111-111111111111'
BOX = '22222222-2222-2222-2222-222222222222'
ZERO = m.ZERO


def fixture():
    content = {'item': 'Wood', 'count': 20, 'dynamicGuid': ZERO, 'dynamicWorldGuid': ZERO}
    plan = {'base_id': BASE, 'containers': [{'id': BOX, 'capacity': 2, 'type': 'ItemChest', 'map': {'x': 2., 'y': -3.}, 'slots': [{'index': 0, 'token': 't'}]}], 'stacks': [{'token': 't', 'category': 'raw', 'content': content}]}
    after = {'ok': True, 'includes_items': True, 'base_id': BASE, 'chests': [{'id': BOX, 'ok': True, 'base_id_live': BASE, 'capacity': 2, 'type_live': 'ItemChest', 'slots': [dict(content, index=0, empty=False), {'index': 1, 'item': 'None', 'count': 0, 'empty': True}]}], 'observed_utc': '2026-10-04T06:00:00Z'}
    return plan, after


class MapTests(unittest.TestCase):
    def test_complete_observed_counts_match_plan(self):
        p, a = fixture()
        b = m.build_base('旧基地', p, a)
        self.assertEqual((b['used'], b['free'], b['boxes'][0]['label']), (1, 1, '建材矿物'))
        self.assertTrue(b['matches_plan'])
        self.assertEqual(b['boxes'][0]['number'], '01')
        self.assertEqual(b['boxes'][0]['items'], [{'item': 'Wood', 'count': 20}])

    def test_observed_changes_override_plan_with_warning(self):
        p, a = fixture()
        a['chests'][0]['slots'][0]['count'] = 23
        a['chests'][0]['slots'][1] = {'index': 1, 'item': 'NewItem', 'count': 2, 'empty': False}
        b = m.build_base('旧基地', p, a)
        self.assertEqual((b['used'], b['free']), (2, 0))
        self.assertEqual(b['boxes'][0]['unknown_items'], 1)
        self.assertTrue(b['boxes'][0]['mixed'])
        self.assertFalse(b['matches_plan'])
        self.assertTrue(b['warnings'])

    def test_known_categories_are_shared_across_base_plans(self):
        p, a = fixture()
        other = {'stacks': [{'content': {'item': 'Wheat'}, 'category': 'food_seeds'}]}
        a['chests'][0]['slots'][1] = {'index': 1, 'item': 'Wheat', 'count': 3, 'empty': False}
        b = m.build_base('x', p, a, m.classification_catalog([p, other]))
        self.assertEqual(b['boxes'][0]['unknown_items'], 0)
        self.assertEqual(b['boxes'][0]['label'], '建材矿物 / 食物种子')
        self.assertFalse(b['matches_plan'])

    def test_scope_mismatch_and_bad_slots_reject(self):
        p, a = fixture()
        a['base_id'] = BOX
        with self.assertRaises(ValueError): m.build_base('x', p, a)
        p, a = fixture()
        a['chests'][0]['base_id_live'] = BOX
        with self.assertRaises(ValueError): m.build_base('x', p, a)
        p, a = fixture()
        a['chests'][0]['slots'][1]['index'] = 0
        with self.assertRaises(ValueError): m.build_base('x', p, a)
        p, a = fixture()
        a['chests'][0]['slots'][1]['count'] = 8
        with self.assertRaises(ValueError): m.build_base('x', p, a)

    def test_missing_positions_are_not_invented(self):
        p, a = fixture()
        p['containers'][0].pop('map')
        b = m.build_base('x', p, a)
        self.assertIsNone(b['boxes'][0]['point'])
        self.assertTrue(any('缺少位置' in w for w in b['warnings']))
        p['containers'][0]['world'] = {'x': -123888, 'y': 158000}
        b = m.build_base('x', p, a)
        self.assertEqual(b['boxes'][0]['point'], {'x': 0, 'y': 0})

    def test_missing_chest_does_not_show_planned_contents_as_live(self):
        p, a = fixture()
        a['chests'] = []
        b = m.build_base('x', p, a)
        self.assertEqual(b['used'], 0)
        self.assertFalse(b['matches_plan'])
        self.assertIn('未出现在', b['warnings'][0])

    def test_html_is_self_contained_and_escapes_data(self):
        p, a = fixture()
        b = m.build_base('</script><img src=x onerror=alert(1)>', p, a)
        text = m.render_document([b])
        self.assertNotIn('</script><img', text)
        self.assertIn('\\u003c/script', text)
        self.assertNotIn('__CHEST_DATA__', text)
        self.assertNotIn('<script src=', text)
        self.assertNotIn('<link ', text)
        self.assertIn("connect-src 'none'", text)

    def test_wrapped_protocol_responses(self):
        p, a = fixture()
        wrapped = {'result': {'content': [{'type': 'text', 'text': json.dumps(a)}]}}
        self.assertEqual(m.unwrap(wrapped), a)

    def test_actual_twenty_box_plan_projection_for_layout_only(self):
        # This synthetic after image is explicitly a local preview, never delivery.
        bases = []
        for stem, name in [('oldbase', '旧基地'), ('newbase', '新基地'), ('thirdbase', '第三基地')]:
            path = ROOT / 'work/palworld-live/lab'
            p = m.read_json(path / f'production-{stem}-plan.json')
            a = m.read_json(path / f'production-{stem}-before.json')
            by = {c['id']: c for c in a['chests']}
            payloads = {s['token']: s['content'] for s in p['stacks']}
            for c in p['containers']:
                slots = [{'container_id': c['id'], 'index': i, 'slot_id_index': i, 'item': 'None', 'count': 0, 'empty': True, 'dynamicGuid': ZERO, 'dynamicWorldGuid': ZERO} for i in range(c['capacity'])]
                for s in c['slots']:
                    slots[s['index']] = dict(payloads[s['token']], index=s['index'], empty=False)
                by[c['id']]['slots'] = slots
            a['observed_utc'] = '本地布局测试 · 方案投影，非实际读取'
            bases.append(m.build_base(name + '（布局测试）', p, a))
        self.assertEqual(sum(len(b['boxes']) for b in bases), 20)
        self.assertEqual(sum(b['used'] for b in bases), 222)
        self.assertTrue(all(b['matches_plan'] for b in bases))
        (HERE / 'layout-preview.html').write_text(m.render_document(bases), encoding='utf-8')


if __name__ == '__main__':
    unittest.main()
