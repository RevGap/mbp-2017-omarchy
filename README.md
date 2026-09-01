# Omarchy on MacBookPro14,3 (2017 15-inch Touch Bar, T1)

A tested guide for running **Omarchy on the 2017 15-inch MacBook Pro (MacBookPro14,3)** while preserving the Apple T1 firmware and restoring the Touch Bar, webcam, Wi-Fi, audio, keyboard backlight, and useful brightness controls.

Tested on:

- MacBookPro14,3
- Radeon Pro 555
- Apple T1 / iBridge
- Omarchy on kernel `7.1.8-arch1-3`

Primary upstream T1 toolkit:

- https://github.com/nohzafk/omarchy-macbookpro-t1
- Related Omarchy discussion: `basecamp/omarchy#2457`

The upstream project was verified on the 13-inch Intel-only MacBookPro14,2. This repo documents a full install on the **15-inch MacBookPro14,3** and the Radeon-specific behavior discovered during testing.

---

## Tested status

| Feature | Status | Notes |
|---|---|---|
| T1 / iBridge | ✅ | `05ac:8600` when Apple's ESP is preserved |
| Touch Bar | ✅ | Real Esc + F1-F12, persistent across reboot |
| Webcam | ✅ | `uvcvideo` |
| Keyboard / trackpad | ✅ | Mainline `applespi` |
| Keyboard backlight | ✅ | `spi::kbd_backlight`; persistence service included |
| Display brightness | ✅ | `gmux_backlight`; custom Hyprland bindings included |
| Wi-Fi 2.4 + 5 GHz | ✅ | BCM43602 NVRAM fix restores Apple MAC and Band 2 |
| Bluetooth | ✅ | No additional work required |
| Speakers | ✅ | `snd_hda_macbookpro` DKMS driver |
| Radeon Pro 555 | ✅ awake | `amdgpu`; internal panel normally driven by dGPU |
| Deep suspend / S3 | ❌ | Radeon SMU firmware reload fails on resume |
| Touch ID | ❌ | No Linux driver |

---

## What's in this repo

```
├── README.md                              # This guide
├── hypr/
│   └── bindings.lua                       # Brightness keybindings (no F-row on this chassis)
├── scripts/
│   └── install-hypr-overrides.sh          # Installs the bindings into ~/.config/hypr
└── systemd/
    ├── macbook-kbd-backlight.service      # Persists keyboard backlight level across reboots
    └── macbook-no-suspend.conf            # logind lid policy (suspend disabled — see §15)
```

---

# 1. Never wipe Apple's EFI partition

This is the most important rule.

The T1 firmware is stored on Apple's EFI System Partition, including:

```text
EFI/APPLE/EMBEDDEDOS/combined.memboot
```

If a Linux installer reformats Apple's ESP, the T1 falls into recovery mode:

```text
05ac:1281  Apple Mobile Device (Recovery Mode)   # broken
05ac:8600  iBridge                               # healthy
```

When the T1 is at `1281`, the Touch Bar, webcam, Touch ID, and ambient-light hardware disappear together.

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

# 2. Recover a T1 already stuck at `05ac:1281`

## Reinstall macOS through Internet Recovery

1. Power off.
2. Power on holding **Command + Option + R**.
3. Open Disk Utility.
4. Choose **View → Show All Devices**.
5. Select the top-level internal Apple SSD.
6. Erase as:

```text
Name: Macintosh HD
Format: APFS
Scheme: GUID Partition Map
```

7. Reinstall macOS.
8. Complete enough setup to reach the desktop.
9. Install all available macOS updates.

## Verify T1 firmware restoration

In macOS Terminal:

```bash
diskutil list
sudo diskutil mount disk0s1
find /Volumes/EFI -maxdepth 5 -type f | grep -E 'combined\.memboot|MBP143\.fd'
system_profiler SPiBridgeDataType
```

On the tested machine:

```text
/Volumes/EFI/EFI/APPLE/EMBEDDEDOS/combined.memboot
```

was present and `system_profiler` reported an **Apple T1 Security Chip**.

Do not reinstall Linux until `combined.memboot` exists.

---

# 3. Back up Apple's ESP

From macOS:

```bash
sudo diskutil mount disk0s1
mkdir -p ~/esp-backup && cd ~/esp-backup

tar -C /Volumes/EFI -cf - EFI | gzip -6 > esp-files.tar.gz
sudo dd if=/dev/rdisk0s1 bs=1m 2>/dev/null | gzip -6 > esp-raw.img.gz
shasum -a 256 ./*.gz > SHA256SUMS.txt

tar tzf esp-files.tar.gz | grep combined.memboot
```

Copy `~/esp-backup` off the machine.

**Do not commit your machine-specific ESP backup to a public repository.**

