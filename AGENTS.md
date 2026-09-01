# Agent instructions

This repo configures Omarchy on a 2017 15″ MacBook Pro (MacBookPro14,3) after Omarchy is already installed and booted. If you are an AI agent running inside the installed Omarchy system, follow this file.

## Scope: what you may and may not do

**Sections 1–5 of README.md are human-only.** They happen in macOS Recovery, macOS, or the Omarchy USB installer, where no agent is running. Never attempt them, and never attempt to "help" with them from Linux:

- **Never run partitioning, formatting, or disk-erase commands.** No `mkfs`, `parted`, `sgdisk`, `fdisk`, `dd` to a disk, or `wipefs` — on any device, for any reason.
- **Never mount, modify, or write to Apple's EFI partition** (the ~300 MB vfat partition, typically `nvme0n1p1`). It holds the T1 firmware. Damaging it disables the Touch Bar, webcam, and Touch ID until macOS is reinstalled from Internet Recovery.
- The Omarchy ESP mounted at `/boot` (typically `nvme0n1p3`) is the only EFI partition you may write to, and only as described in the guide.

**Your scope is sections 6–15**: driver setup, services, keybindings, and the suspend policy. All of it is shell-driven.

## Before doing anything

Verify the T1 is healthy:

```bash
for d in /sys/bus/usb/devices/*/; do
  [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] &&
    echo "05ac:$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
done
```

- `05ac:8600 iBridge` → healthy, proceed.
- `05ac:1281` → the T1 is in recovery mode. **Stop.** No amount of Linux-side work fixes this; the user must reinstall macOS per README section 2. Tell them so.

## How to configure the machine

Prefer the automation script over transcribing README sections by hand:

```bash
./scripts/post-install.sh            # runs sections 7–15, idempotent, safe to re-run
./scripts/post-install.sh --verify   # health check only (README section 17)
```

Rules of engagement:

1. **Run `omarchy-update` first** (README §6) and reboot if it asks, before building any DKMS module.
2. **Verify, don't assume.** Every README section has an expected-output block. After each step, check for it (the script does this for you). If output doesn't match, stop and investigate rather than continuing.
3. **Ask the user for the real Wi-Fi MAC address** (from macOS: System Information → Network → Wi-Fi) if the current interface MAC starts with `00:90:4c`. Never invent or guess a MAC. Pass it as `./scripts/post-install.sh --wifi-mac AA:BB:CC:DD:EE:FF`.
4. **Warn before every reboot.** A reboot ends your session; tell the user what was done, that a reboot is needed, and to re-run you (or `--verify`) afterward. Expect up to three reboots across the full flow (after `omarchy-update`, after the audio driver, after the Wi-Fi firmware fix).
5. **Respect README section 16 ("Things not to do")** as hard constraints, notably:
   - use `modprobe.blacklist=`, never `module_blacklist=`, for the T1 modules;
   - do not install `macbook12-spi-driver-dkms`, `tiny-dfr`, `broadcom-wl`, or `mbpfan`;
   - do not use `amdgpu.dpm=0` or runtime `vga_switcheroo` `DIGD` as suspend workarounds.
6. **Suspend stays disabled** (§15). Do not unmask sleep targets or "fix" suspend; the Radeon Pro 555 does not survive resume on this machine.

## Success criteria

`./scripts/post-install.sh --verify` passes, and after a final reboot: `05ac:8600 iBridge` present, `touchbar.service` active with `SUCCESS: fnmode=0` in its journal, `/dev/video0` exists, speakers listed in `wpctl status`, and the Wi-Fi MAC is Apple's (not `00:90:4c:*`) with both `Band 1` and `Band 2` in `iw phy`.
