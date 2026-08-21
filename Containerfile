# t2-bazzite-deck
#
# Combines:
#   - Bazzite's Deck/Gaming Mode image (gamescope-session-ogui-steam,
#     steamos-manager-powerstation, inputplumber, Return-to-Gaming-Mode,
#     Steam Desktop/Big Picture)
#   - Kansei's T2-Atomic hardware-enablement layer (T2 kernel, T2 audio/
#     keyboard/trackpad stack via t2linux-release, t2fanrd, Apple Wi-Fi/BT
#     firmware, apple-gmux dGPU muxing for the Radeon Pro dGPU)
#
# This mirrors kansei-os/t2-atomic's own variants/t2-bazzite/Containerfile
# (https://github.com/kansei-os/t2-atomic, commit ef80157 as of 2026-08-20),
# which builds FROM ghcr.io/ublue-os/bazzite:stable (the plain desktop image,
# no Gaming Mode). The only architectural change here is the base image:
# ghcr.io/ublue-os/bazzite-deck:stable instead of :bazzite:stable. Everything
# else -- the enablement script and the /etc overlay -- is Kansei's own,
# vendored verbatim under build_files/ and etc-overlay/ (Apache-2.0,
# see LICENSE.kansei-os), with one addition documented below.
#
# Verified locally (podman build, see README.md "What was tested"):
#   - T2 kernel (7.1.8-200.t2.fc44), t2fanrd, t2linux-release all install
#     cleanly on top of bazzite-deck:stable.
#   - gamescope-session-ogui-steam, steamos-manager-powerstation,
#     inputplumber, terra-gamescope, jupiter-fan-control (disabled by
#     default) all survive the T2 layering intact.
#   - apple-gmux.conf (dGPU muxing) and T2 lid/suspend logind overrides
#     from Kansei's /etc overlay are present in the final image.
#
# One deviation from Kansei's upstream script: as of Bazzite's current
# Fedora 44 "-ogc" kernel build, several akmod-built kernel modules
# (kmod-evdi, kmod-gcadapter_oc, kmod-hid-fanatecff, kmod-kvmfr,
# kmod-nct6687d) pin to that exact kernel via the kernel-uname-r
# capability and are not in Kansei's static removal list, which breaks
# the T2 kernel override with a depsolve conflict (reproduced locally,
# and it's the same root cause behind kansei-os/t2-atomic issue #71,
# "Multiple Workflows Keep Failing"). None of these modules apply to
# Apple hardware. build_files/t2-enablement-ublue.sh adds a removal
# sweep keyed on the kernel-uname-r capability itself (not a hand-typed
# name list) so a future Bazzite kernel rebuild adding another such
# module doesn't silently reintroduce this break. See the comment in
# that script for the exact diff against upstream.
#
# Upstream sources:
#   https://github.com/kansei-os/t2-atomic  (variants/t2-bazzite/Containerfile)
#   https://github.com/ublue-os/bazzite     (bazzite-deck image)

ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-deck
ARG BASE_TAG=stable

FROM scratch AS ctx
COPY build_files /

FROM ${BASE_IMAGE}:${BASE_TAG}

# T2-specific /etc drop-ins: apple-gmux dGPU muxing, T2 lid/suspend logind
# overrides, Bluetooth/dracut/fwupd config. Vendored verbatim from
# kansei-os/t2-atomic variants/common/etc/.
COPY --chmod=0644 /etc-overlay/ /etc/

# T2 kernel swap + Apple hardware enablement (kernel, t2fanrd, iwd +
# Broadcom Wi-Fi/BT firmware, apple-gmux, suspend masking). See
# build_files/t2-enablement-ublue.sh for the one deviation from upstream.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/var \
    /ctx/t2-enablement-ublue.sh && \
    rm -rf /tmp/* /var/tmp/*

# Vendored verbatim from kansei-os/t2-atomic (installs ublue-brew).
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/ublue-packages.sh

RUN bootc container lint

LABEL containers.bootc 1
LABEL ostree.bootable 1
