# Acknowledgments & support repos

This work stands entirely on existing open-source reverse-engineering. Credit where
due — and pointers for anyone continuing.

## Core projects

- **[Popax21/synaTudor](https://github.com/Popax21/synaTudor)** — the driver-relinking
  framework this whole port is built on. PE-loads the real Synaptics Windows driver and
  shims Windows/WDF/crypto so it runs on Linux, exposed via a libfprint TOD module.
  Base commit for our port: `31dfdb0`. All of our changes are in the single
  `patches/synaTudor-hp110-storage-ipc.patch`. **Upstreaming this would help every EliteBook
  830 G7 / 840 G8 / 845 G8 owner** — see issues
  [#20](https://github.com/Popax21/synaTudor/issues/20) /
  [#40](https://github.com/Popax21/synaTudor/issues/40) (other non-`00be` PIDs).

- **[uunicorn/synaWudfBioUsb-sandbox](https://github.com/uunicorn/synaWudfBioUsb-sandbox)**
  and **[uunicorn/wine (validity-sensor branch)](https://github.com/uunicorn/wine)** —
  prior art running the Synaptics WBDI driver under hacked Wine; the HP-driver crash /
  `WppRecorderUM.dll` discussions ([issues #4/#5](https://github.com/uunicorn/synaWudfBioUsb-sandbox/issues))
  confirmed the HP-driver path is viable-but-bumpy.

- **[libfprint](https://gitlab.freedesktop.org/libfprint/libfprint)** — the open
  fingerprint library; its **Synaptics-authored** `synaptics` driver is what handles
  `06cb:00f0` today (and can't do the secure enroll). We used it to diagnose the root
  cause; diagnostic patch: `patches/libfprint-synaptics-diag.patch`. Base `d79f157`.
  - Decoding `BMKT_OUT_OF_MEMORY (104)` came straight from
    `libfprint/drivers/synaptics/bmkt.h`.

## Proprietary drivers (fetched, never committed)

- **HP SoftPaq `sp111238.exe`** — "Synaptics Fingerprint Sensor Driver" for the
  EliteBook 840/845 G8. Provides the **"110"** DLLs (`synaWudfBioUsb110.dll`,
  `synaFpAdapter110.dll`) for `06cb:00C0/C4/D8/DF/E9/F0`.
  `https://ftp.hp.com/pub/softpaq/sp111001-111500/sp111238.exe`
  (downloaded by `scripts/fetch-hp-driver.sh`).
- **Lenovo `r19fp02w.exe`** — the **"104"** driver synaTudor bundles by default
  (supports only `06cb:00be`); referenced for comparison.

## Tools

- **[innoextract](https://constexpr.org/innoextract/)** — to unpack the Inno Setup
  driver installers.
- **fwupd / LVFS** — confirmed sensor firmware is already current.

## Reference threads / issues

- libfprint: [#197 Synaptics enroll error](https://gitlab.freedesktop.org/libfprint/libfprint/-/issues/197),
  wiki [#38 unsupported firmware version](https://gitlab.freedesktop.org/libfprint/wiki/-/issues/38)
- Launchpad [#1893719](https://bugs.launchpad.net/oem-priority/+bug/1893719),
  [#2136962](https://bugs.launchpad.net/bugs/2136962) (missing `libfprint-2-tod1-synaptics`)
- Arch forum [Synaptics fingerprint w/ fprint](https://bbs.archlinux.org/viewtopic.php?id=267692)

## Licensing note

This repo contains only **our** original code (patches, scripts, docs) plus pointers
to upstream. It does **not** redistribute any proprietary HP/Synaptics/Lenovo binary
or the upstream project source — those are cloned/downloaded on demand by `setup.sh`.
Respect the licenses of synaTudor (its repo), libfprint (LGPL-2.1+), and the vendor
drivers (proprietary — local use only).
