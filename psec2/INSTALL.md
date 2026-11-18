# PredatorSense for macOS — v2.9.0

Acer Predator Triton 500 (PT515-51), macOS, OpenCore.

Fans, Turbo, LCD Overdrive, keyboard RGB, CPU power profiles.

> This document describes the driver design and is still accurate. The version in this
> repository is **PredatorSenseEC 3.7.0**; see [`../docs/PREDATORSENSE.md`](../docs/PREDATORSENSE.md)
> for the current install steps and command reference.

```
PredatorSense.app   (menu bar, runs as you)
        │  UNIX socket /var/run/predatorsense.sock
predatorsensed      (root daemon)
        │  IOKit user client
PredatorSenseEC.kext
        ├─ ACPI \_SB.PCI0.WMID.WMBH   ← fans, Turbo, LCD OD, RGB
        ├─ ACPI EmbeddedControl       ← sensors, and fan fallback
        └─ MSR 0x610 PKG_POWER_LIMIT  ← CPU power profiles
```

---

## What changed in 2.1.0

**Fan control now goes through WMI, not EC RAM writes.** The `ecdump` from last
time proved the EC's own control loop rewrites `F1ST` back to `0x04` between our
polls — our writes never took. And `Method (GFGB)` in your SSDT1 decodes *any*
duty ≤ `GFMS` as **MAX**, which is why every slider position gave full speed.
`SetGamingFanSpeed` takes a true percentage and doesn't go through that decode.

Direct EC writes remain as an automatic fallback if any WMI call fails.

**On the SMI.** I previously told you the WMBH/SMI path froze your machine and
shouldn't be revisited. That was wrong. `AcerGamingWMI.kext` had the *identical*
`Info.plist` bug this project had — `com.apple.driver.AppleACPIPlatform` instead
of `com.apple.iokit.IOACPIFamily` — so it hung at ACPI bring-up and never ran a
line of its own code. The SMI was never actually exercised. It is untested, not
disproven. Everything below is sequenced so that if it genuinely does stall, you
are at a desktop and your boot is unaffected.

---

## Build

```bash
cd psec2 && chmod +x build.sh && ./build.sh
```

## Install

```bash
sudo diskutil mount disk0s1
sudo cp -R /Volumes/EFI/EFI/OC/config.plist /Volumes/EFI/config-backup-2.1.plist
sudo rm -rf /Volumes/EFI/EFI/OC/Kexts/PredatorSenseEC.kext
sudo cp -R build/PredatorSenseEC.kext /Volumes/EFI/EFI/OC/Kexts/

sudo launchctl bootout system/local.predatorsense.daemon 2>/dev/null
sudo cp build/predatorsensed /usr/local/libexec/
sudo chown root:wheel /usr/local/libexec/predatorsensed
sudo chmod 755 /usr/local/libexec/predatorsensed
rm -rf /Applications/PredatorSense.app
cp -R build/PredatorSense.app /Applications/
```

The kext is already enabled in your config and the LaunchDaemon plist is already
installed, so nothing else needs editing.

**Reboot with the pendrive unplugged.** Don't start the daemon yet.

---

## Bring-up — in this order, don't skip ahead

### Stage 1 — kext loaded, nothing written

```bash
ioreg -c PredatorSenseEC -rd1 | grep -E 'Temp|Fan|Status|WMI|Control'
```

Expect real temps and RPM, `Status = ok`, `FanMode = auto`.

`WMI_Present` will be **No** at this point — that's correct. The driver does not
go looking for the WMI device until you ask it to do something. Nothing has
touched an SMI yet.

