# Display — EDID override, refresh rates, banding

Panel: **BOE NV156FHM-N4K**, EDID vendor/product `09e5`/`082a`, 15.6" 1920×1080 IPS, 144 Hz,
141 ppi, 8 bits per component, RGB 4:4:4, gamma 2.2, sRGB-like primaries.

The internal eDP link runs at **HBR2 (5.40 Gbps/lane), 4 lanes**, with zero lane errors reported by
`system_profiler SPDisplaysDataType` (`spdisplays_displayport_current_bandwidth`,
`_lanes`, `_errors_lane0..3`). That is ~17.3 Gbps of raw payload bandwidth — well above what
1920×1080 at 144 Hz needs — so link bandwidth is **not** the limiting factor for the 120 Hz and
90 Hz EDID modes in this repo. The EDID advertises 8 bits per primary channel; physical panel
bit depth (8-bit vs 6-bit+FRC) is still not confirmed by measurement.

Measured by Notebookcheck on the same panel model: 93 % sRGB, 288 cd/m², 1309:1, ΔE 3.22 out of
the box. **No HDR** — the EDID has zero extension blocks, so there is no CTA-861 HDR metadata
block. DisplayHDR is not supported and cannot be enabled. What Safari does with HDR YouTube is
macOS **EDR tone mapping**, not HDR output.

Everything below lives in `DeviceProperties → PciRoot(0x0)/Pci(0x2,0x0)` as
`AAPL00,override-no-connect` (a 128-byte EDID).

---

## The installed override

```
00ffffffffffff0009e52a0800000000
011c0104a523137802de50a3544c9926
0f505400000001010101010101010101
0101010101019d8580a070383e406c30
aa0058c11000001a9d8580a070387d46
6c30aa0058c110000000000000fc0054
7269746f6e203530300a20209d8580a0
703822416c30aa0058c11000001a001e
```

Descriptor slots (each 18 bytes, first slot at offset 54):

| Offset | Content |
|---|---|
| 54 | 144 Hz DTD — 342.05 MHz, htotal 2080, vtotal 1142 |
| 72 | **90.009 Hz** DTD — same clock and htotal, vtotal 1827, flags `0x1a` |
| 90 | Name descriptor `Triton 500` (shows in Displays and Colour profiles) |
| 108 | 120.034 Hz DTD — same clock and htotal, vtotal 1370 |

The panel's own 60 Hz DTD had sync flags `0x00`, which decode as analogue composite; the installed
override corrects that to `0x1a`. **60 Hz is not offered** in this configuration because slot 72
was given to 90 Hz. That is an accepted trade — the laptop is always plugged in. To get 60 Hz
back, swap slot 72 or drop the name descriptor.

### The rule that makes extra refresh rates work

> **macOS reads only the four base-block DTD slots.** A 256-byte EDID with a CTA extension block
> containing a 90 Hz DTD was **ignored** — tested, no effect.

Extra refresh rates are produced by **keeping the pixel clock and horizontal total unchanged and
lengthening only the vertical blanking**. That keeps the link rate and the panel's timing
constraints intact. Changing the pixel clock is what produces a black screen.

### The rule that does *not* work

The EDID previously declared **10 bits per primary** (byte 20 = `0xB5`) on the theory that macOS
needed it for a 10-bit framebuffer. **Wrong.** Reverted to the panel's true `0xA5` (8-bit) and the
framebuffer stayed `30-Bit Color (ARGB2101010)`. macOS allocates the 10-bit framebuffer regardless
of that byte. Do not re-add it — it made the descriptor contradict the hardware.

### Checksums

```
byte 127 = (256 - sum(bytes 0..126)) % 256
verify:  sum(all 128 bytes) % 256 == 0
```

The override's last byte is `0x1E`, which is the recomputed checksum after the byte-20 revert.

---

## Choosing a refresh rate

| Rate | Use |
|---|---|
| **144 Hz** | work, UI, scrolling |
| **120 Hz** | best all-round — divides 24/30/60 fps evenly, so video does not judder |
| **90 Hz** | lower power; judders on 24/60 fps video |

Change it in **System Settings → Displays**, or apply the prepared configs in
[`../display/90hz/`](../display/90hz/):

