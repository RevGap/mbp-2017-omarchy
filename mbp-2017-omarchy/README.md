# Omarchy on MacBookPro14,3 (2017 15" Touch Bar, T1) — reinstall plan

Written 2026-08-23 from a live diagnosis of the first install. Goal: get the
Touch Bar, webcam, and Esc/F-row back by restoring the T1 firmware via macOS,
then reinstalling Omarchy WITHOUT wiping Apple's EFI partition.

Primary source, verified by its author on **MacBookPro14,2 + kernel 7.1.8-arch1-3**:
https://github.com/nohzafk/omarchy-macbookpro-t1 (discussion: basecamp/omarchy#2457).
Clone it once you're back in Linux; this document is the plan, that repo is the toolkit.

---

## Why the first install failed (so you don't repeat it)

The T1 chip has **no firmware in ROM**. macOS writes it to the EFI System
Partition at `EFI/APPLE/EMBEDDEDOS/combined.memboot` (~30 MB). Omarchy's
whole-disk install reformatted that partition. With the file gone, the T1 sits
in DFU and enumerates as:

    05ac:1281  "Apple Mobile Device (Recovery Mode)"   <- broken (what we had)
    05ac:8600  "iBridge"                               <- healthy (the goal)

This kills four devices: Touch Bar, FaceTime webcam, Touch ID, ambient light
sensor. No Linux-side fix exists; only macOS rewrites the file.

Everything else was fine: `applespi` keyboard/trackpad, `spi::kbd_backlight`,
`gmux_backlight`, amdgpu. The only thing wrong was that the keys that normally
drive brightness live on the dead Touch Bar.

---

## Stage 0 — Before wiping (you are here)

Nothing on this install is worth saving except the two Hyprland override files
in `hypr/` next to this README (keybinds + Caps→Esc). They're already in this repo.

Confirm the plan's premise one last time:

    cat /sys/bus/usb/devices/1-3/idProduct     # expect 1281

