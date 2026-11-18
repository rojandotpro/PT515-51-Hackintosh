# Layout 23 (ALC289, PT515-51) ConfigData tweaks:
#  - internal mic (node 0x13) boost +10 dB  (verb 0x01337001) - mic measured ~-30 dBFS speech
#  - AFGLowPowerState D3 -> D0: codec no longer sleeps between uses, so dictation
#    apps (Wispr Flow) don't lose the first words while it wakes
import plistlib, sys
f = sys.argv[1]
p = plistlib.load(open(f, 'rb'))
boost = bytes.fromhex('01337001')
hit = 0
def walk(o):
    global hit
    if isinstance(o, dict):
        if o.get('CodecID') == 0x10ec0289 and o.get('LayoutID') == 23:
            if boost not in o['ConfigData']:
                o['ConfigData'] += boost
            o['WakeConfigData'] = o.get('WakeConfigData', b'') + (b'' if boost in o.get('WakeConfigData', b'') else boost)
            # AFGLowPowerState left at 3: setting 0 made the mic input disappear
            hit += 1
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(p)
if hit != 1: sys.exit(f'layout 23 entry not found ({hit})')
plistlib.dump(p, open(f, 'wb'))
print('pinconfig patched: mic +10 dB')
