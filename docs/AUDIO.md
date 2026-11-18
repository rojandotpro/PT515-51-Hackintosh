# Audio — custom AppleALC for ALC289

The codec is a **Realtek ALC289** (`VEN_10EC&DEV_0289`, `SUBSYS_1025132D`). The stock AppleALC
layout for this board is **layout 23**, and everything here builds on it.

```
boot-arg: alcid=23
```

This repository ships a **prebuilt AppleALC 1.9.9** in the EFI, already containing the
modifications below. The sources and the patch are in [`../audio/`](../audio/) if you want to
rebuild it.

---

## Why layout 23 is the correct layout

Proven by hardware, not by picking the closest-looking XML. The Linux codec dump
(`/proc/asound/card0/codec#0`) gives the pin defaults the firmware actually programs:

| NID | Firmware pin default | Meaning |
|---|---|---|
| 0x12 | `0x40000000` | unused |
| **0x13** | **`0xb7a60130`** | **internal microphone** |
| **0x14** | **`0x90170110`** | **internal speaker** |
| 0x16 | `0x411111f0` | unconnected |
| **0x17** | **`0x411111f0`** | **unconnected — there is no second speaker** |
| 0x18–0x1a | `0x411111f0` | unconnected |
| **0x1b** | **`0x03a11040`** | headset microphone |
| 0x1e | `0x411111f0` | unconnected |
| **0x21** | **`0x03211020`** | headphone out |

Layout 23's ConfigData against that:

```
layout 23 :  0x13 b7a60130   0x14 90170110   0x1b 03811040   0x21 03211020
firmware  :  0x13 b7a60130   0x14 90170110   0x1b 03a11040   0x21 03211020
                  MATCH           MATCH        differs           MATCH
```

Three of four are byte-identical. The 0x1b difference is bits[23:20]: layout 23 says Line In
(`8`), firmware says Mic In (`A`). Cosmetic — the headset mic works — and fixable with
`alcverbs=1` if it ever matters.

**Layout 33 was tested and the internal microphone stopped working.** That is the whole argument:
33 (and 93, same mic pins) drive 0x17 as a second speaker, but 0x17 is not wired on this board.
There is no fuller sound to recover and no reason to revisit it.

**Nothing can be ported from the Windows driver.** `HDXACERNB.inf` contains no pin-config
overrides; the Acer INF is APO/effects registry keys only. Windows uses the same BIOS defaults
AppleALC reads. Waves MaxxAudio is a Windows userspace APO (`MaxxAudioRender64.dll`) with no
macOS equivalent — it cannot be replicated, only approximated (which is what the DSP chain below
does).

---

## What this build adds

Three changes on top of stock layout 23. All are visible in
[`../audio/applealc-layout23.patch`](../audio/applealc-layout23.patch).

### 1. Speaker DSP chain (approximates the Windows "Music" profile)

`layout23.xml` → `IntSpeaker` → `SignalProcessing` → `SoftwareDSP`:

| Index | Function | Purpose |
|---|---|---|
| 0 | `DspEqualization32` | Maxx-style EQ curve (several peaking/shelf filters) |
| 1 | `DspGainStage` | 2× gain (+6 dB) |
| 2 | `DspSplineLimiter` | catches the peaks the gain would otherwise clip |

This is a *static* approximation of the Windows effect. Do not expect it to be identical, and do
not add more gain without the limiter — the tiny speakers distort immediately.

### 2. Internal microphone boost (+10 dB)

`pinpatch.py` appends verb `0x01337001` to the ConfigData for the layout 23 entry:

```
0x013 3 7001  ->  NID 0x13, verb 0x3 (SET_AMP_GAIN_MUTE), payload 0x7001
```

Measured speech on the internal mic was about **−30 dBFS**, which made dictation tools cut off the
first word. The boost is also written to `WakeConfigData` so it survives resume.

### 3. Mute-key fix

In stock layout 23 the mute flags sat on the wrong nodes, so the hardware mute key did nothing for
the internal speakers or the headphone jack. `Platforms23.xml` moves them:

- `MuteInputAmp` / `PublishMute` on the speaker pin `0x14` and headphone pin `0x21`,
- `PublishVolume` stays on the DACs (`0x02`, `0x03`).

That is the entire fix. It is not an EC or HID problem — the key was always reaching the codec.

---

## Two settings that break audio

> **Do not set `AFGLowPowerState` to 0.** It was tried to stop the codec sleeping; the internal
> microphone input **disappeared** from the input list. Leave it at `3`. `pinpatch.py` deliberately
> does not touch it.

> **Keep both sample rates at 48000 Hz.** Built-in input and output in Audio MIDI Setup. If the
> input is at 44.1 kHz and the output at 48 kHz, activating the microphone drops the output stream.

---

## Known behaviour, not bugs

- **Idle pop.** The ALC289 powers its amplifier down when idle; the click on resume is the amp
  re-engaging. Every AppleALC profile for this codec sets `AFGLowPowerState`, so it is inherent.
  There is no macOS-side fix.
- **Codec idle wake and dictation.** Because the codec sleeps, some dictation apps can lose the
  first fraction of a second. The +10 dB boost makes the level usable but does not change the
  sleep behaviour.
- **`alc-layout-id` vs `layout-id`.** Live `ioreg` on `HDEF` shows
  `alc-layout-id = 23` (the real one) and `layout-id = 7` (AppleALC's substitute for AppleHDA).
  The `7` is correct and must not be "fixed".

---

## Rebuild from source

```sh
cd audio
chmod +x build.sh
./build.sh
```

The script:

1. clones AppleALC + MacKernelSDK (shallow) and fetches the latest Lilu DEBUG build,
2. copies `layout23.xml` and `Platforms23.xml` over `Resources/ALC289/`,
3. runs `pinpatch.py` on `Resources/PinConfigs.kext/Contents/Info.plist`,
4. builds and leaves the result in `audio/out/AppleALC.kext`.

Then install it into the EFI:

```sh
sudo diskutil mount disk0s1
sudo rm -rf /Volumes/EFI/EFI/OC/Kexts/AppleALC.kext
sudo cp -R audio/out/AppleALC.kext /Volumes/EFI/EFI/OC/Kexts/
sudo dot_clean -m /Volumes/EFI
```

Reboot. `alcid=23` stays in `boot-args`.

The **upstream AppleALC version will drift**; `build.sh` clones `master`. If it fails to build,
check out the tag matching the version you are replacing (1.9.9 here) and rebuild.

---

## Diagnostic commands

```sh
# Codec identity
ioreg -rn HDEF | grep -E 'IOHDACodecVendorID|alc-layout-id|layout-id'

# Audio devices and current rates
system_profiler SPAudioDataType

# CoreAudio restarts and failures
log show --last 5m --predicate 'process == "coreaudiod" OR sender CONTAINS "AppleHDA" OR sender CONTAINS "AppleALC"'
```

If audio stops after a macOS update, AppleHDA/AppleHDAController may need re-patching — see
[`NETWORK.md`](NETWORK.md) for the same root-patch cycle that Wi-Fi uses.
