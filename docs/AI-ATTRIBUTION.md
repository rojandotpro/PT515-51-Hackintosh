# AI assistance, authorship and licensing

This repository was built by a human, with AI assistants used as tools. That sentence is the whole
policy, but it deserves detail — both because it is honest and because "was this written by AI?" is
now a licensing question, not only a credibility one.

**This page is a disclosure and a practical position, not legal advice.** If you plan to reuse this
work commercially, read the licences yourself and take your own advice.

---

## What was used

| Assistant | Provider | How it was used here |
|---|---|---|
| **ChatGPT** | OpenAI | Research, log reading, ACPI/ASL interpretation, shell and Python scripting, config diffing, one Wi-Fi repair session, drafting |
| **Claude** | Anthropic | Code review, documentation structure and editing, reverse-engineering notes, this repository's guides |
| **Codex** | OpenAI | Small code-generation and refactoring tasks alongside ChatGPT |

Different model versions were used over the life of the project. Naming a version would be
misleading, because the work spans sessions across several releases; the providers and products
above are accurate.

They were used for:

- explaining unfamiliar ACPI, IOKit and CoreAudio behaviour,
- turning logs and dumps into readable summaries,
- drafting code, scripts, documentation and commit messages,
- proposing hypotheses and test plans,
- reviewing diffs and spotting inconsistencies.

They were **not** used as a source of hardware facts. Every value, address, pin, method ID, power
limit and register in this repository was measured on the physical machine or read from its
firmware. Where a claim could not be tested, the documentation says so.

---

## What the human did

The work that makes this repository trustworthy is not the prose:

- disassembling and reading the firmware's own ACPI methods,
- capturing USB, EC, MSR and codec data from Linux and macOS,
- deciding which hypotheses to test and running every test,
- writing and debugging the kext, daemon and app against real hardware,
- verifying every enabled kext, SSDT and driver against a booting system,
- rejecting the approaches that looked right and were wrong,
- deciding what to publish, what to sanitize and what to leave out.

AI produced drafts. The machine produced facts. The human decided.

---

## Where the AI was wrong

This is the part most disclosures omit, and it is the useful part. The project's recurring failure
mode was **confident inference from partial data** — an AI (and sometimes a human) reasoning from a
similar laptop instead of from this one.

Examples that were tested and disproved:

| Suggestion | What the hardware showed |
|---|---|
| PL2 is the firmware default, PL1 can be raised | The EC enforces PL1 = 45 W below the OS; only PL2 is writable |
| A "richer" AppleALC layout would sound better | The alternative layout killed the internal microphone |
| The trackpad should be interrupt-driven | Interrupt mode broke input; polling is correct on `I2C1.TPD0` |
| The panel override should declare 10-bit colour | The native EDID is 8-bit; the claim was reverted |
| A BIOS setting could revive the dGPU | No NVIDIA device and no PEG root port exist in PCI |
| Fn/media keys must be reachable through EC or WMI | No notify, no EC change, no HID event; firmware-only |
| A generated `config.plist` variant would add 90 Hz | It was invalid or wrong; the working EDID was built from the panel's own data |

The full list, with evidence, is in
[`BUILD-REFERENCE.md §12`](BUILD-REFERENCE.md#12-rejected-approaches--do-not-retry-without-new-evidence).
Two AI-generated configuration files are explicitly marked as **do not use** in that section. They
remain in the record as evidence, not as recommendations.

---

## Licensing position

### The MIT licence covers the human-authored work

[`LICENSE`](../LICENSE) applies to the original code and documentation in this repository: the
PredatorSense stack under `psec2/`, the AppleALC layout modifications under `audio/`, the scripts
under `tools/`, and the documents under `docs/`.

That includes the human contributions of selection, structure, editing, testing and correction, and
the code and text written or substantially revised by the maintainer.

### AI-generated material

Copyright rules for AI output differ by country. In the United States, the Copyright Office requires
human authorship: material generated purely by a model, with no human creative contribution, is not
registrable. Where a human selects, arranges, edits or substantially rewrites output, the human
contribution can be protected — but the scope is fact-specific.

The practical position taken here:

- **No claim is made that every sentence or line is individually copyrightable.** Some passages began
  as model output.
- **The repository as a whole is offered under MIT** by its maintainer, who directed the work,
  verified it and accepts responsibility for it. You may reuse it on those terms.
- **No warranty of title is given** beyond what MIT implies. If you need clean-room certainty for a
  commercial derivative, treat the text as technical reference and write your own prose.
- **No model was asked to reproduce copyrighted text**, and no vendor source code, decompiled binary
  or proprietary document is redistributed here.

### Interface facts are not vendor code

The ACPI-WMI method IDs, buffer widths, EC offsets and sensor mappings documented here are
**functional interface facts** discovered by observing the machine. They are the kind of
interoperability information clean-room reverse engineering exists to produce. No Acer binary,
installer, driver, image or asset is included.

### Third-party components keep their own licences

OpenCore, the Acidanthera kexts, VoodooI2C, VoodooPS2, OpenIntelWireless, USBToolBox and the rest
are redistributed as unmodified release binaries under their upstream licences. See
[`NOTICE.md`](../NOTICE.md) for the list and links. The MIT licence here does not override them.

### Apple

No Apple software, installer, IPSW, recovery image or root patch is distributed in this repository.
macOS is Apple's, licensed only for Apple-branded hardware. This project documents what was done to
a machine the maintainer owns; it does not grant you a macOS licence.

### Trademarks and naming

**PredatorSense**, **Predator** and **Acer** are trademarks of Acer Incorporated. **macOS**,
**MacBookPro** and **Apple** are trademarks of Apple Inc. **ChatGPT** and **Codex** are trademarks of
OpenAI. **Claude** is a trademark of Anthropic.

The names are used **nominatively** — to identify the vendor feature being replaced, the platform
being documented, or the tools that were used. This project is **unofficial and unaffiliated**: it is
not endorsed by, sponsored by, or connected to Acer, Apple, OpenAI or Anthropic. No vendor logo or
artwork is redistributed. The replacement app is an independent implementation with its own icon and
UI.

If you fork this for another laptop, keep the same discipline: name the vendor feature you are
replacing, state that you are unaffiliated, and ship your own code and artwork.

### Assistant terms of use

The assistants were used through their normal consumer or developer products, under their published
terms. This project does not redistribute model weights, bypass usage limits, or claim the assistants
as authors. Nothing here implies that OpenAI or Anthropic endorses the result.

Attribution to a model is not required by those terms. It is included because a reader deserves to
know how the material was produced, and because the errors documented above are part of the
engineering record.

---

## If you reuse this

| You want to… | Do this |
|---|---|
| Learn from it | Read it; no permission needed |
| Copy code or docs into your project | Keep the MIT notice and [`NOTICE.md`](../NOTICE.md) obligations for third-party binaries |
| Publish a derivative | State that it is unofficial, keep trademark use nominative, do not use vendor logos |
| Use it commercially | Review the third-party licences; MIT here is permissive but does not relicense OpenCore or the kexts |
| Cite it | Link the repository and, if useful, the commit hash |
| Ask about a specific file | Open an issue; the provenance of anything unclear will be stated plainly |

---

## The short version

> AI wrote drafts. A human measured, tested, corrected and published. The MIT licence covers the
> repository as published; third-party binaries keep their own licences; vendor names are used only
> to say what this replaces.
