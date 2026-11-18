# Doing this with AI — the method that actually worked

This project was built with AI assistants in the loop: ChatGPT, Claude and Codex were used for
research, log reading, ACPI interpretation, script writing, config diffing and drafting. They were
**not** used as a source of hardware facts.

That distinction is the whole method. This page explains it so you can repeat it on your own
machine.

---

## The one rule

> **The machine is the source of truth. The AI is a fast reader, writer and hypothesis generator.**

Every time this project trusted a plausible inference over a measurement, it was wrong. Every
correction came from hardware:

| Wrong inference | What measurement showed |
|---|---|
| "PL2 must be 75 W, that's the firmware default" | MSR reads showed the EC enforces **PL1 45 W** below the OS; only PL2 changes |
| "Layout 33 looks like it has more speaker pins, try it" | It killed the internal mic — the mic is on `0x13`/`0x1b`, layout 23 |
| "The trackpad must be interrupt-driven, polling is a workaround" | Interrupt mode broke input; polling is correct on `I2C1.TPD0` |
| "The panel override should declare 10-bit colour" | The native EDID is 8-bit; the 10-bit claim was reverted |
| "The dGPU is disabled, maybe a BIOS setting brings it back" | `lspci` shows **no NVIDIA device and no PEG root port** — dead in silicon |
| "Fn keys must be reachable through EC or WMI" | No notify, no EC change, no HID event; the firmware handles them |

The pattern: **confident inference from partial data**. AI is very good at producing that. Your job
is to make it cheap to disprove.

---

## The loop

Use this for every change, large or small:

1. **Measure.** Capture the current state before touching anything (`ioreg`, `kmutil showloaded`,
   `pmset -g`, `acpidump`, EC reads, a Linux live USB).
2. **Hypothesise.** Ask the AI for 2–3 candidate explanations, not one answer.
3. **Design the smallest test.** One variable. One reboot. A rollback path.
4. **Test on hardware.** Keep a known-good USB and a copy of the working EFI.
5. **Record the result** — including the failures. A negative result is knowledge.
6. **Only then** update the config/docs.

If a step cannot be tested, it is a guess. Label it as one in the docs.

---

## Ground truth you can collect

### From macOS

```sh
# Loaded third-party kexts and versions
kmutil showloaded --list-only | grep -v com.apple

# Everything the EC/WMI driver publishes
ioreg -rn PredatorSenseEC -l

# Hardware, battery, display, audio
system_profiler SPHardwareDataType SPDisplaysDataType SPAudioDataType SPPowerDataType

# Power management and assertions
pmset -g custom
pmset -g assertions
pmset -g therm

# Kernel log (use a predicate, not the whole log)
log show --last 10m --predicate 'process == "predatorsensed"'
```

### From a Linux live USB

This was the single most valuable technique in the project. Linux exposes hardware that macOS
hides:

```sh
lspci -nnk -v
lsusb -t
sudo dmidecode -t system -t battery
sudo acpidump -o tables
sudo dmesg | grep -i -E 'i2c|elan|alc|nvidia|thunderbolt'
sudo rdmsr 0x610 0x1FC 0x690     # needs msr-tools
```

Use a live image that does not touch the internal disk. Capture the output to a text file and
bring it back.

### From OpenCore

- Set `Misc → Debug → Target` to `67` temporarily and read `OpenCore-YYYY-MM-DD.txt` from the ESP.
- `Misc → Debug → DisplayLevel` controls screen logging.
- A verbose boot (`-v`) plus a photo of the last screen is often enough to identify a stall.

---

## Prompt patterns that work

These are the shapes that produced useful results. Adapt the specifics.

### 1. Read a dump, cite offsets

> Here is an ACPI dump (`acpidump` output / `iasl -d` result). List every method under
> `\_SB.PCI0.WMID`, its argument widths, and what each return value means. Quote the exact AML
> offset for each claim. If something is ambiguous, say "unknown" instead of guessing.

### 2. Diff two configs, functional changes only

> Compare these two OpenCore `config.plist` files. List only changes that can affect boot,
> kext loading, power management or devices. Ignore whitespace and ordering. For each change,
> say what it does and whether it is safe to test.

### 3. Write a measurement script

> Write a zsh script that reads EC register `0x93` every 250 ms for 60 seconds, prints a timestamp
> and value, and writes to `~/ec-93.csv`. Do not write to the EC. Handle the case where the tool
> is missing.

### 4. Read a panic or a log

> Here is a panic backtrace / unified-log excerpt. Identify the faulting kext or process, the
> likely trigger, and the three smallest experiments that would confirm or eliminate each cause.
> Do not propose changing more than one variable per boot.

### 5. Challenge the hypothesis

> You suggested X. What evidence would prove X wrong? What else could produce the same symptom?
> Give me a test that distinguishes them.

### 6. Explain a reverse-engineered value

> We measured `kbPctToHw(p) = p == 0 ? 0 : 24 + round(0.76 * p)`. Explain what hardware behaviour
> this implies, what the 24 offset means, and what would break if we used a linear 0–100 map.

### 7. Keep context for the next session

> Write a handover document for another engineer (or AI) covering: current state, what was
> verified this session, what was changed, what was reverted and why, and the next three
> experiments in priority order. Include exact file paths and commands.

---

## Guardrails

- **Never paste real serials, UUIDs, MAC addresses or Apple account data** into a chat. Replace
  them with placeholders first. This repository's config ships placeholders for that reason.
- **Never let an AI invent register values, MSR values or ACPI offsets.** Ask for the source and
  verify it yourself.
- **Back up the EFI before every experiment.** Keep one USB that boots.
- **One change per boot.** If two things change, you learn nothing when it fails.
- **Be suspicious of confident prose.** Ask "how would we know?" and "what would falsify that?"
- **Do not run random root patchers, kexts or scripts from a chat answer.** Check the upstream
  repository, the release, the checksum and the licence.
- **Keep the failures.** The rejected-approaches section is more valuable than the success list.

---

## What the AI was genuinely good at

- Reading 250 KB of decompiled ACPI and finding the relevant methods.
- Explaining what an unknown `ioreg` property probably means, with caveats.
- Writing repeatable measurement scripts and log filters.
- Diffing two 90 KB XML configs and summarising functional changes.
- Turning a messy session into a handover document.
- Generating test matrices and checklists.
- Catching inconsistencies between docs and the live system.

## What it was bad at

- Knowing this laptop's hardware without being told.
- Resisting a plausible story when the data was thin.
- Keeping track of what had already been tried across sessions.
- Anything that required the physical machine (fan noise, panel banding, key presses).
- Estimating performance without measurements.

The fix for the first three is the same: **write everything down, including what failed**, and feed
that document back at the start of each session. This repository is that document.

---

## A reusable session opener

Paste this at the start of a new AI session:

> I am working on an Acer Predator Triton 500 PT515-51 Hackintosh running macOS Tahoe. The project
> reference is in `docs/BUILD-REFERENCE.md`; read the "Rejected approaches" section before
> suggesting anything. Treat hardware measurements as the only source of truth. When you propose a
> change, give me: the exact file and key, the reason, the rollback, and the smallest test. If you
> do not know a hardware detail, say so. Do not invent register values or ACPI offsets.

That single paragraph prevents most of the wasted cycles.
