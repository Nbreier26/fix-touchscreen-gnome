# 🖥️ Fix Touchscreen Monitor Mapping — GNOME Wayland

![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=arch-linux&logoColor=white)
![GNOME](https://img.shields.io/badge/GNOME-4A86CF?style=flat&logo=gnome&logoColor=white)
![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=flat&logo=gnu-bash&logoColor=white)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

Fix for external touch monitors sending input events to the wrong display on GNOME with Wayland.

> **Tested on:** Arch Linux · GNOME 49.5 · USB-C touch monitor (`wch.cn USB2IIC_CTP_CONTROL`)

---

## Table of Contents

- [The Problem](#the-problem)
- [Quick Fix (Manual)](#quick-fix-manual)
- [Automatic Fix (Script)](#automatic-fix-script)
- [Why doesn't xinput work?](#why-doesnt-xinput-work)
- [Making It Permanent](#making-it-permanent-without-the-script)
- [References](#references)

---

## The Problem

When connecting an external USB-C touch monitor to a laptop running GNOME/Wayland, touch events are sent to the internal display instead of the external one. This happens because `libinput` assumes the touch device covers all available monitors, and Mutter's heuristics don't always produce the correct mapping.

The classic `xinput --map-to-output` command **does not work on Wayland** — the correct fix is through `gsettings`.

---

## Quick Fix (Manual)

### 1. Find your external monitor details

```bash
cat ~/.config/monitors.xml
```

Note the `<vendor>`, `<product>`, and `<serial>` of your external monitor — the one whose connector is **not** `eDP` (eDP is the internal laptop screen).

### 2. Find the touchscreen device ID

```bash
lsusb
```

Look for your touch device. The ID is in `XXXX:XXXX` format (vendor:product), e.g. `32d7:0001`.

### 3. Apply the mapping

```bash
gsettings set org.gnome.desktop.peripherals.touchscreen:/org/gnome/desktop/peripherals/touchscreens/VENDOR:PRODUCT/ \
  output "['MONITOR_VENDOR', 'MONITOR_PRODUCT', 'MONITOR_SERIAL']"
```

**Real-world example** (RTK monitor over USB-C):

```bash
gsettings set org.gnome.desktop.peripherals.touchscreen:/org/gnome/desktop/peripherals/touchscreens/32d7:0001/ \
  output "['RTK', '0x1920', 'demoset-1']"
```

**Log out and back in** to ensure GNOME applies the new configuration.

---

## Automatic Fix (Script)

The script auto-detects the touchscreen and the external monitor, then applies the correct mapping.

### Download and run

```bash
curl -O https://raw.githubusercontent.com/Nbreier26/fix-touchscreen-gnome/main/fix-touch.sh
chmod +x fix-touch.sh
bash fix-touch.sh
```

### What the script does

1. Reads `~/.config/monitors.xml` and lists available monitors
2. Detects the touchscreen via `libinput list-devices`
3. Identifies the Vendor:Product ID of the touch device
4. Applies the correct `gsettings` entry to map touch input to the external monitor
5. *(Optional)* Creates a `systemd --user` service to apply the mapping automatically on every login

### Dependencies

- `libinput` — usually pre-installed on Arch
- `gsettings` — part of the `glib2` package

```bash
sudo pacman -S libinput glib2
```

---

## Why doesn't `xinput` work?

On GNOME Wayland, Xwayland abstracts away input devices and merges them into generic ones (`xwayland-touch-pointer`, etc.). The `xinput --map-to-output` command only works on pure X11 sessions.

On Wayland, touch-to-monitor mapping is handled by **Mutter** (GNOME's compositor) via `gsettings`, using a per-device relocatable schema:

```
org.gnome.desktop.peripherals.touchscreen:/org/gnome/desktop/peripherals/touchscreens/<vendorid:productid>/
```

---

## Making It Permanent (Without the Script)

Create a systemd user service file:

```bash
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/fix-touch.service
```

Paste the following content, replacing the values with your own device info:

```ini
[Unit]
Description=Fix touchscreen monitor mapping
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c \
  "gsettings set \
  org.gnome.desktop.peripherals.touchscreen:/org/gnome/desktop/peripherals/touchscreens/32d7:0001/ \
  output \"['RTK', '0x1920', 'demoset-1']\""
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

[Install]
WantedBy=graphical-session.target
```

Then enable it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now fix-touch.service
```

> Replace `32d7:0001`, `RTK`, `0x1920`, and `demoset-1` with your own device values from Steps 1 and 2.

---

## References

- [ArchWiki — Touchscreen](https://wiki.archlinux.org/title/Touchscreen)
- [Enforcing a touchscreen mapping in GNOME — Peter Hutterer](https://who-t.blogspot.com/2024/03/enforcing-touchscreen-mapping-in-gnome.html)
- [GNOME Discourse — External touch-screen mapped to wrong display](https://discourse.gnome.org/t/external-touch-screen-is-mapped-to-wrong-display/26089)

---

## License

MIT
