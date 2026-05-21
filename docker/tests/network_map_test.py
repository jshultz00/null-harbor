#!/usr/bin/env python3
"""
Run: python3 tests/network_map_test.py
No external dependencies — stdlib only.
"""

import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
JS_PATH    = os.path.join(SCRIPT_DIR, '../network_map/network_map.js')
CSS_PATH   = os.path.join(SCRIPT_DIR, '../network_map/network_map.css')

# ─── Load data from network_map.js ───────────────────────────────────────────
# The file is `const NETWORK_MAP_DATA = { ... };` — strip the JS wrapper and
# parse the inner JSON object (the data uses strict JSON syntax throughout).
with open(JS_PATH, 'r') as f:
    src = f.read()

# Extract from first '{' to last '}'
start = src.index('{')
end   = src.rindex('}') + 1
D = json.loads(src[start:end])

# ─── Minimal test harness ─────────────────────────────────────────────────────
passed, failed = 0, 0
results = []

def assert_that(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        results.append(f'PASS  {name}')
    else:
        failed += 1
        suffix = f' — {detail}' if detail else ''
        results.append(f'FAIL  {name}{suffix}')

# ─── Test 1: Data integrity ───────────────────────────────────────────────────
REQUIRED_FIELDS = ['OS', 'Memory (GB)', 'CPUs', 'HDD Size (GB)', 'interfaces']

for mid, m in D['machines'].items():
    for f in REQUIRED_FIELDS:
        assert_that(f'[data-integrity] {mid} has field "{f}"', m.get(f) is not None)
    assert_that(
        f'[data-integrity] {mid}.interfaces is non-empty list',
        isinstance(m.get('interfaces'), list) and len(m['interfaces']) > 0
    )

# ─── Test 2: Zone assignment ──────────────────────────────────────────────────
zone_ids = {z['id'] for z in D['layout']['zones']}

def get_chain_role(mid, m):
    t    = (m.get('deploy') or {}).get('type', '')
    nets = [i['network'] for i in m.get('interfaces', [])]
    if t == 'linux-firewall':
        if 'dmz' in nets and 'external' in nets:
            return 'fw-dmz'
        if 'server' in nets:
            return 'fw-central'
    if 'external' in nets:
        return 'attack'
    return None

def get_zone_id(m):
    nets = {i['network'] for i in m.get('interfaces', [])}
    for zc in D['layout']['zones']:
        if zc.get('renderMode') == 'attackZone':
            continue
        if zc.get('segment') in nets:
            return zc['id']
    return None

for mid, m in D['machines'].items():
    if get_chain_role(mid, m) is not None:
        continue
    zid = get_zone_id(m)
    assert_that(f'[zone-assign] {mid} has a zone', zid is not None, 'get_zone_id returned None')
    if zid is not None:
        assert_that(
            f'[zone-assign] {mid} zone "{zid}" exists in layout.zones',
            zid in zone_ids
        )

# ─── Test 3: No orphan zones ──────────────────────────────────────────────────
known_networks = set(D['networks'].keys())

for mid, m in D['machines'].items():
    for iface in m.get('interfaces', []):
        net = iface['network']
        assert_that(
            f'[orphan-zones] {mid} interface network "{net}" exists in networks',
            net in known_networks
        )

# ─── Test 4: Legend data completeness ────────────────────────────────────────
zones = D['layout']['zones']
assert_that('[legend] layout.zones is non-empty', len(zones) > 0)
assert_that(
    '[legend] all zones have bgColor (starts with #)',
    all(z.get('bgColor', '').startswith('#') for z in zones),
    'one or more zones missing bgColor'
)
assert_that(
    '[legend] all zones have label',
    all(len(z.get('label', '')) > 0 for z in zones),
    'one or more zones missing label'
)

# ─── Test 5: wks-win10 removed, replacements present ─────────────────────────
assert_that('[machine-replace] wks-win10 is absent',  'wks-win10' not in D['machines'])
assert_that('[machine-replace] wks-linux is present',  'wks-linux' in D['machines'])
assert_that('[machine-replace] wks-win11 is present',  'wks-win11' in D['machines'])

# ─── Test 6: External subnet is 5.79.99.0/24 ─────────────────────────────────
assert_that(
    '[subnet] external network uses 5.79.99.0/24',
    D['networks']['external']['subnet'] == '5.79.99.0/24'
)

# ─── Test 7: wks-win11 IPs match README (10.0.0.101 / 10.30.30.20) ───────────
wks = D['machines'].get('wks-win11')
if wks:
    ctrl  = next((i for i in wks.get('interfaces', []) if i['network'] == 'control'), None)
    users = next((i for i in wks.get('interfaces', []) if i['network'] == 'users'),   None)
    assert_that(
        '[ips] wks-win11 control IP is 10.0.0.101/24',
        ctrl is not None and ctrl['ip'] == '10.0.0.101/24',
        f'got {ctrl["ip"]}' if ctrl else 'control interface missing'
    )
    assert_that(
        '[ips] wks-win11 users IP is 10.30.30.20/24',
        users is not None and users['ip'] == '10.30.30.20/24',
        f'got {users["ip"]}' if users else 'users interface missing'
    )

# ─── Test 8: External zone entry present in layout.zones ─────────────────────
assert_that(
    '[zones] External zone entry exists in layout.zones',
    any(z.get('id') == 'External' and z.get('renderMode') == 'attackZone' for z in zones)
)

# ─── Test 9: autoLayout block present in layout ───────────────────────────────
al = D['layout'].get('autoLayout') or {}
assert_that(
    '[auto-layout] autoLayout block exists with required keys',
    all(k in al for k in ('zoneStartX', 'zoneStartY', 'colStride', 'rowStride', 'defaultCols'))
)

# ─── Test 10: CSS file exists on disk ────────────────────────────────────────
assert_that('[css-exists] network_map.css is present on disk', os.path.isfile(CSS_PATH))

# ─── Output ───────────────────────────────────────────────────────────────────
for r in results:
    print(r)
print(f'\n{passed} passed, {failed} failed')
sys.exit(1 if failed > 0 else 0)
