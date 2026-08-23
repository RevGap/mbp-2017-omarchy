# Omarchy on MacBookPro14,3 (2017 15-inch Touch Bar, T1)

A tested install and recovery guide for running **Omarchy on the 2017 15-inch MacBook Pro (MacBookPro14,3)** while preserving the Apple T1 firmware and restoring the Touch Bar, webcam, Wi-Fi, audio, keyboard backlight, and useful Hyprland bindings.

This guide was built from a live install on a **MacBookPro14,3 with Radeon Pro 555** and Omarchy running **kernel 7.1.8-arch1-3**.

Primary upstream source/toolkit:

- https://github.com/nohzafk/omarchy-macbookpro-t1
- Related Omarchy discussion: `basecamp/omarchy#2457`

The upstream work was verified on a **MacBookPro14,2 (13-inch, Intel-only)**. This repo adds the installation details and the **15-inch Radeon-specific findings** discovered on a real MacBookPro14,3.

---

## Current tested status on MacBookPro14,3

| Hardware / feature | Status | Notes |
|---|---|---|
| T1 / iBridge | ✅ | `05ac:8600` after preserving Apple's ESP |
| Touch Bar | ✅ | Esc + F1-F12, persistent across reboot |
| Webcam | ✅ | `uvcvideo`, `/dev/video0` + `/dev/video1` |
| Keyboard / trackpad | ✅ | Mainline `applespi` |
| Keyboard backlight | ✅ | `spi::kbd_backlight`; boot persistence included below |
| Display brightness | ✅ | `gmux_backlight`; Hyprland shortcut included |
| Wi-Fi 2.4 + 5 GHz | ✅ | BCM43602 NVRAM fix; real Apple MAC restored |
| Bluetooth | ✅ | No additional work required |
| Speakers | ✅ | `snd_hda_macbookpro` DKMS driver |
| Microphone | ✅/⚠️ | Detected; may need PipeWire unmute/volume adjustment |
| Radeon Pro 555 | ✅ awake | `amdgpu`, internal panel driven by dGPU |
| Deep suspend / S3 | ❌ | Radeon fails SMU firmware reload on resume; disable suspend |
| Touch ID | ❌ | No Linux driver |
| Ambient light sensor | ⚪ | Driver can load; useful userspace support not established |

---

# 1. The rule that matters most: never wipe Apple's EFI partition

The T1 firmware is not self-contained in ROM. macOS places the firmware on Apple's EFI System Partition, including:

```text
EFI/APPLE/EMBEDDEDOS/combined.memboot
```

If a Linux installer reformats Apple's ESP, the T1 falls into recovery mode:

```text
05ac:1281  Apple Mobile Device (Recovery Mode)   # broken
05ac:8600  iBridge                               # healthy
```

When the T1 is at `1281`, the Touch Bar, webcam, Touch ID, and ambient-light hardware disappear together. A Linux driver cannot repair missing T1 firmware; macOS must restore it (or you must restore a known-good ESP backup).

Check from Linux:

```bash
for d in /sys/bus/usb/devices/*/; do
  [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] &&
    echo "05ac:$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
done
```

Do not continue with Touch Bar troubleshooting unless you have:

```text
05ac:8600 iBridge
```

---

# 2. Recover a machine whose T1 is already at `05ac:1281`

## 2.1 Reinstall macOS through Internet Recovery

1. Power off.
2. Power on holding **Command + Option + R**.
3. Open Disk Utility.
4. Choose **View → Show All Devices**.
5. Select the top-level internal Apple SSD.
6. Erase it as:

```text
Name: Macintosh HD
Format: APFS
Scheme: GUID Partition Map
```

7. Quit Disk Utility and reinstall macOS onto `Macintosh HD`.
8. Complete enough of first-boot setup to reach the desktop.
9. Install **all available macOS updates** before proceeding.

## 2.2 Verify the T1 firmware was restored

In macOS Terminal:

```bash
diskutil list
sudo diskutil mount disk0s1
find /Volumes/EFI -maxdepth 5 -type f | grep -E 'combined\.memboot|MBP143\.fd'
system_profiler SPiBridgeDataType
```

On the tested machine, the important file appeared at:

```text
/Volumes/EFI/EFI/APPLE/EMBEDDEDOS/combined.memboot
```

and `system_profiler` reported:

```text
Model Name: Apple T1 Security Chip
```

Do not reinstall Linux until `combined.memboot` exists.

---

# 3. Back up Apple's ESP before touching the partition layout again

From macOS:

```bash
sudo diskutil mount disk0s1
mkdir -p ~/esp-backup && cd ~/esp-backup

tar -C /Volumes/EFI -cf - EFI | gzip -6 > esp-files.tar.gz
sudo dd if=/dev/rdisk0s1 bs=1m 2>/dev/null | gzip -6 > esp-raw.img.gz
shasum -a 256 ./*.gz > SHA256SUMS.txt

tar tzf esp-files.tar.gz | grep combined.memboot
```

