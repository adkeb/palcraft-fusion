"""Local test only: python3 research/test_bridge_json.py (bundled test Lua 5.4.8)."""
from pathlib import Path
import json
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / 'research/lua-5.4.8/src/lua'
CODEC = ROOT / 'bridge/PalLiveBridge/Scripts/json.lua'
def run_lua(script):
    result = subprocess.run([str(LUA), '-'], input='local json = dofile(' + repr(str(CODEC)) + ')\n' + script,
                            text=True, capture_output=True, check=True)
    return result.stdout

def encode_decode(text):
    # Lua long-bracket string delimiter is chosen to avoid the input.
    delimiter = '='
    while ']' + delimiter + ']' in text:
        delimiter += '='
    return run_lua('print(json.encode(json.decode([' + delimiter + '[' + text + ']' + delimiter + '])))')

valid = [None, True, False, 0, -1, 1.5, 1e23, {}, [], [None, False, {}, []],
         {'name': '帕鲁😀', 'guid': '22222222000000000000000000000000', 'n': None},
         '"\\\b\f\n\r\t\u0000\u001f']
random.seed(173)
def tree(depth=0):
    primitives = [None, True, False, random.randint(-1000000, 1000000), '箱子😀\\\n']
    if depth > 4 or random.random() < .5:
        return random.choice(primitives)
    if random.random() < .5:
        return [tree(depth + 1) for _ in range(random.randrange(5))]
    return {str(i): tree(depth + 1) for i in range(random.randrange(5))}
valid += [tree() for _ in range(1000)]
for item in valid:
    for ensure_ascii in (False, True):
        text = json.dumps(item, ensure_ascii=ensure_ascii, separators=(',', ':'))
        assert json.loads(encode_decode(text)) == item, repr(item)

invalid = ['', ' ', 'nul', 'True', 'falsex', '+1', '.2', '01', '-01', '1.', '1e',
           '1e+', '1e999', '--1', 'NaN', 'Infinity', '{}[]', '[,]', '[1,]', '[1 2]',
           '{"a":}', '{"a":1,}', '{"a" 1}', '{"a":1,"a":2}', '{"a":null,"a":2}',
           '{"a":false,"a":2}', '"\\x"', '"\\u123"', '"\\ud800"', '"\\udc00"',
           '"\\ud800\\u1234"', '"\n"', '"unfinished', '\ufeff{}', '/*x*/{}']
for item in invalid:
    try:
        encode_decode(item)
    except Exception:
        pass
    else:
        raise AssertionError('accepted invalid JSON: ' + repr(item))
assert json.loads(encode_decode('"\\ud83d\\ude00"')) == '😀'
run_lua('''
assert(json.encode(json.array()) == "[]")
assert(json.encode({}) == "{}")
assert(json.encode(json.decode('[null,null]')) == '[null,null]')
assert(not pcall(json.encode, {[1]=1,[3]=3}))
assert(not pcall(json.encode, {[1]=1,a=2}))
assert(not pcall(json.encode, 0/0))
assert(not pcall(json.encode, math.huge))
assert(not pcall(json.encode, function() end))
assert(not pcall(json.encode, string.char(255)))
assert(not pcall(json.decode, '"' .. string.char(255) .. '"'))
local cyclic={}; cyclic.self=cyclic
assert(not pcall(json.encode, cyclic))
assert(not pcall(json.decode, '[[[[]]]]', {max_depth=2}))
assert(not pcall(json.encode, {{{{}}}}, {max_depth=2}))
assert(not pcall(json.decode, '[1,2]', {max_bytes=4}))
assert(not pcall(json.encode, {1,2}, {max_bytes=4}))
assert(json.decode('"os.execute()"') == 'os.execute()')
''')
print(json.dumps({'lua': 'Lua 5.4.8', 'roundtrips': len(valid) * 2,
                  'invalid_inputs_rejected': len(invalid), 'edge_assertions': 16,
                  'result': 'passed'}))