Also note your Wi-Fi MAC for later (the repo's Wi-Fi NVRAM step wants it):

    ip link show | grep -A1 wl | grep ether

---

## Stage 1 — Reinstall macOS (restores the T1 firmware)

1. Shut down. Power on holding **Cmd + Opt + R** (Internet Recovery; gets the
   newest macOS this Mac supports). Needs Wi-Fi or Ethernet-over-USB-C.
2. Disk Utility → View → **Show All Devices** → select the top-level NVMe →
   **Erase**, format APFS, scheme GUID. This wipes Omarchy (LUKS, btrfs, all of it).
3. Quit Disk Utility → Reinstall macOS → target the new APFS volume. Let it finish
   and complete the first-boot setup (creating a user is fine; keep it minimal).
4. Install **all pending macOS updates** (System Settings → General → Software
   Update). Firmware/bridgeOS updates ship this way.
5. Verify the firmware is back. In Terminal:

       diskutil list                              # disk0s1 should be ~300 MB EFI
       sudo diskutil mount disk0s1
       ls -la /Volumes/EFI/APPLE/EMBEDDEDOS/      # must contain combined.memboot

   If `combined.memboot` is missing, stop. Re-run Software Update and re-check.
   Do not proceed to Linux until this file exists.

### Stage 1b — Back the ESP up (verbatim from nohzafk)

Do this so you never depend on macOS again if something goes wrong later.

    sudo diskutil mount disk0s1
    mkdir -p ~/esp-backup && cd ~/esp-backup
    tar -C /Volumes/EFI -cf - EFI | gzip -6 > esp-files.tar.gz
    sudo dd if=/dev/rdisk0s1 bs=1m 2>/dev/null | gzip -6 > esp-raw.img.gz
    shasum -a 256 ./*.gz > SHA256SUMS.txt
    tar tzf esp-files.tar.gz | grep combined.memboot   # must print a line

**Copy `~/esp-backup` off the machine** (USB stick, cloud, this repo — it's
~30 MB gzipped). This backup is the only thing that can save you from doing
Stage 1 again.

---

## Stage 2 — Make room for Omarchy (still in macOS)

Local Time Machine snapshots block resizing; delete them first.

    tmutil listlocalsnapshots /
    sudo tmutil deletelocalsnapshots <each-date-printed-above>
    diskutil list                                   # note the APFS container id (disk0s2)
    sudo diskutil apfs resizeContainer disk0s2 110g # leaves ~350 GB free on the 465 GB drive
    diskutil list                                   # disk0s1 must STILL be ~300 MB

110 GB for macOS is generous; 60g works if you'd rather give Linux more. Don't
go below what macOS currently uses plus ~15 GB.

If resizing stalls, run it detached (from another machine over SSH):

    ssh host 'nohup setsid bash -c "sudo diskutil apfs resizeContainer disk0s2 110g \
      > /tmp/resize.log 2>&1" >/dev/null 2>&1 & echo started'

T1 Macs have **no Secure Boot / Startup Security Utility** — that arrived with
T2. Skip any Omarchy instruction about disabling it.

---

## Stage 3 — Install Omarchy into the free space

1. Write the Omarchy ISO to USB. Plug in, power on holding **Option**, pick the
   orange **EFI Boot** entry.
2. In the installer choose **Free space install** — NOT the whole-drive option.
   (Verify this option exists in the installer version you're using before
   confirming anything. It was present for nohzafk; I could not confirm it from
   the installed 4.0.0 system because the installer lives on the ISO.)
3. **Read the confirmation screen.** If it lists the ~300 MB EFI partition as
   being formatted, ABORT. Only the free space should be touched.
4. Keep LUKS encryption on. Finish the install and boot into Omarchy.

Expected layout afterwards:

    nvme0n1p1   300M  vfat          Apple ESP  — UNTOUCHED, holds combined.memboot
    nvme0n1p2  ~110G  apfs          macOS (still bootable via Option at power-on)
    nvme0n1p3     2G  vfat  /boot   Omarchy's own ESP
    nvme0n1p4   rest  crypto_LUKS   Omarchy root

### Gate — is the T1 alive?

    for d in /sys/bus/usb/devices/*/; do
      [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] &&
        echo "05ac:$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
    done

You want `05ac:8600 iBridge`. If it still says `1281`, the Apple ESP got
formatted — restore it from the Stage 1b backup (`dd` the raw image back onto
nvme0n1p1) before going any further. Nothing below works without 8600.

---

## Stage 4 — Post-install fixes (from nohzafk's repo)

    git clone https://github.com/nohzafk/omarchy-macbookpro-t1
    cd omarchy-macbookpro-t1

Read its README once through — it may have moved on since this plan was written.

### 4a. Make Omarchy show up in the Option boot menu

    sudo mkdir -p /boot/EFI/BOOT
    sudo cp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI

### 4b. Suspend/resume kernel parameter

    sudo tee /etc/limine-entry-tool.d/macbook-t1.conf <<'EOF2'
    KERNEL_CMDLINE[default]+=" pcie_ports=compat"
    EOF2
    sudo limine-update

### 4c. Touch Bar driver (DKMS)

Do NOT install `tiny-dfr` or rely on mainline `hid-appletb-*` — those bind
`05ac:8302` (T2). The T1 needs `apple-ibridge` which binds `0x8600`.

    sudo pacman -S --needed linux-headers dkms
    sudo mkdir -p /usr/src/appleibridge-0.1
    sudo cp drivers/appleibridge/{*.c,*.h,Makefile,dkms.conf} /usr/src/appleibridge-0.1/
    sudo dkms add     -m appleibridge -v 0.1
    sudo dkms build   -m appleibridge -v 0.1
    sudo dkms install -m appleibridge -v 0.1

    sudo install -m 755 systemd/touchbar-enable.sh /usr/local/sbin/
    sudo install -m 644 systemd/touchbar.service   /etc/systemd/system/
    sudo systemctl daemon-reload && sudo systemctl enable --now touchbar.service
    journalctl -u touchbar.service -n 20          # want: SUCCESS: fnmode=0 idle=-1 dim=-1

The service exists because `hid-sensor-hub` grabs the Touch Bar's HID interface
at boot before the iBridge driver can. If the Touch Bar is dark but the service
"succeeded", do the rebind by hand and check the HID id matches:

    ls /sys/bus/hid/devices/ | grep 8600
    DEV=0003:05AC:8600.0002
    printf '%s' "$DEV" | sudo tee /sys/bus/hid/drivers/hid-sensor-hub/unbind  >/dev/null
    printf '%s' "$DEV" | sudo tee /sys/bus/hid/drivers/apple-ibridge-hid/bind >/dev/null

If the DKMS build fails against a newer kernel than 7.1.8, check the repo's
issues first; the upstream driver fork is
https://github.com/F13-Kr1pt0n/macbook-pro-touchbar-driver.

### 4d. Audio (Cirrus CS8409 — speakers and mic are silent without this)

    sudo pacman -S --needed base-devel git wget dkms linux-headers
    git clone https://github.com/davidjo/snd_hda_macbookpro.git
    cd snd_hda_macbookpro
    sudo ./install.cirrus.driver.sh -i
    sudo reboot
    # after reboot, mic is muted by default:
    wpctl set-mute  @DEFAULT_AUDIO_SOURCE@ 0
    wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 100%

### 4e. Wi-Fi (BCM43602 — works, but weak without its NVRAM file)

Follow the repo's Wi-Fi section exactly; it needs the MAC you noted in Stage 0.
nohzafk measured −74 → −42 dBm after the fix. Do NOT install `broadcom-wl`.
Then prefer the 5 GHz SSID:

    nmcli -f NAME,TYPE,AUTOCONNECT-PRIORITY connection show
    nmcli connection modify "<YOUR_SSID>_5G" connection.autoconnect-priority 10

### 4f. Webcam

Needs nothing once the T1 is at 8600 — `uvcvideo` picks it up. Test with
`omarchy` screen-recording or any browser.

### 4g. Things the repo says NOT to do

- No `mbpfan` — the SMC runs the fans in firmware.
- No `s2idle` hacks — the NVMe `d3cold_allowed=0` fix is already applied.
- No `macbook12-spi-driver-dkms` from AUR — `applespi` is mainline; the AUR
  package is broken and conflicts. If it got installed somehow:

      sudo dkms remove -m macbook12-spi-driver -v 0+git.315 --all
      sudo pacman -R macbook12-spi-driver-dkms

---

## Stage 5 — Restore the Hyprland overrides

Copy `hypr/bindings.lua` and `hypr/input.lua` from this repo over
`~/.config/hypr/`, then `hyprctl reload && hyprctl configerrors`.

What they give you even with the Touch Bar working:

| Key | Action |
|---|---|
| SUPER CTRL ↑ / ↓ | keyboard backlight up / down |
| SUPER CTRL \ | keyboard backlight cycle |
| SUPER SHIFT CTRL ↑ / ↓ | display brightness up / down |
| Caps Lock | Escape (Compose moved to right Alt) |

With the Touch Bar alive you'll also have a real Esc and F1–F12 on the bar;
keep the Caps→Esc anyway, it's nicer.

---

## What still won't work

- **Touch ID** — no Linux driver exists. Nothing to do.
- **Ambient light sensor** — module builds, no userspace uses it.
- **15" dGPU caveat** — nohzafk verified on the 13" (Intel-only). The 15" 14,3
  has a Radeon Pro via `apple_gmux` + `amdgpu`. That all worked on the first
  install, so it should be unaffected, but if graphics misbehave after
  `pcie_ports=compat`, that parameter is the first suspect.

---

## Quick reference — the one check that matters

    cat /sys/bus/usb/devices/1-3/idProduct
    # 8600 = T1 alive, proceed.   1281 = firmware missing, go back to Stage 1 / restore ESP backup.