Copy `~/esp-backup` somewhere **off the machine** (iCloud Drive, external storage, another computer, etc.).

The file-level tar backup is the easiest way to verify that `combined.memboot` is actually present. Keep the raw image as an emergency restore option.

**Do not commit your machine-specific ESP backup to a public repository.**

---

# 4. Shrink macOS and leave free space for Omarchy

Delete local Time Machine snapshots first:

```bash
tmutil listlocalsnapshots /
sudo tmutil deletelocalsnapshots <each-date-if-any>
```

Confirm the APFS physical store with:

```bash
diskutil list
```

On the tested 500 GB drive, macOS was reduced to 110 GB:

```bash
sudo diskutil apfs resizeContainer disk0s2 110g
```

Then verify:

```bash
diskutil list
```

Expected shape:

```text
disk0s1   ~314.6 MB   EFI / Apple ESP
disk0s2   ~110 GB     APFS / macOS
           ~390 GB     free space
```

**The Apple EFI partition must remain untouched.**

T1 Macs do not have the T2-era Secure Boot / Startup Security Utility workflow, so skip T2-specific instructions about disabling Secure Boot.

---

# 5. Install Omarchy into free space — never use whole-disk install

1. Boot the Omarchy USB while holding **Option**.
2. Select the orange **EFI Boot** entry.
3. Select the internal Apple NVMe drive.
4. Choose:

```text
Free space install (alongside existing data)
```

5. Do **not** choose full-disk install.
6. Read the confirmation screen before committing.
7. It should say it is installing into the unallocated/free space.
8. Abort if the existing ~314 MB Apple ESP is listed for formatting or modification.
9. Keep LUKS encryption enabled.

A healthy resulting layout looks approximately like:

```text
nvme0n1p1   ~300M  vfat          Apple ESP — DO NOT FORMAT
nvme0n1p2   ~110G  apfs          macOS
nvme0n1p3     2G   vfat  /boot   Omarchy ESP
nvme0n1p4    rest  crypto_LUKS   Omarchy root
```

Immediately after first boot, verify the T1:

```bash
for d in /sys/bus/usb/devices/*/; do
  [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] &&
    echo "05ac:$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
done
```

You want:

```text
05ac:8600 iBridge
```

---

# 6. Update Omarchy before building hardware DKMS modules

On a fresh installation, update Omarchy first so DKMS is built against the kernel you actually intend to run:

```bash
omarchy-update
```

Reboot if requested, then check:

```bash
uname -r
```

The configuration documented here was tested on:

```text
7.1.8-arch1-3
```

---

# 7. Make Omarchy visible in Apple's Option boot picker

Omarchy's Limine install may rely on an NVRAM boot entry rather than the generic fallback path Apple's picker expects.

```bash
sudo mkdir -p /boot/EFI/BOOT
sudo cp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI
```

Do not create a second `limine.conf` beside `BOOTX64.EFI`.

---

# 8. Remove Omarchy's obsolete MacBook SPI DKMS package

Omarchy may install `macbook12-spi-driver-dkms`. On the tested current kernel it fails to build, while keyboard/trackpad support is already provided by mainline `applespi`.

Remove it:

```bash
sudo dkms remove -m macbook12-spi-driver -v 0+git.315 --all
sudo pacman -R macbook12-spi-driver-dkms
modinfo -n applespi
```

`modinfo` should resolve to the kernel's own `applespi.ko`.

Do not install the old AUR driver again.

---

# 9. Install the T1 Touch Bar driver

Clone the upstream toolkit:

```bash
cd ~
git clone https://github.com/nohzafk/omarchy-macbookpro-t1.git
cd omarchy-macbookpro-t1
```

Install headers and DKMS:

```bash
sudo pacman -S --needed linux-headers dkms
sudo mkdir -p /usr/src/appleibridge-0.1
sudo cp drivers/appleibridge/{*.c,*.h,Makefile,dkms.conf} /usr/src/appleibridge-0.1/

sudo dkms add     -m appleibridge -v 0.1
sudo dkms build   -m appleibridge -v 0.1
sudo dkms install -m appleibridge -v 0.1
```

Install the late-loading Touch Bar service:

```bash
sudo install -m 755 systemd/touchbar-enable.sh /usr/local/sbin/
sudo install -m 644 systemd/touchbar.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now touchbar.service
```

Verify:

```bash
journalctl -u touchbar.service -n 30 --no-pager
```

Healthy output includes:

```text
apple_ibridge loaded (keyboard mode)
apple_ib_tb loaded
unbound from hid-sensor-hub
bound to apple-ibridge-hid
SUCCESS: fnmode=0 idle=-1 dim=-1
```

## 9.1 Critical persistence fix: use `modprobe.blacklist`, not `module_blacklist`

Without a blacklist, `apple_ibridge` can autoload early with `tb_mode=auto`, attempt a USB configuration switch, and deadlock during boot/resume. The upstream service intentionally loads the module **late** using `insmod` with `tb_mode_param=keyboard`.

Create the Limine drop-in:

```bash
sudo tee /etc/limine-entry-tool.d/macbook-t1.conf <<'EOF'
KERNEL_CMDLINE[default]+=" pcie_ports=compat modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als"
EOF

sudo limine-update
```

Then reboot and confirm:

```bash
cat /proc/cmdline
journalctl -b -u touchbar.service --no-pager
```

### Why `module_blacklist=` is wrong here

Do **not** use:

```text
module_blacklist=apple_ibridge,apple_ib_tb,apple_ib_als
```

The kernel-level blacklist also blocks the service's deliberate `insmod`, producing:

```text
insmod: ERROR: could not insert module ... Operation not permitted
```

`modprobe.blacklist=` prevents automatic module loading while still allowing the service's direct `insmod` path.

---

# 10. Audio — Cirrus CS8409

Install the maintained MacBook Pro audio driver:

```bash
sudo pacman -S --needed base-devel git wget dkms linux-headers
cd ~
git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro
sudo ./install.cirrus.driver.sh -i
sudo reboot
```

After reboot, if the microphone is muted:

```bash
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 100%
```

Verify with:

```bash
wpctl status
```

---

# 11. Wi-Fi — BCM43602 NVRAM fix

Without the board NVRAM file, Linux may expose the Broadcom placeholder MAC:

```text
00:90:4c:xx:xx:xx
```

Check:

```bash
ip link | grep -A1 -E 'wl'
```

If the address starts with `00:90:4c`, get the **real Wi-Fi MAC from macOS**:

**System Information → Network → Wi-Fi**

Do not copy the Linux placeholder MAC into the NVRAM file.

From the upstream toolkit:

```bash
cd ~/omarchy-macbookpro-t1/firmware
sed -i 's/^macaddr=.*/macaddr=AA:BB:CC:DD:EE:FF/' brcmfmac43602-pcie.txt
sudo cp brcmfmac43602-pcie.txt /lib/firmware/brcm/
sudo reboot
```

Replace `AA:BB:CC:DD:EE:FF` with your own Apple Wi-Fi MAC.

Verify after reboot (interface name may differ):

```bash
ip link | grep -A1 -E 'wl'
iw phy | grep Band
iw dev <wifi-interface> link
```

Healthy behavior should show:

- your real Apple MAC, not `00:90:4c:*`
- both `Band 1` and `Band 2`
- 5 GHz frequencies when connected to a 5 GHz AP (for example 5xxx MHz)

On the tested MacBookPro14,3, the repaired connection reached 5 GHz with link rates in the hundreds of Mbit/s.

Do not install `broadcom-wl` for this configuration.

---

# 12. Webcam

Once the T1 is healthy (`05ac:8600`), the webcam uses mainline `uvcvideo`.

Verify:

```bash
lsmod | grep uvcvideo
ls /dev/video* 2>/dev/null
```

The tested system exposed `/dev/video0` and `/dev/video1`.

---

# 13. Keyboard backlight

The actual backlight device is provided by the existing SPI keyboard stack:

```bash
ls /sys/class/leds
cat /sys/class/leds/spi::kbd_backlight/max_brightness
```

Test it directly:

```bash
brightnessctl -d 'spi::kbd_backlight' set 50%
```

## Persist a preferred level across reboot

This repo includes `systemd/macbook-kbd-backlight.service`. Install it with:

```bash
sudo install -m 644 systemd/macbook-kbd-backlight.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now macbook-kbd-backlight.service
```

The supplied service sets 50% at boot. Edit the service before installation if you prefer another level.

---

# 14. Hyprland bindings included in this repo

The `hypr/` directory contains two tested overrides:

```text
hypr/bindings.lua
hypr/input.lua
```

They provide:

| Keys | Action |
|---|---|
| `SUPER + CTRL + ↑ / ↓` | keyboard backlight up / down |
| `SUPER + CTRL + \` | keyboard backlight cycle |
| `SUPER + SHIFT + CTRL + ↑ / ↓` | display brightness up / down |
| `Caps Lock` | Escape |
| `Right Alt` | Compose |

Install them with the included helper:

```bash
./scripts/install-hypr-overrides.sh
```

Or manually:

```bash
mkdir -p ~/.config/hypr
cp hypr/bindings.lua ~/.config/hypr/bindings.lua
cp hypr/input.lua ~/.config/hypr/input.lua
```

Then reload Hyprland using the reload mechanism appropriate to your Omarchy release, or log out/in.

---

# 15. MacBookPro14,3 Radeon suspend: confirmed broken on this setup

This section applies specifically to the **15-inch MacBookPro14,3 with Radeon Pro 555**, not the 13-inch Intel-only MacBookPro14,2 used for the upstream suspend verification.

The machine successfully enters ACPI S3 (`deep`), and the T1/Touch Bar resumes, but the Radeon fails to return:

```text
amdgpu: SMU load firmware failed
amdgpu: fw load failed
amdgpu: smu firmware loading failed
amdgpu_device_ip_resume failed (-22)
PM: failed to resume async: error -22
```

The GPU then enters reset/recovery loops and the internal display remains black even though the machine is otherwise partly awake.

Two USB-C/xHCI controllers also reported resume errors (`-19`) during the same tests.

## Tested but NOT successful

### `amdgpu.dpm=0`

Adding only:

```text
amdgpu.dpm=0
```

changed fan/power behavior but **did not fix resume**. The same SMU firmware reload failure and `-22` resume error remained.

Do not keep this parameter solely for suspend on this configuration.

### Runtime `vga_switcheroo` switch to Intel (`DIGD`)

The machine exposes both GPUs:

```text
DIS = Radeon Pro 555
IGD = Intel HD Graphics 630
```

The Radeon owns the internal panel in the normal Linux boot. A delayed runtime switch using `DIGD` caused the graphical session to exit to a black internal display and required a reboot.

That experiment is **not recommended** as a suspend workaround.

A true Intel-only boot may require an EFI helper such as `apple_set_os.efi` plus a different boot configuration; that was not implemented or validated here.

## Recommended stable behavior: disable suspend

Until a reliable Radeon resume fix is established, prevent accidental S3 entry:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Ignore lid-triggered suspend:

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo install -m 644 systemd/macbook-no-suspend.conf /etc/systemd/logind.conf.d/macbook-no-suspend.conf
```

Reboot, then verify:

```bash
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target
systemd-analyze cat-config systemd/logind.conf | grep -E 'HandleLidSwitch'
```

Expected:

```text
masked
masked
masked
masked

HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

With this configuration, closing/reopening the lid does not enter the broken S3 resume path.

---

# 16. Things not to do

- **Do not use Omarchy full-disk install** on a T1 Mac if you want the T1 hardware to work.
- **Do not format Apple's ~314 MB ESP.**
- **Do not use `module_blacklist=`** for the T1 DKMS modules; use `modprobe.blacklist=`.
- **Do not install `macbook12-spi-driver-dkms`** on this current kernel; mainline `applespi` handles keyboard/trackpad.
- **Do not install `tiny-dfr`** for this T1 Touch Bar; it targets different hardware.
- **Do not install `broadcom-wl`** for the BCM43602 configuration documented here.
- **Do not add `amdgpu.dpm=0` expecting it to repair suspend** on the tested Radeon Pro 555.
- **Do not rely on runtime `DIGD` switching** as a safe way to move the internal panel to Intel under the tested Hyprland setup.
- `mbpfan` is not required; the SMC firmware manages fans.

---

# 17. Quick health check

```bash
echo '=== T1 ==='
for d in /sys/bus/usb/devices/*/; do
  [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] &&
    echo "05ac:$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
done

echo
echo '=== TOUCH BAR ==='
systemctl --no-pager --full status touchbar.service | head -15

echo
echo '=== WEBCAM ==='
lsmod | grep uvcvideo
ls /dev/video* 2>/dev/null

echo
echo '=== AUDIO ==='
wpctl status | grep -A10 Audio

echo
echo '=== GPU ==='
lspci -k | grep -A3 -E 'VGA|Display'

echo
echo '=== WIFI ==='
ip link | grep -A1 -E 'wl'
```

The single most important result remains:

```text
05ac:8600 iBridge
```

---

# Credits / upstream work

Most of the difficult T1-specific driver work belongs to the upstream authors and projects below. This repo exists to document a complete, reproducible **MacBookPro14,3 / Omarchy** install and the 15-inch Radeon caveats discovered during testing.

- T1 Omarchy toolkit: https://github.com/nohzafk/omarchy-macbookpro-t1
- Touch Bar driver lineage: https://github.com/F13-Kr1pt0n/macbook-pro-touchbar-driver
- MacBook Pro Cirrus audio: https://github.com/davidjo/snd_hda_macbookpro
- Omarchy: https://github.com/basecamp/omarchy

If you improve Radeon suspend/resume on the 15-inch 14,3, please document the exact kernel, firmware package, parameters, and logs so the result can be reproduced.