---

# 4. Shrink macOS and leave free space for Omarchy

Delete local Time Machine snapshots if any:

```bash
tmutil listlocalsnapshots /
sudo tmutil deletelocalsnapshots <each-date>
```

Confirm the APFS physical store:

```bash
diskutil list
```

On the tested 500 GB SSD, macOS was reduced to 110 GB:

```bash
sudo diskutil apfs resizeContainer disk0s2 110g
```

Expected result:

```text
disk0s1   ~314.6 MB   Apple EFI / ESP
disk0s2   ~110 GB     macOS APFS
           ~390 GB     free space
```

The Apple EFI partition must remain untouched.

---

# 5. Install Omarchy into free space

1. Boot the Omarchy USB while holding **Option**.
2. Select **EFI Boot**.
3. Select the internal Apple NVMe drive.
4. Choose:

```text
Free space install (alongside existing data)
```

5. Do **not** choose full-disk install.
6. Verify the confirmation screen targets only the free space.
7. Abort if Apple's ~314 MB EFI partition is listed for formatting.
8. Keep LUKS encryption enabled.

A healthy final layout is approximately:

```text
nvme0n1p1   ~300M  vfat          Apple ESP — DO NOT FORMAT
nvme0n1p2   ~110G  apfs          macOS
nvme0n1p3     2G   vfat  /boot   Omarchy ESP
nvme0n1p4    rest  crypto_LUKS   Omarchy root
```

Immediately verify:

```text
05ac:8600 iBridge
```

---

# 6. Update Omarchy first

Before building hardware DKMS modules:

```bash
omarchy-update
```

Then reboot if requested and check:

```bash
uname -r
```

The configuration documented here was tested on:

```text
7.1.8-arch1-3
```

---

# 7. Make Omarchy visible in Apple's Option boot picker

```bash
sudo mkdir -p /boot/EFI/BOOT
sudo cp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI
```

Do not place a second `limine.conf` beside `BOOTX64.EFI`.

---

# 8. Remove the obsolete MacBook SPI DKMS package

Omarchy may install `macbook12-spi-driver-dkms`. On the tested current kernel it fails to build, while keyboard and trackpad support are already provided by mainline `applespi`.

```bash
sudo dkms remove -m macbook12-spi-driver -v 0+git.315 --all
sudo pacman -R macbook12-spi-driver-dkms
modinfo -n applespi
```

Do not reinstall the old AUR driver.

---

# 9. Install the T1 Touch Bar driver

Clone the upstream toolkit:

```bash
cd ~
git clone https://github.com/nohzafk/omarchy-macbookpro-t1.git
cd omarchy-macbookpro-t1
```

Install:

```bash
sudo pacman -S --needed linux-headers dkms
sudo mkdir -p /usr/src/appleibridge-0.1
sudo cp drivers/appleibridge/{*.c,*.h,Makefile,dkms.conf} /usr/src/appleibridge-0.1/

sudo dkms add     -m appleibridge -v 0.1
sudo dkms build   -m appleibridge -v 0.1
sudo dkms install -m appleibridge -v 0.1

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

## Critical persistence fix

Use a Limine drop-in:

```bash
sudo tee /etc/limine-entry-tool.d/macbook-t1.conf <<'EOF'
KERNEL_CMDLINE[default]+=" pcie_ports=compat modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als"
EOF

