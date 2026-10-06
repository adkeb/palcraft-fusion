"""Necessary item alpha-edge check against the actual MC getSideFaces oracle."""
import json
from pathlib import Path
root=Path('work/minecraft-fusion/entity-visuals/portable-assets')
reference=json.loads((root/'item-edge-reference.json').read_text())
produced=json.loads((root/'item-edges-produced.json').read_text())
for row in reference:
    texture=row['item'].replace('minecraft:','minecraft:item/')
    key=lambda e:(e['direction'],e['x'],e['y'])
    assert sorted(map(key,row['edges']))==sorted(map(key,produced[texture])),texture
print(json.dumps({'status':'passed','actual_MC_ItemModelGenerator_edge_masks':len(reference),'night_low_power':True}))
