# HP EliteBook fingerprint on Linux — Synaptics secure sensors (`06cb:00df`, `06cb:00f0`)

Getting a **secure (match-in-sensor) Synaptics fingerprint reader** working on Linux
by relinking the real Windows driver with [synaTudor](https://github.com/Popax21/synaTudor).

**Status: working on the EliteBook 830 G7 (`06cb:00df`)** under Omarchy/Arch —
sensor → Tudor host → libfprint TOD module → fprintd → `sudo`, polkit, and the lock
screen. See [Working stack](#working-stack-06cb00df) for reproduction.

---

## TL;DR

| Track | Sensor | Status |
|---|---|---|
| **TOD enrollment + auth** | `06cb:00df` | ✅ **Working** — enroll, verify, `sudo`/polkit/lock via PAM |
| USB autosuspend | `06cb:00f0` | ✅ [rule](scripts/99-fingerprint-no-autosuspend.rules) (not installed) |
| Open libfprint driver enroll | `06cb:00f0` | ❌ Dead end — firmware needs a secure enroll (`104` = `BMKT_OUT_OF_MEMORY`) |
| TOD enroll | `06cb:00f0` | 🟡 Driver loads, pairs, TLS up, reads DB2; blocked on a stale DB2 record |

Deep detail: [`docs/FINDINGS.md`](docs/FINDINGS.md) · history: [`CHANGELOG.md`](CHANGELOG.md) · credits: [`docs/ACKNOWLEDGMENTS.md`](docs/ACKNOWLEDGMENTS.md).

---

## Working stack (`06cb:00df`)

Verified end-to-end on an HP EliteBook 830 G7 running Omarchy (Arch, fprintd 1.94.5).

```
fprintd ──► libtudor_tod.so (libfprint TOD module)
              └─ D-Bus ──► tudor_host_launcher (root)
                             └─ tudor_host ──► HP "110" WBDI DLL ──► USB 06cb:00df
```

### Build and install

```bash
./setup.sh                                  # clone base + apply patch + build + run offline tests
sudo bash scripts/install-tudor-stack.sh    # binaries, TOD module, unit, D-Bus, udev rule
sudo omarchy setup security fingerprint     # enroll right index; writes PAM for sudo/polkit/lock
```

`./setup.sh` applies [`patches/synaTudor-hp110-storage-ipc.patch`](patches/synaTudor-hp110-storage-ipc.patch) to
synaTudor at `31dfdb0` and builds `libtudor`, `tudor_host`, `tudor_host_launcher`,
`tudor_cli`, and `libtudor_tod.so`. The patch is self-contained: a clean checkout
builds and passes all 8 offline tests.

`fprintd` needs a `libfprint` that supports TOD modules. `packaging/` holds the two
PKGBUILDs used here: `libfprint-tod`, and a stub literally *named* `libfprint-git`
(epoch 1, no library) because Omarchy's setup checks that package name with
`pacman -Q`, which does not resolve `provides=`, and the real `libfprint-git`
conflicts with `libfprint-tod`. No proprietary binary is committed; the HP DLLs are
fetched from HP's SoftPaq by
[`scripts/fetch-hp-driver.sh`](scripts/fetch-hp-driver.sh) into git-ignored `work/`.

### What the patch adds

- **HP "110" driver support** — ID tables (`00be`/`00f0`/`00df`), DLL paths, and the
  Windows APIs the 110 driver needs that upstream's 104-tuned shim lacked:
  `GetSystemFirmwareTable` (SMBIOS host identity), `CallNtPowerInformation`,
  USER32 window layer, WTS session notifications, CAPI AES/RSA (`CryptEncrypt`,
  `CryptSetKeyParam`, …), `GetLocalTime`, `LoadLibraryW`.
- **Vendor sensor storage** — `WinBio` storage adapter calls (`OpenDatabase`,
  `QueryByContent`, `FirstRecord`/`NextRecord`, `CommitEnrollment`, `DeleteRecord`,
  `EraseDatabase`), identity GUID + finger tracking, and capture retry bounds.
- **IPC error reporting** — the host reports defined failures (duplicate finger,
  failed commit, dead capture) as `IPC_MSG_RESP_ERROR` instead of `abort()`ing and
  killing the device session. Without this a duplicate enroll killed `fprintd`.
- **TOD record listing** — `IPC_MSG_RESP_LIST_RECORDS` lets the module enumerate
  on-sensor records, so records created outside the current process can be listed
  and deleted.
- **WDF teardown fix** — unlinking a WDF object whose parent is already dead no
  longer deadlocks.
- **Install fixes** — launcher unit uses `/usr/bin/tudor` (was `/sbin`), and the
  udev rule goes to `rules.d` (meson's `udevdir` points one level too high, which
  left an inert rule in `/usr/lib/udev`).

### Two gotchas that cost the most time

1. **"Enrollment failed" on a sensor that already holds that finger.** The vendor
   DB query API cannot enumerate every record. A leftover right-index template makes
   every new right-index enroll fail as `enroll-duplicate`, and `fprintd`'s
   `DeleteEnrolledFingers` removes only records it can see (`Deleted 0 records`).
   Fix: erase the whole sensor DB with `tudor_cli` (`d`, then `ERASE`) as root,
   with `TUDOR_DB_ERASE_APPROVED=1`; then restart the launcher.
2. **`ObjectPathInUse: A host for this USB device already exists`.** After a crashed
   enrollment the launcher keeps a stale host object and `fprintd` refuses the
   device. Restart `tudor-host-launcher` (which also drops `fprintd`'s claim), then
   `fprintd`.

### Firmware-write boundary

`tudor_open` reaches the proprietary driver's hardware-preparation code before the
CLI regains control, so any run of the vendor stack can issue firmware/ownership
writes. The approval-gated wrappers (`scripts/syna-cli.sh`,
`scripts/syna-enroll-verify.sh`) require `TUDOR_FIRMWARE_WRITE_APPROVED=1`; that
records approval, it does not prevent writes. See
[`docs/FINDINGS.md`](docs/FINDINGS.md) §8.

---

## The `06cb:00f0` track (EliteBook 840/845 G8)

- **Sensor:** Synaptics FS7605 PurePrint, USB `06cb:00f0`, firmware v10.1 (latest on LVFS)
- The open libfprint `synaptics` driver talks to it but cannot drive its secure
  enroll: `Enrollment failed (104)` = `BMKT_OUT_OF_MEMORY`, raised ~4 ms after
  `ENROLL_READY`, before any touch. The bmkt DB is empty (proved with
  [`patches/libfprint-synaptics-diag.patch`](patches/libfprint-synaptics-diag.patch));
  the firmware speaks a newer protocol revision than the driver expects.
- The TOD route gets further — driver init, pairing, TLS secure channel, and DB2
  reads all work — but the closed driver loops during its own DB2 enumeration on a
  lone stale record (`_GetCommonPropUsrObjId failed(118)` /
  `stiTudorGetNextEnrollment() failed`), so `tudor_open` never returns.

The database-wide erase in `tudor_cli` (command `d`) exists precisely to clear
records that enumeration cannot see; that is what unblocked `00df`. It is the first
thing to try on a `00f0` unit with a stale DB2 entry.

---

## Repo layout

```
.
├── README.md
├── CHANGELOG.md
├── setup.sh                    # clone + patch + build + offline tests (no system changes)
├── patches/
│   ├── synaTudor-hp110-storage-ipc.patch  # HP 110 shims, vendor storage, IPC errors, TOD listing
│   └── libfprint-synaptics-diag.patch # diagnostic patch used to prove the 00f0 root cause
├── scripts/
│   ├── fetch-hp-driver.sh      # download + extract HP "110" DLLs (proprietary; not in git)
│   ├── install-tudor-stack.sh  # install binaries, TOD module, unit, D-Bus, udev rule
│   ├── syna-erase-db.sh        # root: erase the whole sensor DB (approval-gated)
│   ├── syna-cli.sh             # gated, bounded open-only probe
│   ├── syna-enroll-verify.sh   # gated single enroll + verify through tudor_cli
│   ├── syna-verify-fresh.sh    # gated read-only verify against existing records
│   ├── syna-inspect-vendor.sh  # vendor storage inspection
│   └── 99-fingerprint-no-autosuspend.rules, fp-*.sh   # original 00f0 diagnostics
├── packaging/
│   ├── libfprint-tod-PKGBUILD, libfprint-git-PKGBUILD
│   ├── 60-tudor-libfprint-tod.rules
│   └── net.reactivated.TudorHostLauncher.service
├── docs/
│   ├── FINDINGS.md
│   └── ACKNOWLEDGMENTS.md
├── work/   (git-ignored)       # synaTudor clone + build + HP DLLs
└── state/  (git-ignored)       # host pairing store and logs
```

---

## Credits

Built entirely on open-source reverse-engineering — see
[`docs/ACKNOWLEDGMENTS.md`](docs/ACKNOWLEDGMENTS.md). Especially
**[Popax21/synaTudor](https://github.com/Popax21/synaTudor)** and
**[uunicorn/synaWudfBioUsb-sandbox](https://github.com/uunicorn/synaWudfBioUsb-sandbox)**.