sudo limine-update
```

Reboot and verify:

```bash
cat /proc/cmdline
journalctl -b -u touchbar.service --no-pager
```

### Use `modprobe.blacklist`, not `module_blacklist`

Do **not** use:

```text
module_blacklist=apple_ibridge,apple_ib_tb,apple_ib_als
```

The kernel-level blacklist also blocks the service's deliberate `insmod` and produces `Operation not permitted`.

`modprobe.blacklist=` suppresses automatic module loading while still allowing the late service to load the driver directly.

---

# 10. Audio

```bash
sudo pacman -S --needed base-devel git wget dkms linux-headers
cd ~
git clone https://github.com/davidjo/snd_hda_macbookpro.git
cd snd_hda_macbookpro
sudo ./install.cirrus.driver.sh -i
sudo reboot
```

If the microphone is muted:

```bash
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 100%
```

---

# 11. Wi-Fi — BCM43602 NVRAM fix

Without board NVRAM, Linux may show Broadcom's placeholder MAC:

```text
00:90:4c:xx:xx:xx
```

Check:

```bash
ip link | grep -A1 -E 'wl'
```

If the address starts with `00:90:4c`, get the **real Wi-Fi MAC from macOS**:

**System Information → Network → Wi-Fi**

Then from the upstream toolkit:

```bash
cd ~/omarchy-macbookpro-t1/firmware
sed -i 's/^macaddr=.*/macaddr=AA:BB:CC:DD:EE:FF/' brcmfmac43602-pcie.txt
sudo cp brcmfmac43602-pcie.txt /lib/firmware/brcm/
sudo reboot
```

Replace the example MAC with your own.

Verify:

```bash
ip link | grep -A1 -E 'wl'
iw phy | grep Band
iw dev <wifi-interface> link
```

Healthy behavior should show:

- the real Apple MAC
- both `Band 1` and `Band 2`
- a 5xxx MHz frequency when connected to 5 GHz

Do not install `broadcom-wl` for this setup.

---

# 12. Webcam

Once the T1 is healthy, the webcam uses mainline `uvcvideo`:

```bash
lsmod | grep uvcvideo
ls /dev/video* 2>/dev/null
```

---

# 13. Keyboard backlight

The backlight device is:

```text
spi::kbd_backlight
```

Test:

```bash
brightnessctl -d 'spi::kbd_backlight' set 50%
```

To persist a preferred level across reboot, install the included service:

```bash
sudo install -m 644 systemd/macbook-kbd-backlight.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now macbook-kbd-backlight.service
```

The supplied service uses 50%.

---

# 14. Hyprland brightness bindings

Because the 2017 Touch Bar chassis has no physical F-row, Omarchy's normal keyboard/display-brightness keys are inconvenient even though the Touch Bar itself now works.

This repo includes:

```text
hypr/bindings.lua
```

Bindings:

| Keys | Action |
|---|---|
| `SUPER + CTRL + ↑ / ↓` | keyboard backlight up / down |
| `SUPER + CTRL + \` | keyboard backlight cycle |
| `SUPER + SHIFT + CTRL + ↑ / ↓` | display brightness up / down |

There is **no Caps-to-Escape remap** in the final setup because the working Touch Bar provides a real Escape key.

Install the bindings with:

```bash
./scripts/install-hypr-overrides.sh
```

Or manually:

```bash
mkdir -p ~/.config/hypr
cp hypr/bindings.lua ~/.config/hypr/bindings.lua
```

Log out/in if your Omarchy release does not reload the file automatically.

---

# 15. Radeon suspend on MacBookPro14,3

This applies specifically to the **15-inch MacBookPro14,3 with Radeon Pro 555**.

The machine successfully enters ACPI S3/deep sleep and the T1/Touch Bar resumes, but the Radeon fails to return:

```text
amdgpu: SMU load firmware failed
amdgpu: fw load failed
amdgpu: smu firmware loading failed
amdgpu_device_ip_resume failed (-22)
PM: failed to resume async: error -22
```

The GPU then enters reset/recovery loops and the internal display remains black.

Two USB-C/xHCI controllers also reported resume errors (`-19`) in the same tests.

## Tested but not successful

### `amdgpu.dpm=0`

This changed fan/power behavior but did **not** fix the SMU firmware reload failure.

### Runtime `vga_switcheroo` `DIGD`

A delayed runtime switch from Radeon to Intel caused the graphical session to exit to a black internal display and required rebooting.

Do not use runtime `DIGD` as a suspend workaround on this tested setup.

A true Intel-only boot may require an EFI helper such as `apple_set_os.efi`; that path was not validated here.

## Recommended stable behavior: disable suspend

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Install the included lid policy:

```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo install -m 644 systemd/macbook-no-suspend.conf /etc/systemd/logind.conf.d/macbook-no-suspend.conf
```

Reboot and verify:

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

---

# 16. Things not to do

- Do not use Omarchy full-disk install if you want T1 hardware to work.
- Do not format Apple's ~314 MB ESP.
- Do not use `module_blacklist=` for the T1 modules; use `modprobe.blacklist=`.
- Do not install `macbook12-spi-driver-dkms` on the tested current kernel.
- Do not install `tiny-dfr` for this T1 Touch Bar.
- Do not install `broadcom-wl` for the documented BCM43602 setup.
- Do not keep `amdgpu.dpm=0` expecting it to repair suspend.
- Do not rely on runtime `DIGD` switching as a safe suspend workaround.
- `mbpfan` is not required; the SMC manages the fans.

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

# Credits

Most of the difficult T1-specific work belongs to the upstream projects below. This repo documents a complete, reproducible **MacBookPro14,3 / Omarchy** installation and the Radeon-specific caveats discovered during live testing.

- T1 Omarchy toolkit: https://github.com/nohzafk/omarchy-macbookpro-t1
- Touch Bar driver lineage: https://github.com/F13-Kr1pt0n/macbook-pro-touchbar-driver
- MacBook Pro Cirrus audio: https://github.com/davidjo/snd_hda_macbookpro
- Omarchy: https://github.com/basecamp/omarchy
