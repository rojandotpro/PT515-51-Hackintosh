# Special keys — investigated, not reachable

**Short answer: the Fn-row media keys and the PredatorSense key are handled inside the firmware
and are not exposed to the OS in any form this build can intercept.** All work on them was
reverted; the kext in this repository is the clean v3.7.0.

The goal was:

- a Turbo toggle key,
- a PredatorSense key that opens/closes the app,
- an Airplane key that toggles Wi-Fi/Bluetooth/location,
- the app following Fn backlight changes.

---

## What was measured

Each of these was checked on the running machine, not assumed:

| Probe | Result |
|---|---|
| ACPI notify from the EC (`_Q2C` path via `WMID`, notify `0xBC`) | fires only for **other** events (e.g. AC plug). Nothing on key presses. |
| Full EC RAM scan (256 bytes) before/after a key press | no change |
| `IOHIDManager` input monitoring | no HID events for the keys |
| VoodooPS2 release build with `LogScanCodes=1` | **prints nothing** when the keys are pressed |
| EC bit `LMIB` (offset `0x75`, bit 1) | set, then re-read — the keys did not appear |
| Airplane key | belongs to a separate ACPI device `SMKB` (`_HID 10251229`) with **no EC query** |
| Fn brightness | handled in firmware; WMI method 21 and EC `GBRL` do not reflect it |

Conclusion: the keys never reach the PS/2 controller, the EC, WMI or HID. They are consumed by
the embedded controller firmware before any OS-visible interface.

## What still works

| Key | Behaviour |
|---|---|
| **Mute** (hardware key) | works — fixed in the AppleALC layout, see [`AUDIO.md`](AUDIO.md) |
| **Volume up/down** | works via the same codec path |
| **Brightness** | works — `SSDT-PNLF` + WhateverGreen backlight |
| **Keyboard backlight** | **not** a key — use the slider in the PredatorSense menu-bar app (0–100 %) |
| Everything else in the Fn row | firmware-only, no OS hook |

## The only untested idea

If someone wants to reopen this, the one approach never tried is a **Linux live USB** capture:

```sh
sudo showkey -s          # raw PS/2 scan codes
acpi_listen              # ACPI events
sudo evtest              # input events
```

Press the four keys while each is running. If any scan codes appear, they can be mapped in
VoodooPS2's **Custom PS2 Map** to spare function keys, and the daemon can listen via
`IOHIDManager` and act on them (turbo, app toggle, Wi-Fi toggle).

That is a research task with an unknown payoff — on the balance of evidence above, the keys are
unlikely to produce any OS-visible code. **Do not add speculative EC writes to the driver to chase
them**; an EC write in the wrong register can hang the machine.
