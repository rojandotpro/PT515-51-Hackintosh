# PredatorSense — the custom driver stack

Acer's PredatorSense is Windows-only. It controls fans, CPU power profiles, the LCD overdrive flag,
the keyboard RGB and the keyboard backlight over an undocumented ACPI-WMI interface. This project
replaces it with three components and **no third-party dependencies**.

> **Want to build your own?** [`BUILD-YOUR-OWN-APP.md`](BUILD-YOUR-OWN-APP.md) is the full tutorial:
> finding the control path, reversing the ACPI-WMI interface, probing safely, writing the kext,
> daemon and app, and porting the method to another laptop.

```
PredatorSense.app        SwiftUI menu-bar app (runs as you, LSUIElement)
      │  UNIX socket /var/run/predatorsense.sock
predatorsensed           root LaunchDaemon, owns the IOKit connection
      │  IOKit user client (PredatorSenseEC)
PredatorSenseEC.kext     kernel driver
      ├─ ACPI \_SB.PCI0.WMID.WMBH   fans, Turbo, LCD Overdrive, RGB
      ├─ ACPI EmbeddedControl       sensors, fan fallback
      └─ MSR 0x610 PKG_POWER_LIMIT  CPU power profiles
```

Settings persist to `/Library/Application Support/PredatorSense/state.json` (root-only) and are
restored at boot, so you never need to open the app.

---

## Build

Requires only Xcode Command Line Tools.

```sh
cd psec2
chmod +x build.sh
./build.sh
```

Output is in `psec2/build/`:

```
PredatorSenseEC.kext
predatorsensed
PredatorSense.app
```

The build compiles the kext against the **installed macOS SDK's kernel headers** and ad-hoc signs
everything. No MacKernelSDK checkout is needed, but the SDK must ship `Kernel.framework`.

---

## Install

```sh
# 1. Kext into the EFI
sudo diskutil mount disk0s1
sudo cp -R psec2/build/PredatorSenseEC.kext /Volumes/EFI/EFI/OC/Kexts/
# It is already enabled in config.plist. Reboot.

# 2. Daemon
sudo cp psec2/build/predatorsensed /usr/local/libexec/
sudo chown root:wheel /usr/local/libexec/predatorsensed
sudo chmod 755 /usr/local/libexec/predatorsensed
sudo cp psec2/daemon/local.predatorsense.daemon.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/local.predatorsense.daemon.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/local.predatorsense.daemon.plist

# 3. App
sudo rm -rf /Applications/PredatorSense.app
sudo ditto --norsrc --noextattr psec2/build/PredatorSense.app /Applications/PredatorSense.app
sudo xattr -cr /Applications/PredatorSense.app
sudo codesign --force --deep --sign - /Applications/PredatorSense.app
```

Verify:

```sh
kmutil showloaded --list-only | grep PredatorSense
echo status | nc -U /var/run/predatorsense.sock
```

The reply is JSON. A healthy machine shows `"ok":true`, `"ecPresent":true`, `"wmiPresent":true`,
real temperatures and fan RPM.

> If `wmiPresent` is `false`, the WMI device was not found. Fan control falls back to direct EC
> writes; power profiles and RGB need WMI. Check that the EC/WMI SSDTs are intact and that the kext
> loaded at all.

---

## Safety model (read before using manual fans)

The driver is built so that a crash, a hang or a forgot-to-close app cannot leave the fans stuck.

| Guard | Behaviour |
|---|---|
| **Duty floor** | 35 % minimum, enforced in the kernel |
| **Thermal ceiling** | 88 °C on the real EC sensor forces auto; releases at 78 °C (hysteresis) |
| **Watchdog** | Manual mode needs a keepalive every 2 s; 6 s of silence returns the fans to the EC |
| **Client teardown** | Daemon exit/crash reverts immediately, no timer |
| **Reconciliation** | The driver tracks what the hardware *confirmed*, not what was requested, and retries failed writes every 2 s |
| **Partial WMI failure** | If the fan-behaviour call succeeds but a speed call fails, it reverts both fans to auto |
| **No access at boot** | First EC read is 20 s after load; the first WMI call only happens when you ask for one |

Test manual mode **upward first** (90 %), then try a lower value and confirm the RPM actually drops.
If 45 % and 90 % give the same RPM, the percentage is not being honoured — stop and report it.

Emergency commands:

```sh
echo "fanmode auto" | nc -U /var/run/predatorsense.sock
sudo killall predatorsensed          # losing the client also reverts the fans
```

---

## Command reference

