#!/usr/bin/env bash
# Post-install automation for Omarchy on MacBookPro14,3 (README sections 7-15).
#
# Run as your normal user (it uses sudo where needed). Idempotent: completed
# steps are detected and skipped, so re-run it freely, including after reboots.
#
#   ./scripts/post-install.sh                          run everything
#   ./scripts/post-install.sh --wifi-mac AA:BB:CC:DD:EE:FF   also fix Wi-Fi NVRAM MAC
#   ./scripts/post-install.sh --verify                 health check only (section 17)
#
# Prerequisites (section 6): run `omarchy-update` and reboot before first run.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
t1_toolkit_dir="$HOME/omarchy-macbookpro-t1"
audio_dir="$HOME/snd_hda_macbookpro"
wifi_mac=""
verify_only=0
reboot_needed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wifi-mac) wifi_mac="${2:?--wifi-mac needs a value}"; shift 2 ;;
    --verify)   verify_only=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mOK\033[0m %s\n' "$*"; }
skip() { printf '    \033[33mskip\033[0m %s\n' "$*"; }
fail() { printf '    \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

t1_state() {
  local d
  for d in /sys/bus/usb/devices/*/; do
    [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ] || continue
    cat "$d/idProduct" 2>/dev/null
  done
}

verify() {
  local rc=0
  step "T1 / iBridge"
  if t1_state | grep -q 8600; then ok "05ac:8600 iBridge"; else
    printf '    \033[31mFAIL\033[0m T1 not at 05ac:8600 — see README section 1-2\n'; rc=1; fi

  step "Touch Bar service"
  if systemctl is-active -q touchbar.service 2>/dev/null &&
     journalctl -b -u touchbar.service --no-pager 2>/dev/null | grep -q 'SUCCESS: fnmode=0'; then
    ok "touchbar.service active, SUCCESS: fnmode=0"
  else printf '    \033[31mFAIL\033[0m touchbar.service not healthy (check journalctl -u touchbar.service)\n'; rc=1; fi

  step "Kernel cmdline"
  if grep -q 'modprobe.blacklist=apple_ibridge' /proc/cmdline; then ok "modprobe.blacklist present"
  else printf '    \033[31mFAIL\033[0m limine drop-in not applied to this boot (reboot?)\n'; rc=1; fi

  step "Webcam"
  if [ -e /dev/video0 ]; then ok "/dev/video0 present"
  else printf '    \033[31mFAIL\033[0m no /dev/video* device\n'; rc=1; fi

  step "Audio"
  if wpctl status 2>/dev/null | grep -qi sink; then ok "audio sinks present"
  else printf '    \033[31mFAIL\033[0m no audio sinks (cirrus driver built? rebooted since?)\n'; rc=1; fi

  step "Wi-Fi"
  local mac
  mac="$(ip -o link | awk -F'link/ether ' '/wl/ {print $2}' | awk '{print $1}' | head -1)"
  if [ -z "$mac" ]; then printf '    \033[31mFAIL\033[0m no wl* interface\n'; rc=1
  elif [[ "$mac" == 00:90:4c:* ]]; then
    printf '    \033[31mFAIL\033[0m placeholder MAC %s — run with --wifi-mac (see README section 11)\n' "$mac"; rc=1
  else
    ok "MAC $mac"
    if iw phy 2>/dev/null | grep -q 'Band 2'; then ok "5 GHz (Band 2) available"
    else printf '    \033[31mFAIL\033[0m Band 2 missing (reboot after firmware copy?)\n'; rc=1; fi
  fi

  step "Keyboard backlight"
  if systemctl is-enabled -q macbook-kbd-backlight.service 2>/dev/null; then ok "persistence service enabled"
  else printf '    \033[31mFAIL\033[0m macbook-kbd-backlight.service not enabled\n'; rc=1; fi

  step "Suspend disabled"
  if [ "$(systemctl is-enabled sleep.target 2>&1)" = "masked" ]; then ok "sleep targets masked"
  else printf '    \033[31mFAIL\033[0m sleep.target not masked (README section 15)\n'; rc=1; fi

  [ "$rc" -eq 0 ] && step "All checks passed" || step "Some checks FAILED (see above)"
  return "$rc"
}

if [ "$verify_only" -eq 1 ]; then verify; exit $?; fi

# --- Preflight -------------------------------------------------------------
step "Preflight: T1 health"
case "$(t1_state)" in
  *8600*) ok "05ac:8600 iBridge" ;;
  *1281*) fail "T1 is in recovery mode (05ac:1281). Linux-side work cannot fix this; reinstall macOS per README section 2." ;;
  *)      fail "No healthy T1 found. See README section 1." ;;
esac

# --- Section 7: Option boot picker -----------------------------------------
step "Section 7: Omarchy in Apple's Option boot picker"
if sudo test -f /boot/EFI/BOOT/BOOTX64.EFI; then skip "BOOTX64.EFI already present"
else
  sudo mkdir -p /boot/EFI/BOOT
  sudo cp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI
  ok "installed BOOTX64.EFI"
fi

# --- Section 8: remove obsolete SPI DKMS package ---------------------------
step "Section 8: remove macbook12-spi-driver-dkms (mainline applespi is used)"
if pacman -Qi macbook12-spi-driver-dkms &>/dev/null; then
  sudo dkms remove -m macbook12-spi-driver --all 2>/dev/null || true
  sudo pacman -R --noconfirm macbook12-spi-driver-dkms
  ok "removed"
else skip "not installed"; fi
modinfo -n applespi >/dev/null || fail "mainline applespi module not found for this kernel"

# --- Section 9: T1 Touch Bar driver ----------------------------------------
step "Section 9: Touch Bar driver (appleibridge DKMS)"
sudo pacman -S --needed --noconfirm linux-headers dkms base-devel git wget

if [ ! -d "$t1_toolkit_dir" ]; then
  git clone https://github.com/nohzafk/omarchy-macbookpro-t1.git "$t1_toolkit_dir"
  ok "cloned upstream T1 toolkit"
else skip "toolkit already cloned at $t1_toolkit_dir"; fi

if dkms status -m appleibridge -v 0.1 2>/dev/null | grep -q installed; then
  skip "appleibridge 0.1 already installed via DKMS"
else
  sudo mkdir -p /usr/src/appleibridge-0.1
  sudo cp "$t1_toolkit_dir"/drivers/appleibridge/{*.c,*.h,Makefile,dkms.conf} /usr/src/appleibridge-0.1/
  dkms status -m appleibridge -v 0.1 2>/dev/null | grep -q appleibridge || sudo dkms add -m appleibridge -v 0.1
  sudo dkms build -m appleibridge -v 0.1
  sudo dkms install -m appleibridge -v 0.1
  ok "appleibridge built and installed"
fi

sudo install -m 755 "$t1_toolkit_dir/systemd/touchbar-enable.sh" /usr/local/sbin/
sudo install -m 644 "$t1_toolkit_dir/systemd/touchbar.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now touchbar.service
ok "touchbar.service enabled"

step "Section 9: Limine persistence drop-in (modprobe.blacklist, NOT module_blacklist)"
dropin=/etc/limine-entry-tool.d/macbook-t1.conf
if sudo test -f "$dropin" && sudo grep -q modprobe.blacklist "$dropin"; then
  skip "drop-in already present"
else
  sudo tee "$dropin" >/dev/null <<'EOF'
KERNEL_CMDLINE[default]+=" pcie_ports=compat modprobe.blacklist=apple_ibridge,apple_ib_tb,apple_ib_als"
EOF
  sudo limine-update
  ok "drop-in installed and limine updated"
  reboot_needed=1
fi

# --- Section 10: audio ------------------------------------------------------
step "Section 10: Cirrus speaker driver (snd_hda_macbookpro)"
if wpctl status 2>/dev/null | grep -qi sink && dkms status 2>/dev/null | grep -qi cirrus; then
  skip "cirrus DKMS present and audio sinks exist"
else
  if [ ! -d "$audio_dir" ]; then
    git clone https://github.com/davidjo/snd_hda_macbookpro.git "$audio_dir"
  fi
  (cd "$audio_dir" && sudo ./install.cirrus.driver.sh -i)
  ok "cirrus driver installed"
  reboot_needed=1
fi

# --- Section 11: Wi-Fi NVRAM MAC fix ---------------------------------------
step "Section 11: Wi-Fi BCM43602 NVRAM"
cur_mac="$(ip -o link | awk -F'link/ether ' '/wl/ {print $2}' | awk '{print $1}' | head -1)"
if [ -n "$cur_mac" ] && [[ "$cur_mac" != 00:90:4c:* ]]; then
  skip "real MAC already active ($cur_mac)"
elif [ -n "$wifi_mac" ]; then
  [[ "$wifi_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || fail "--wifi-mac '$wifi_mac' is not a valid MAC"
  nvram="$t1_toolkit_dir/firmware/brcmfmac43602-pcie.txt"
  [ -f "$nvram" ] || fail "NVRAM template not found at $nvram"
  sed "s/^macaddr=.*/macaddr=$wifi_mac/" "$nvram" | sudo tee /lib/firmware/brcm/brcmfmac43602-pcie.txt >/dev/null
  ok "NVRAM installed with macaddr=$wifi_mac"
  reboot_needed=1
else
  printf '    \033[33mACTION NEEDED\033[0m Wi-Fi has placeholder MAC (%s).\n' "${cur_mac:-none}"
  echo   "    Get the real Wi-Fi MAC from macOS (System Information -> Network -> Wi-Fi),"
  echo   "    then re-run: $0 --wifi-mac AA:BB:CC:DD:EE:FF"
fi

# --- Section 13: keyboard backlight persistence ----------------------------
step "Section 13: keyboard backlight persistence"
if systemctl is-enabled -q macbook-kbd-backlight.service 2>/dev/null; then skip "already enabled"
else
  sudo install -m 644 "$repo_dir/systemd/macbook-kbd-backlight.service" /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now macbook-kbd-backlight.service
  ok "service enabled (50%)"
fi

# --- Section 14: Hyprland brightness bindings ------------------------------
step "Section 14: Hyprland brightness bindings"
if cmp -s "$repo_dir/hypr/bindings.lua" "$HOME/.config/hypr/bindings.lua" 2>/dev/null; then
  skip "bindings already installed"
else
  "$repo_dir/scripts/install-hypr-overrides.sh"
fi

# --- Section 15: disable suspend -------------------------------------------
step "Section 15: disable suspend (Radeon does not survive resume)"
if [ "$(systemctl is-enabled sleep.target 2>&1)" = "masked" ]; then skip "sleep targets already masked"
else
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  ok "sleep targets masked"
fi
if sudo test -f /etc/systemd/logind.conf.d/macbook-no-suspend.conf; then skip "lid policy already installed"
else
  sudo mkdir -p /etc/systemd/logind.conf.d
  sudo install -m 644 "$repo_dir/systemd/macbook-no-suspend.conf" /etc/systemd/logind.conf.d/macbook-no-suspend.conf
  ok "lid policy installed (reboot to apply)"
  reboot_needed=1
fi

# --- Done -------------------------------------------------------------------
if [ "$reboot_needed" -eq 1 ]; then
  step "Done — REBOOT REQUIRED, then run: $0 --verify"
else
  step "Done — running health check"
  verify
fi