### Stage 2 — daemon

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/local.predatorsense.daemon.plist
echo status | nc -U /var/run/predatorsense.sock
```

### Stage 3 — the first SMI, deliberately the smallest one

This is the real test. `turbo` is a single WMI call with a two-byte payload and
nothing else depends on it.

```bash
echo "turbo on" | nc -U /var/run/predatorsense.sock
```

- **You get a reply** → the SMI returns. The path is live. Continue.
- **It hangs / the machine locks** → hold the power button. On the next boot
  everything is back to normal (nothing here persists), and the fans still work
  through the EC fallback. Tell me and stop at this stage.

Check `"wmiPresent": true` in the reply, then turn it back off:

```bash
echo "turbo off" | nc -U /var/run/predatorsense.sock
```

### Stage 4 — fans, upward first

A write that only makes fans faster can't cook anything.

```bash
echo "duty 90 90"     | nc -U /var/run/predatorsense.sock
echo "fanmode manual" | nc -U /var/run/predatorsense.sock
echo status           | nc -U /var/run/predatorsense.sock
```

**Both** fans should get louder, and `"controlPath": "wmi"`. Now the thing that
failed last time — check the slider actually does something in between:

```bash
echo "duty 45 45" | nc -U /var/run/predatorsense.sock ; sleep 5
echo status       | nc -U /var/run/predatorsense.sock
```

RPM must land clearly *below* the 90% reading. If 45 and 90 give the same RPM,
the percentage isn't being honoured — tell me the numbers for both.

```bash
echo "fanmode auto" | nc -U /var/run/predatorsense.sock
```

### Stage 5 — prove the watchdog (do not skip)

```bash
echo "duty 90 90"     | nc -U /var/run/predatorsense.sock
echo "fanmode manual" | nc -U /var/run/predatorsense.sock
sudo killall -9 predatorsensed
```

Within ~6 s the fans must drop back to EC control:

```bash
log show --last 2m --predicate 'eventMessage CONTAINS "PredatorSenseEC"'
# expect: "fans returned to EC control (last client disconnected)"
```

If they don't, stop using manual mode and tell me. That net is what makes the
rest acceptable.

### Stage 6 — the rest

```bash
echo "lcdod on"           | nc -U /var/run/predatorsense.sock
echo "rgb 255 0 0 15"     | nc -U /var/run/predatorsense.sock   # all 4 zones red
echo "power performance"  | nc -U /var/run/predatorsense.sock
echo status               | nc -U /var/run/predatorsense.sock
```

If `"powerLocked": true`, your firmware sealed the package power MSR until the
next reset and profiles can't apply this boot. That's a BIOS decision, not a bug
here — the driver reads the register back and reports it rather than lying.

### Stage 7 — the app

```bash
open /Applications/PredatorSense.app
```

---

## About 100%

The GPU fan used to top out around 4000 RPM where the CPU fan reaches 6000+.
That was the *custom curve's* ceiling, not the fan's: `GFMS` gives per-fan
maxima of 102 (CPU) and 78 (GPU), and custom mode is bounded by them, so the GPU
fan's "100%" was a lower absolute speed.

Fan behaviour modes are per-slot, so from 2.3.0 a slider at **100% switches that
fan to MAX mode** — the separate path the firmware's own max-fan button uses,
which isn't bounded that way. Anything below 100% stays on the custom curve. So
one fan can sit on its curve while the other runs flat out.

## Command reference

```
status
fanmode auto|manual
duty <cpuPct> <gpuPct>          35-100
turbo on|off
lcdod on|off
rgb <r> <g> <b> [zoneMask]      0-255 each; zones 1,2,4,8 — 15 = all
power low|balanced|performance
wmi <methodId> <hexByte>...     raw probe; byte count = argument width
ecread <hex> / ecwrite <hex> <hex> / ecdump
```

`wmi` is the escape hatch. If an encoding turns out to be wrong, that's what we
use to find the right one without rebuilding.

---

## Settings persistence

Every setting you change is written to
`/Library/Application Support/PredatorSense/state.json` and re-applied by the
daemon on the next boot: fan mode and duty, CPU power profile, Turbo, LCD
Overdrive, keyboard mode/speed/brightness/direction and each zone's colour.

To start clean: `sudo rm "/Library/Application Support/PredatorSense/state.json"`

Keyboard brightness is intentionally limited to **10–100%** in the app. The
firmware turns the LEDs off below 10%; zero remains reserved for the daemon's
temporary idle dim.

## Safety

1. **Duty floor** — 35%, enforced in the kernel regardless of what's asked.
2. **Thermal ceiling** — 88 °C on the real EC sensor forces auto, releasing at
   78 °C so it can't oscillate.
3. **Watchdog** — manual mode requires a keepalive every 2 s; 6 s of silence
   hands the fans back.
4. **Client teardown** — daemon exit or crash reverts immediately, no timer.
5. **Reconciliation** — the driver tracks what the hardware *confirmed*, not what
   was asked, and retries any failed write every tick.
6. **Partial WMI failure reverts** — if the behavior call succeeds but a speed
   call fails, it puts the fans straight back to auto rather than leaving one fan
   set and one not.
7. **No hardware access at boot.** First EC read is 20 s after load; the first
   WMI call only ever happens because you asked for one.
8. **Power profiles are verified.** Performance requests PL1 45 W / PL2 90 W.
   The driver reads MSR 0x610 back immediately; if firmware or hardware caps
   PL2 (this machine's default is 75 W), the command fails and reports the
   actual limit instead of claiming that 90 W was applied.

Sleep, unload and shutdown all revert.

---

## If something goes wrong

Fans stuck: `echo "fanmode auto" | nc -U /var/run/predatorsense.sock`, or just
`sudo killall predatorsensed` — losing the client reverts them.

Boot problems: OpenShell from the picker → `cd EFI\OC\Kexts` →
`mv PredatorSenseEC.kext PredatorSenseEC.off`.

## Uninstall

```bash
sudo launchctl bootout system/local.predatorsense.daemon
sudo rm /Library/LaunchDaemons/local.predatorsense.daemon.plist
sudo rm /usr/local/libexec/predatorsensed
sudo rm -rf /Applications/PredatorSense.app
```

## Known limits

- **GPU overclocking/monitoring**: not possible. `-wegnoegpu` disables the NVIDIA
  GPU under macOS. The GPU *fan* works because the EC drives it regardless.
- **WMI payload encodings** come from your firmware's own binary MOF (`WQAB`) and
  the Linux `acer-wmi` driver. They are reconstructed, not yet confirmed on your
  hardware. Stage 3 and Stage 4 are what confirm them.
