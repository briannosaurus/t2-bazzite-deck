# t2-bazzite-deck

Combines Kansei's T2-Atomic hardware-enablement layer with Bazzite's
Deck/Gaming Mode image, for a 2019 16" MacBook Pro (`MacBookPro16,1`).

## What this is

Kansei's published `ghcr.io/kansei-os/t2-atomic-bazzite` is built FROM
`ghcr.io/ublue-os/bazzite:stable` (Bazzite's plain desktop image), so it has
no Gaming Mode. This project is the same build, retargeted at
`ghcr.io/ublue-os/bazzite-deck:stable` instead, which already contains
Gaming Mode (`gamescope-session-ogui-steam`, `steamos-manager-powerstation`,
`inputplumber`, Return-to-Gaming-Mode).

The `Containerfile` here is Kansei's own
`variants/t2-bazzite/Containerfile` with one line changed (the base image).
Everything else is Kansei's own build logic, vendored verbatim into
`build_files/` and `etc-overlay/` under Apache-2.0 (`LICENSE.kansei-os`),
from [kansei-os/t2-atomic](https://github.com/kansei-os/t2-atomic) commit
`ef80157` (2026-08-20), with the fixes below layered on top.

## Status

Builds cleanly, passes `bootc container lint`, and **boots successfully**
on a real `MacBookPro16,1` (confirmed 2026-08-24, running kernel
`7.1.8-200.t2.fc44.x86_64`). Gaming Mode, T2 hardware enablement, and Wi-Fi
have all been verified working on hardware.

## Fixes on top of Kansei's upstream script

Kansei's own CI has been failing daily on Fedora-44-based variants since
~2026-08-09 ([kansei-os/t2-atomic#71](https://github.com/kansei-os/t2-atomic/issues/71)).
`build_files/t2-enablement-ublue.sh` carries three fixes beyond that
upstream issue, each marked `t2-bazzite-deck addition` in the script:

1. **Kernel override depsolve failure.** Bazzite's Fedora 44 kernel build
   ships akmod modules (`kmod-evdi`, `kmod-gcadapter_oc`,
   `kmod-hid-fanatecff`, `kmod-kvmfr`, `kmod-nct6687d`) that pin to the
   exact stock kernel via the `kernel-uname-r` RPM capability. None apply
   to Apple hardware, but Kansei's static removal list predates them, so
   the T2 kernel override failed to depsolve. Fixed by removing anything
   requiring `kernel-uname-r` dynamically (via `rpm -q --whatrequires`)
   instead of a hand-maintained name list, so future Bazzite kernel
   rebuilds don't reintroduce the break.

2. **Stale initramfs → dracut emergency shell on boot.** The post-kernel
   `dracut` regen step (needed so the T2 keyboard works for early
   boot/LUKS) was commented out, so the shipped initramfs was missing the
   `systemd-sysroot-fstab-check` symlink and the `t2bce_dma`/`t2bce_core`/
   `t2bce_vhci` keyboard modules. Fixed by uncommenting that step and
   calling `/usr/libexec/rpm-ostree/wrapped/dracut` directly instead of the
   `rpm-ostree cliwrap`-installed `/usr/bin/dracut`, which drops privileges
   for unrecognized invocations and can't write to `/var/tmp` during the
   build.

3. **Wi-Fi permanently "unavailable."** Bazzite's base image runs
   `bazzite-iwd-migration.service` before `NetworkManager.service` on
   *every* boot, which unconditionally deletes
   `/etc/NetworkManager/conf.d/iwd.conf` as presumed legacy cruft. Kansei's
   script writes its "use iwd" config to that exact filename and also swaps
   out `wpa_supplicant` entirely, so once the file got deleted,
   NetworkManager fell back to its compiled-in `wpa_supplicant` backend
   default and could never bring up Wi-Fi (no such service left to
   activate). Fixed by writing the config to
   `/etc/NetworkManager/conf.d/99-t2-wifi-backend.conf` instead, a filename
   the migration script doesn't target.

## Known limitation (carried over from Kansei, not a regression)

**Sleep/wake does not work.** Kansei's enablement script masks
`suspend.target` and disables lid-switch/suspend-key handling, with an
explicit comment that suspend doesn't work on T2 Macs.

## Secure Boot

`mokutil --sb-state` reports Secure Boot disabled on this machine, so the
unsigned custom kernel/image isn't blocked by it. If you ever enable Secure
Boot, this image (like the upstream `t2-atomic-bazzite` image, also
unsigned -- `ostree-unverified-registry`) will need to be re-evaluated.

## Build

```bash
./build.sh
```

Builds `localhost/t2-bazzite-deck:local` with `podman`. Nothing is pushed
or deployed. Override `IMAGE_NAME`, `IMAGE_TAG`, or `BASE_TAG` as env vars
if needed.

## Test (no registry push required)

`rpm-ostree` can rebase directly to an image sitting in local `podman`
storage:

```bash
sudo rpm-ostree rebase ostree-unverified-image:containers-storage:localhost/t2-bazzite-deck:local
```

This stages a **new, additional deployment**. Any previously-booted
deployment (e.g. `t2-atomic-bazzite`, or a `bazzite-deck:stable` fallback)
is untouched and remains selectable at boot.

```bash
rpm-ostree status   # confirm the new deployment is staged, not yet booted
```

## Reboot

```bash
systemctl reboot
```

At the boot menu (or via `rpm-ostree status` after reboot), confirm you've
booted the new `t2-bazzite-deck` deployment.

## Verify Gaming Mode

```bash
ls /usr/share/wayland-sessions/
# expect: gamescope-session-ogui-steam.desktop, plasma.desktop, and related
#         gamescope-session-*.desktop entries

systemctl is-enabled steamos-manager.service inputplumber.service
```

- From KDE Desktop: log out, and confirm the SDDM login screen offers a
  Steam/Gaming Mode session alongside Plasma.
- From Gaming Mode: confirm Steam's "Return to Desktop" (or equivalent)
  switches back to KDE, and that Desktop's "Return to Gaming Mode" (the
  `return-to-gamemode` script wired into `/etc/skel/Desktop/Return.desktop`)
  switches back to Gaming Mode.
- Confirm a controller is recognized in Big Picture/Gaming Mode
  (`inputplumber.service` handles this).

## Verify T2 hardware

- Keyboard, trackpad: should work immediately (T2 `apple-bce`-derived
  stack via `t2linux-release`).
- Wi-Fi, Bluetooth: `iwd`-backed NetworkManager + Broadcom firmware from
  Kansei's `radio.tar`. If Wi-Fi shows as "unavailable" in `nmcli device
  status`, check `/etc/NetworkManager/conf.d/99-t2-wifi-backend.conf`
  exists and `systemctl status bazzite-iwd-migration.service` (see fix #3
  above).
- Speakers: T2 audio stack via `t2linux-release`.
- Display brightness: standard backlight control, unaffected by this
  layering.
- Sleep/wake: **expected to remain non-functional** (see "Known
  limitation" above) -- this is not a regression to chase.
- Radeon Pro dGPU / external displays: `amdgpu` driver + `apple-gmux.conf`
  muxing (`force_igd` commented out = dynamic switching).
- USB: standard kernel USB stack; `sg3_utils` is installed for the
  SuperDrive USB optical slot.
- `dmesg | grep -i t2` / `dmesg | grep -i apple` for any T2-specific
  driver errors.

## Roll back

If anything is wrong, don't debug on the broken deployment -- roll back
first:

```bash
# From within the new deployment, if it boots:
sudo rpm-ostree rollback
systemctl reboot

# Or from the bootloader menu at boot time:
# select the previous deployment entry directly -- this does not require
# the new deployment to boot successfully first.
```

No prior deployment is modified by anything in this project.

## Publishing to GHCR (not done automatically)

Only do this after the local test above has fully passed:

```bash
podman tag localhost/t2-bazzite-deck:local ghcr.io/briannosaurus/t2-bazzite-deck:latest
podman login ghcr.io
podman push ghcr.io/briannosaurus/t2-bazzite-deck:latest
```

Then, to rebase a machine to the published image:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/briannosaurus/t2-bazzite-deck:latest
```

## Files

```
Containerfile              # base image swap + Kansei's enablement, mirrored 1:1
build.sh                   # local podman build, no push
build_files/
  t2-enablement-ublue.sh   # vendored from kansei-os/t2-atomic + fixes (see above)
  ublue-packages.sh        # vendored verbatim (installs ublue-brew)
  common/radio.tar         # vendored verbatim (Broadcom Wi-Fi/BT firmware)
etc-overlay/                # vendored verbatim from variants/common/etc/
  modprobe.d/apple-gmux.conf         # Radeon Pro dGPU muxing
  systemd/logind.conf.d/t2-lidswitch.conf  # T2 suspend/lid handling
  bluetooth/, dracut.conf.d/, fwupd/
LICENSE.kansei-os          # Apache-2.0, for the vendored files above
```
