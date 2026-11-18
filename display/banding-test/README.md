# Explicit 8-bit framebuffer test

The active EFI config adds two WhateverGreen display properties to the Intel iGPU:

- `@0,display-link-component-bits = 01 00 00 00` (8-bit link components)
- `@0,display-pixel-component-bits = 01 00 00 00` (8-bit pixel components)

The panel EDID advertises 8 bits per primary channel. This tests whether macOS had selected an incompatible implicit link/pixel depth that contributes to gradient artifacts. WhateverGreen documents these two component-depth settings for gradient glitches. The test retains the current EDID, framebuffer ID, display-dither property, and all other settings. It does not guarantee that the compositor banding will disappear.

Pre-test config: `config-before.plist`. Rollback: double-click `Restore-Display-Config.command` and restart.

After reboot, check whether the same Music gradient is smoother. Also confirm native resolution, 144 Hz, brightness, and that the machine boots normally. If the screen is blank or unstable, boot from the backup EFI or restore the saved config.

Validation: `plutil -lint` OK; OpenCore 1.0.8 `ocvalidate` reports no issues.

References:
- WhateverGreen properties: https://github.com/acidanthera/WhateverGreen/blob/master/Manual/Sample.dsl
- Panel EDID audit: `/Volumes/Multimedia/Hackintosh/display-audit-20261006-135348/edid-decode.txt`
