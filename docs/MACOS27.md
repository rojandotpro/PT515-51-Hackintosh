# macOS 27 and the future of this machine

**Short answer: macOS 26 Tahoe is the end of the line for the PT515-51.** Do not plan a macOS 27
migration for daily use.

## First, confirm what you are running

`sw_vers` is the only authority:

```sh
sw_vers
# ProductVersion: 26.7.3
# BuildVersion:   25G342
```

A **26.7.x** point update is still Tahoe, not macOS 27. Safari has its own version series (27.x)
and appears in Software Update next to the OS; seeing "27" there does not mean the operating
system is 27. If `sw_vers` reports 26.x, every patch in this repository still applies.

---

---

## What is established

Apple's macOS 27 — reported under the codename **"Golden Gate"** — is **Apple Silicon only**.
There is no Intel support of any kind, and the OpenCore Legacy Patcher project has stated it will
**not** support it.

That means no amount of EFI work makes this laptop run macOS 27 natively. The kernel, the
frameworks and the GPU drivers are all built for arm64.

## Community workarounds, and why they do not apply here

Two experimental projects were examined in October/November 2026. Both are real, both are early,
and neither supports this hardware.

### `hao-patcher` / `hao-runtime`

An experimental **ARM → x86 translation** layer intended to let Intel Macs run Apple Silicon-only
macOS releases.

- Status at review: **pre-alpha**, no releases.
- Tested by its author only on **MacBookPro9,2** (Ivy Bridge, Intel HD 4000).
- Requires a supported GPU path; the UHD 630 is far outside anything it has been tried on.

### NullMoth "Liberator"

An **NVIDIA driver project** providing a Metal → Vulkan (NVK) path for **Turing and newer** GPUs.

- Irrelevant twice over: the RTX 2060/2080 Max-Q in this chassis is **physically dead** (see
  below), and the UHD 630 is Intel, so the project targets neither GPU present.

### The "Tahoe donor frameworks" idea

Copying frameworks from Tahoe into a Golden Gate install to satisfy Intel binaries does not work:
the translation boundary is not a file-copy problem, and the graphics stack in particular is
compiled for a different ISA. Treat any guide that suggests this as speculation.

---

## Why this laptop is a particularly bad candidate

| Obstacle | Reality |
|---|---|
| **No Intel support** | macOS 27 ships arm64 only; OCLP will not patch it. |
| **Dead dGPU** | `lspci` under Linux shows **no NVIDIA device and no PEG root port**. It is dead in silicon — no VBIOS, BIOS or ACPI change reaches it. |
| **iGPU driver** | Apple's Intel graphics drivers are the first thing removed from an Apple Silicon-only OS. Even a working translator would need a driver that no longer exists. |
| **No AVX-512-class headroom** | Coffee Lake mobile has no AVX-512, and translation layers assume modern instructions. |
| **Performance** | Any ARM→x86 translation costs a large, unpredictable share of performance on a 45 W 6-core. |

## Recommendation

1. **Keep macOS Tahoe 26.7.x as the daily driver.** It works, it is supported by the current kext
   ecosystem, and every fix in this repository applies to it.
2. Pin a known-good installer and a full EFI backup. Keep them offline.
3. If you want to experiment with macOS 27, do it on a **spare disk** with the expectation that it
   will not boot to a usable desktop. Do not risk the working install.
4. Watch the two projects above, but only trust a release that explicitly lists this GPU and this
   chipset. "Pre-alpha on a 2012 MacBook" is not a portent.

Tahoe is a good place to stop. The machine is fully functional; the limit is Apple's, not the
configuration's.
