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
`variants/t2-bazzite/Containerfile` with one line changed (the base image),
plus one small addition to the vendored enablement script -- see
"Known issue fixed" below. Everything else is Kansei's own build logic,
vendored verbatim into `build_files/` and `etc-overlay/` under Apache-2.0
(`LICENSE.kansei-os`), from
[kansei-os/t2-atomic](https://github.com/kansei-os/t2-atomic) commit
`ef80157` (2026-08-20).

## What was tested (2026-08-21)

Before writing any of this, I reproduced the build locally with `podman
build` against Kansei's *unmodified* `variants/t2-bazzite/Containerfile`
(current `bazzite:stable`). It failed with a dependency-resolution error
when overriding the kernel -- **this is a real, currently-open upstream
break**, not something introduced by combining with Deck. It's also the
same root cause behind
[kansei-os/t2-atomic#71](https://github.com/kansei-os/t2-atomic/issues/71)
("Multiple Workflows Keep Failing"), whose CI has failed daily since at
least 2026-08-09 for every Fedora-44-based variant.

### Known issue fixed

Bazzite's current Fedora 44 kernel build (`7.2.0-ogc4.1.fc44`) ships several
akmod-built kernel modules that pin to that exact kernel via the
`kernel-uname-r` RPM capability: `kmod-evdi` (DisplayLink USB-GPU),
`kmod-gcadapter_oc` (GameCube adapter overclock), `kmod-hid-fanatecff`
(Fanatec racing wheel force-feedback), `kmod-kvmfr` (KVM/Looking-Glass frame
relay), `kmod-nct6687d` (a specific desktop motherboard sensor chip). None
of these apply to Apple hardware, but Kansei's static removal list predates
them, so the T2 kernel override fails to depsolve.

`build_files/t2-enablement-ublue.sh` adds one block (marked
`t2-bazzite-deck addition`) that removes anything requiring
`kernel-uname-r` dynamically, rather than hand-listing package names, so a
future Bazzite kernel rebuild adding yet another such module doesn't
silently reintroduce this break. This is the only functional change from
Kansei's upstream script.

### Verified after the fix, against `ghcr.io/ublue-os/bazzite-deck:stable` (tag `44.20260820`)

- Builds cleanly (`bootc container lint` passes with only benign warnings
  about non-empty `/boot`/`/run`/`/var` scratch files, which is normal for
  an in-progress `rpm-ostree` layer).
- T2 kernel (`kernel-core-7.1.8-200.t2.fc44`), `t2fanrd`, `t2linux-release`
  all present and correctly enabled.
- Gaming Mode packages all present and correct:
  `gamescope-session-ogui-steam`, `gamescope-session`,
  `gamescope-session-steam`, `terra-gamescope` (the actual package
  providing `/usr/sbin/gamescope`), `steamos-manager-powerstation`
  (provides `steamos-manager.service` + `steamosctl`), `inputplumber`.
  `/usr/bin/return-to-gamemode` and `bazzite-autologin.service` are present
  but not RPM-owned -- Bazzite bakes these in directly rather than
  packaging them.
- `/usr/share/wayland-sessions/` has both `plasma.desktop` and
  `gamescope-session-ogui-steam.desktop` (plus `gamescope-session-steam.desktop`,
  `gamescope-session-steam-plus.desktop`, `gamepadui-with-qam-session.desktop`).
- `steamos-manager.service` and `inputplumber.service` are enabled.
- `jupiter-fan-control.service` (Deck-hardware-only fan daemon) is present
  but **disabled by default** -- no conflict with `t2fanrd`, which is
  enabled.
- `apple-gmux.conf` (Radeon Pro dGPU muxing) and the T2 lid/suspend logind
  overrides from Kansei's `/etc` overlay are present in the final image.

I could not test actually booting the image (that requires an
`rpm-ostree rebase` + reboot on this specific hardware, which is
intentionally left for you to trigger -- see "Test" below). Everything
above was verified by building the image with `podman build` and
inspecting its contents with `podman run`, not by booting it.

### Known limitation carried over from Kansei (not new)

**Sleep/wake will not work.** Kansei's enablement script masks
`suspend.target` and disables lid-switch/suspend-key handling, with an
explicit comment that suspend doesn't work on T2 Macs. This is already
true of your currently-deployed `t2-atomic-bazzite`, not a regression
introduced here.

### Secure Boot

`mokutil --sb-state` reports Secure Boot disabled on this machine, so the
unsigned custom kernel/image is not blocked by it. If you ever enable
Secure Boot, this image (like your current T2 image, also unsigned --
`ostree-unverified-registry`) will need to be re-evaluated.

## Build

```bash
./build.sh
```

Builds `localhost/t2-bazzite-deck:local` with `podman`. Nothing is pushed
or deployed. Override `IMAGE_NAME`, `IMAGE_TAG`, or `BASE_TAG` as env vars
if needed.

## Test (no registry push required)

`rpm-ostree` can rebase directly to an image sitting in local `podman`
storage, so you can test this without publishing to GHCR at all:

```bash
sudo rpm-ostree rebase ostree-unverified-image:containers-storage:localhost/t2-bazzite-deck:local
```

This stages a **new, third deployment**. Your currently-booted
`t2-atomic-bazzite` deployment and your `bazzite-deck:stable` fallback
deployment are both untouched and remain selectable at boot.

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
  Kansei's `radio.tar`.
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
# select the previous deployment entry (your prior t2-atomic-bazzite
# deployment, or the bazzite-deck:stable fallback) directly -- this does
# not require the new deployment to boot successfully first.
```

Neither your original `t2-atomic-bazzite` deployment nor your
`bazzite-deck:stable` fallback deployment are modified by anything in this
project.

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
  t2-enablement-ublue.sh   # vendored from kansei-os/t2-atomic + one addition (see above)
  ublue-packages.sh        # vendored verbatim (installs ublue-brew)
  common/radio.tar         # vendored verbatim (Broadcom Wi-Fi/BT firmware)
etc-overlay/                # vendored verbatim from variants/common/etc/
  modprobe.d/apple-gmux.conf         # Radeon Pro dGPU muxing
  systemd/logind.conf.d/t2-lidswitch.conf  # T2 suspend/lid handling
  bluetooth/, dracut.conf.d/, fwupd/
LICENSE.kansei-os          # Apache-2.0, for the vendored files above
```