```sh
SOCK=/var/run/predatorsense.sock
echo status                          | nc -U $SOCK
echo "fanmode auto|manual"           | nc -U $SOCK
echo "duty <cpuPct> <gpuPct>"        | nc -U $SOCK   # 35-100
echo "turbo on|off"                  | nc -U $SOCK
echo "lcdod on|off"                  | nc -U $SOCK
echo "power low|balanced|performance"| nc -U $SOCK
echo "rgb <r> <g> <b> [zoneMask]"    | nc -U $SOCK   # 0-255; mask bits: left=1, middle=2, right=4
echo "kbpct <0-100>"                 | nc -U $SOCK
echo "kbmode <name|0-5> [speed] [brightness] [dir] [r g b]" | nc -U $SOCK
echo "kbtimeout <seconds>|off"       | nc -U $SOCK
echo "zonemap <left> <middle> <right>" | nc -U $SOCK
echo "ecread <hex>"                  | nc -U $SOCK
echo "ecwrite <hex> <hex>"           | nc -U $SOCK
echo "ecdump"                        | nc -U $SOCK
echo "wmi <methodId> <hexByte>..."   | nc -U $SOCK
```

`wmi` is the escape hatch for probing a method without rebuilding. **The byte count is the argument
width**: uint32 methods want 4 bytes, uint64 methods want 8, the keyboard descriptor wants 16. The
daemon pads short buffers to the declared width for known methods, but get it right when probing a
new one.

### Keyboard backlight mapping

The hardware's visible range is **25–100**; below 25 the LEDs are dark. The app exposes 0–100 and
converts:

```c
kbPctToHw(p) = p == 0 ? 0 : 24 + round(0.76 * p);
kbHwToPct(hw) = hw < 25 ? 0 : clamp(round((hw - 24) / 0.76), 1, 100);
```

0 is a true off. The idle re-assert is skipped when brightness is 0, so an explicit "off" holds.

---

## Power profiles

The firmware/EC enforces **PL1 = 45 W** below the OS. Raising PL1 from software does not work on
this machine (proven with MSR reads and Linux). Only PL2 is changed:

| Profile | PL1 | PL2 |
|---|---|---|
| Low | 50 % of firmware base | 65 % of firmware base |
| Balanced | firmware base (45 W) | firmware base |
| Performance | 45 W (firmware) | **90 W / 28 s** |

The driver reads MSR `0x610` back immediately and reports the **actual** limit. If the firmware has
locked the MSR (`powerLocked: true`), profiles cannot apply until the next reset — it reports that
instead of claiming success.

Do not expect a large sustained multi-core gain: the 45 W cap is the limit. The 90 W burst helps
short loads.

---

## RGB

Three zones are wired: firmware indices **1 = left, 2 = middle, 4 = right**. Index 3 is not
connected. The app's logical mask (`1/2/4`) is translated through `zoneMap`.

Effects: `static`, `breath`, `neon`, `wave`, `shifting`, `zoom`. The effect descriptor is 16 bytes;
changing it restarts the animation, which is why the daemon avoids rewriting it during active use.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `kmutil` shows no PredatorSenseEC | Kext missing/disabled in `config.plist`; check the EFI being booted, then reboot |
| Socket missing | Daemon not running: `sudo launchctl print system/local.predatorsense.daemon` |
| `wmiPresent:false` | WMI device not found; check ACPI/SSDTs and that the kext is v3.7.0+ |
| Fans stuck at one speed | `echo "fanmode auto"` then check `hwFanMode` in `status` |
| App opens but sliders do nothing | Check socket permissions (`root:admin 0660`) and `status` for errors |
| Settings reset every boot | `state.json` unwritable or daemon starting before the kext is ready |
| `powerLocked:true` | Firmware sealed the MSR; reboot. Not a bug |

Uninstall:

```sh
sudo launchctl bootout system/local.predatorsense.daemon
sudo rm /Library/LaunchDaemons/local.predatorsense.daemon.plist
sudo rm /usr/local/libexec/predatorsensed
sudo rm -rf /Applications/PredatorSense.app
# remove PredatorSenseEC.kext from the EFI and reboot
```

---

## Hard-won implementation notes

These cost days; do not repeat them:

- `OSBundleLibraries` must be `com.apple.iokit.IOACPIFamily`. Using
  `com.apple.driver.AppleACPIPlatform` **causes a boot hang**.
- `IOExternalMethodDispatch` requires an **exact** struct size match.
- Swift/C ABI: `MemoryLayout.size` excludes trailing padding; C `sizeof` includes it. Keep
  `PSECStatus` a multiple of 8 and use `MemoryLayout.stride`. A mismatch gives
  `kIOReturnBadArgument` (`0xe00002c2`) on every call.
- `gMethods[]`, the `kPSECMethod*` constants and Swift's `PSECSelector` must stay in lockstep.
- The app uses `@main`, so build with `-parse-as-library`.
- The daemon must call `restoreSettings()` **after** `listen()`, or the socket is deaf during boot.
- WMI calls must not sit behind an `if (!fEC) return` guard.
- `NSColorPanel` cannot open from a `MenuBarExtra` without `NSApp.activate(ignoringOtherApps:)`.
- `ScrollView` inside `MenuBarExtra` collapses; use a plain `VStack`.

The full reverse-engineered WMI method table, EC register map, fan ordinals and measurements are in
[`BUILD-REFERENCE.md`](BUILD-REFERENCE.md#3-reverse-engineered-acpi-wmi-interface).
