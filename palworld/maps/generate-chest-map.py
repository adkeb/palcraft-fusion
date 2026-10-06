#!/usr/bin/env python3
"""Build a self-contained, read-only chest map from a plan and observed storage.

Example:
  python3 generate-chest-map.py --base 旧基地 plan.json after.json --output 箱子位置图.html
Repeat --base NAME PLAN AFTER for additional bases. No game or network access.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import sys

CATEGORIES = {
    'raw': ('建材矿物', '#8b7454'),
    'processed': ('加工材料', '#b1773b'),
    'pal_materials': ('帕鲁素材', '#9b705d'),
    'equipment': ('装备弹药捕获', '#536eb1'),
    'blueprint_armor': ('防具图纸', '#9568ba'),
    'blueprint_weapon': ('武器及建筑图纸', '#7d65b9'),
    'blueprint_accessory': ('饰品图纸', '#b0679e'),
    'pal_eggs_skills': ('帕鲁蛋与技能果', '#389b91'),
    'pal_training': ('帕鲁培养材料', '#448d67'),
    'food_seeds': ('食物种子', '#bc8738'),
    'valuables': ('贵重物品', '#ab9744'),
    'medicine': ('药品', '#50987c'),
    'unclassified': ('待确认杂物', '#75818b'),
}
ORDER = {key: i for i, key in enumerate(CATEGORIES)}
ZERO = '00000000-0000-0000-0000-000000000000'


def unwrap(value):
    for _ in range(5):
        if not isinstance(value, dict):
            break
        if isinstance(value.get('result'), dict):
            value = value['result']
        elif isinstance(value.get('structuredContent'), dict):
            value = value['structuredContent']
        elif isinstance(value.get('content'), list):
            texts = [x.get('text') for x in value['content'] if x.get('type') == 'text']
            if len(texts) != 1:
                break
            try:
                value = json.loads(texts[0])
            except (ValueError, TypeError):
                break
        else:
            break
    return value


def read_json(path):
    return unwrap(json.loads(Path(path).read_text(encoding='utf-8-sig')))


def finite(value):
    return isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value)


def identity(slot):
    return (slot.get('item'), str(slot.get('dynamicGuid', ZERO)).lower(),
            str(slot.get('dynamicWorldGuid', ZERO)).lower())


def point(box):
    p = box.get('map')
    if isinstance(p, dict) and finite(p.get('x')) and finite(p.get('y')):
        return {'x': p['x'], 'y': p['y']}
    p = box.get('world')
    if isinstance(p, dict) and finite(p.get('x')) and finite(p.get('y')):
        return {'x': (p['y'] - 158000) / 459, 'y': (p['x'] + 123888) / 459}
    return None


def classification_catalog(plans):
    exact, items = defaultdict(set), defaultdict(set)
    for plan in plans:
        for stack in plan.get('stacks', []):
            slot, category = stack['content'], stack['category']
            exact[identity(slot)].add(category)
            items[slot['item']].add(category)
    return exact, items


def build_base(name, plan, after, catalog=None):
    if not isinstance(plan, dict) or not isinstance(plan.get('containers'), list):
        raise ValueError(f'{name}: plan needs containers')
    if not isinstance(after, dict) or after.get('ok') is not True or after.get('includes_items') is not True:
        raise ValueError(f'{name}: after must be a successful storage.list result with items')
    if after.get('base_id') != plan.get('base_id'):
        raise ValueError(f'{name}: plan and observed storage belong to different bases')
    if not isinstance(after.get('chests'), list):
        raise ValueError(f'{name}: after needs chests')
    planned = {c['id']: c for c in plan['containers']}
    if len(planned) != len(plan['containers']):
        raise ValueError(f'{name}: duplicate plan container')
    by_token = {}
    exact_categories, item_categories = catalog or classification_catalog([plan])
    for stack in plan.get('stacks', []):
        slot, category = stack['content'], stack['category']
        by_token[stack['token']] = slot
    boxes, ids, warnings = [], set(), []
    for chest in after['chests']:
        cid = chest.get('id')
        if not isinstance(cid, str) or cid in ids:
            raise ValueError(f'{name}: missing or duplicate observed container')
        ids.add(cid)
        live_base = chest.get('base_id_live', chest.get('base_id_from_snapshot'))
        if live_base != plan['base_id']:
            raise ValueError(f'{name}: observed chest belongs to a different base')
        if chest.get('ok') is not True:
            raise ValueError(f'{name}: observed chest is unreadable')
        capacity = chest.get('capacity')
        slots = chest.get('slots')
        if not isinstance(capacity, int) or isinstance(capacity, bool) or capacity < 1 or not isinstance(slots, list) or len(slots) != capacity:
            raise ValueError(f'{name}: complete slots and valid capacity required')
        indices = {s.get('index') for s in slots}
        if indices != set(range(capacity)):
            raise ValueError(f'{name}: duplicate or incomplete slot indices')
        desired = planned.get(cid, {})
        expected_slots = {s['index']: by_token[s['token']] for s in desired.get('slots', [])}
        category_counts = Counter()
        items = Counter()
        used = 0
        matches = bool(desired)
        unknown_items = 0
        for slot in slots:
            count = slot.get('count')
            if not isinstance(count, int) or isinstance(count, bool) or count < 0:
                raise ValueError(f'{name}: invalid count')
            empty = slot.get('empty')
            if not isinstance(empty, bool) or empty != (count == 0) or not isinstance(slot.get('item'), str):
                raise ValueError(f'{name}: invalid empty slot')
            expected = expected_slots.get(slot['index'])
            if empty:
                if expected is not None:
                    matches = False
                continue
            used += 1
            if expected is None or identity(expected) != identity(slot) or expected['count'] != count:
                matches = False
            exact = exact_categories.get(identity(slot), set())
            category = next(iter(exact)) if len(exact) == 1 else None
            if category is None:
                same_item = item_categories.get(slot['item'], set())
                category = next(iter(same_item)) if len(same_item) == 1 else 'unclassified'
                if not same_item:
                    unknown_items += 1
            category_counts[category] += 1
            items[slot['item']] += count
        categories = [{'id': key, 'label': CATEGORIES.get(key, (key, '#75818b'))[0], 'stacks': count}
                      for key, count in sorted(category_counts.items(), key=lambda row: ORDER.get(row[0], 99))]
        label = ' / '.join(c['label'] for c in categories) or '空箱'
        pos = point(chest) or point(desired)
        world = chest.get('world') or desired.get('world') or {}
        box = {
            'id': cid, 'label': label, 'categories': categories, 'used': used,
            'capacity': capacity, 'free': capacity - used, 'mixed': len(categories) > 1,
            'type': '木箱' if chest.get('type_live', desired.get('type')) == 'ItemChest' else '金属箱' if chest.get('type_live', desired.get('type')) == 'ItemChest_02' else '普通箱',
            'point': pos, 'height': world.get('z') if finite(world.get('z')) else None,
            'color': CATEGORIES.get(categories[0]['id'], ('', '#75818b'))[1] if categories else '#91a0a7',
            'matches_plan': matches, 'unknown_items': unknown_items,
            'items': [{'item': item, 'count': count} for item, count in sorted(items.items())],
        }
        boxes.append(box)
    missing = set(planned) - ids
    if missing:
        warnings.append(f'方案中的 {len(missing)} 个箱子未出现在本次读取中；没有虚构它们的当前内容。')
    unplanned = ids - set(planned)
    if unplanned:
        warnings.append(f'本次读取多出 {len(unplanned)} 个箱子；其分类按已知物品判断，未知物品标为待确认。')
    different = sum(not b['matches_plan'] for b in boxes)
    if different:
        warnings.append(f'{different} 个箱子的内容与输入方案不同；本图格数及物品数量采用本次读取值。')
    no_position = sum(b['point'] is None for b in boxes)
    if no_position:
        warnings.append(f'{no_position} 个箱子缺少位置，只列在下方，不放入位置图。')
    boxes.sort(key=lambda b: (b['point'] is None, -b['point']['y'] if b['point'] else 0, b['point']['x'] if b['point'] else 0, b['id']))
    for i, box in enumerate(boxes, 1):
        box['number'] = f'{i:02d}'
    return {
        'id': plan['base_id'], 'name': name, 'boxes': boxes, 'warnings': warnings,
        'observed': after.get('observed_utc') or '读取时间未提供',
        'capacity': sum(b['capacity'] for b in boxes), 'used': sum(b['used'] for b in boxes),
        'free': sum(b['free'] for b in boxes), 'matches_plan': not different and not missing,
    }


def render_document(bases):
    template = Path(__file__).with_name('chest-map-template.html').read_text(encoding='utf-8')
    data = {'generated': datetime.now(timezone.utc).isoformat(timespec='seconds'), 'bases': bases}
    encoded = json.dumps(data, ensure_ascii=False, allow_nan=False, separators=(',', ':')).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    return template.replace('__CHEST_DATA__', encoded)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', action='append', nargs=3, metavar=('NAME', 'PLAN', 'AFTER'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        inputs = [(name, read_json(plan), read_json(after)) for name, plan, after in args.base]
        catalog = classification_catalog([plan for _, plan, _ in inputs])
        bases = [build_base(name, plan, after, catalog) for name, plan, after in inputs]
        if len({b['id'] for b in bases}) != len(bases):
            raise ValueError('Duplicate base input')
        document = render_document(bases)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(document, encoding='utf-8')
        print(json.dumps({'output': str(args.output.resolve()), 'bases': len(bases), 'boxes': sum(len(b['boxes']) for b in bases), 'used': sum(b['used'] for b in bases), 'free': sum(b['free'] for b in bases)}, ensure_ascii=False))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