- `config.B-replace60.plist` — **the installed variant** (144 / 120 / 90).
- `config.A-ext256.plist` — the CTA-extension experiment that did not work; kept as evidence.

`../display/banding-test/` holds the configs used for the gradient tests, and
`../display/panel-audit/` and `../display/audit-*/` hold the Linux/EDID captures.

---

## What *not* to use

These files exist in the project history and are wrong for this panel. They are kept only so
nobody recreates them:

- `Display-9e5-82a.kext`, `DisplayVendorID-9e5/DisplayProductID-82a`, `EDID-9e5-82a.bin` — fake
  `9c7c` product ID, gamma 1.96, wrong primaries, name "Unknown Display".
- `config.experimental-90-120hz.plist`, `EDID-native-old120-plus-90hz.bin`,
  `config.native-plus-old-120hz.plist`, `config.native-ids-triton-120hz.plist`,
  `config.native-ids-triton-120hz-corrected.plist` — generated during the 90 Hz search, all
  superseded.

---

## Gradient banding — open, cosmetic

Browser gradients are smooth; some macOS UI gradients band. The likely cause is **8-bit compositor
output without dithering**, not the EDID. `AAPL00,Dither` is present but has no confirmed effect.

Things that were tried or are queued:

- sRGB IEC61966-2.1 profile instead of the auto "Triton 500" profile (sRGB renders darker; effect
  on banding not yet measured).
- A pipe-dithering toggle in the driver — **untested idea**, not implemented.

Do not chase this with EDID changes; the panel is 8-bit and macOS is rendering 8-bit.

---

## Resolution guidance

`2560×1440` is GPU **downscaling** to a 1080p panel — softer, non-integer resampling, and costly
on the UHD 630. HiDPI at 1080p logical needs a 3840×2160 framebuffer (4× the pixels) and is
impractical here. **Use native 1920×1080.**

## Colour profile

A free ICC measured on this exact panel model (i1Pro 2):
`https://www.notebookcheck.net/uploads/tx_nbc2/Triton500.icm`

Install to `~/Library/ColorSync/Profiles/`. That is another unit's measurement — white point varies
by ~540 K between units of the same model. For colour-critical work, calibrate with a colorimeter.

**Do not** use `Trit500.icm` from Notebookcheck's other PT515-51 review — that unit had an AUO
B156HAN08.2 panel.

## Media playback

The UHD 630 decodes **HEVC Main10** and **VP9 Profile 2** in hardware. It has **no AV1 decoder**
(AV1 starts with Tiger Lake). That is why HDR YouTube works in Safari (VP9 P2) and struggles in
Chrome (AV1 → software decode).

IINA settings that work (note: `gpu-next` is unavailable — IINA's bundled mpv has no libplacebo):

```
tone-mapping     = bt.2390
hdr-compute-peak = yes
Hardware decoding = Auto      -> videotoolbox, p010 10-bit surface
```

---

## Verify what is actually active

```sh
system_profiler SPDisplaysDataType
# Framebuffer Depth: 30-Bit Color (ARGB2101010)
# Resolution / UI Looks like / Refresh Rate

# Every mode the driver exposes
/usr/bin/python3 - <<'PY'
import Quartz
d = Quartz.CGMainDisplayID()
for m in Quartz.CGDisplayCopyAllDisplayModes(d, None):
    print(Quartz.CGDisplayModeGetWidth(m), Quartz.CGDisplayModeGetHeight(m),
          round(Quartz.CGDisplayModeGetRefreshRate(m), 3))
PY
```

Visual check: <https://testufo.com/refreshrate> should read the selected rate. Sleep/wake at
90 Hz and 120 Hz both work.

## Intermittent blank panel on restart — open, low severity

Rarely, the internal panel stays blank through a restart while the machine boots normally behind
it. **Close the lid, let it sleep, reopen** — the second panel bring-up succeeds and the image
returns.

That behaviour means it is a race in initial bring-up, not a hang, not a framebuffer failure, and
not the dead dGPU (which is absent from the bus and would fail consistently). The byte-20 EDID
revert was done partly on the theory that the connector was negotiating against a descriptor that
contradicted the hardware; **unproven as a fix** and kept on its own merits. `enable-backlight-registers-fix`
is already set. If it recurs, the next suspect is panel power sequencing — not the descriptor.
