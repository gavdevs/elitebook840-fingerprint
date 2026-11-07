# Changelog

All work done **2026-05-20** (single session), newest first within the day.
Format is narrative rather than release-versioned — this is a research log.

## [unreleased]

### 2026-11-06 — Do not report a deletion the sensor did not perform
- The vendor storage adapter answers `ERROR_SUCCESS` from `DeleteRecord` without
  removing anything when the template is not linked into its queryable database.
  Measured on `00df`: `Deleted 0 records with GUID 9367845f... finger 2`, then a
  successful identify of that same GUID. `tudor_storage_delete_records` now counts
  matching records after the call and fails when any remain, so fprintd surfaces
  the truth instead of claiming the fingerprint is gone.
- `IPC_MSG_CLEAR_RECORDS` now uses `EraseDatabase` on the sensor backend instead of
  deleting enumerated records one by one. Per-record deletion can leave exactly the
  unlinked template that makes the next enrollment of that finger fail as a
  duplicate.
- `tudor_storage_erase_database` reopens the DB session after erasing, so a clear
  leaves the device usable for the enrollment that follows it rather than requiring
  a driver restart.
- Context: Omarchy's `omarchy-remove-security-fingerprint` calls `fprintd-delete`,
  then drops `fprintd libfprint libfprint-git`, which deletes `/var/lib/fprint`.
  With the old silent-success behavior that left a stale template on the sensor and
  no host-side record, so the next enroll failed as a duplicate with nothing to
  point at. The removal path now gets an error it can report.

### 2026-11-06 — Packaging fixes found while installing
- `scripts/install-tudor-stack.sh` resolved the repo root to `scripts/`, so from any
  other working directory it looked for `scripts/work/synaTudor/build`. It now uses
  the parent of its own directory.
- `libfprint-git-compat` could not satisfy Omarchy's dependency check:
  `omarchy-pkg-missing` uses `pacman -Q libfprint-git`, which does not resolve
  `provides=`, so setup tried to install the real `libfprint-git` and hit its
  conflict with `libfprint-tod`. `packaging/libfprint-git-PKGBUILD` is now a package
  literally named `libfprint-git` (epoch 1, version above the omarchy repo build so
  upgrades leave it alone) that depends on `libfprint-tod` and ships no library.

### 2026-11-06 — EliteBook 830 G7 (`06cb:00df`) WORKING end-to-end
- The full chain now works on Omarchy/Arch: sensor → `tudor_host` → `libtudor_tod.so`
  → fprintd → `sudo`, polkit, and the lock screen. Right index enrolled and
  verified (`Verify GUID ... -> does match`).
- Consolidated the six incremental patches into one self-contained
  `patches/synaTudor-hp110-storage-ipc.patch` (50 files), verified to apply to synaTudor
  `31dfdb0`, build, and pass all 8 offline tests from a clean clone.
- `tudor_host` no longer `abort()`s on a defined adapter failure. Duplicate finger,
  failed commit, and dead capture are reported as `IPC_MSG_RESP_ERROR`, so a failed
  enroll no longer tears down the device session or crashes fprintd.
- Added `IPC_MSG_RESP_LIST_RECORDS` + `libfprint-tod/src/list.c` so the module can
  enumerate on-sensor records and delete ones it did not create.
- Root-caused the recurring "enrollment failed / duplicate" loop: the vendor query
  API cannot see every stored record, so `DeleteEnrolledFingers` reported
  `Deleted 0 records` while an orphaned right-index template stayed on the sensor.
  Only the database-wide `EraseDatabase` clears it; added `scripts/syna-erase-db.sh`
  (approval-gated, root) and documented the CLI input order the erase requires.
- Fixed two install defects: the launcher unit pointed at `/sbin/tudor`, and the
  udev rule landed in `/usr/lib/udev` where systemd-udev never reads it. Now
  `scripts/install-tudor-stack.sh` puts it in `rules.d` and uses `TAG+="uaccess"`
  instead of the nonexistent `plugdev` group.
- Captured the `libfprint-tod` and `libfprint-git-compat` PKGBUILDs under
  `packaging/`; fprintd needs a TOD-capable libfprint.

### 2026-11-05 — EliteBook 830 G7 (`06cb:00df`) local test preparation
- Added a focused source patch for the HP package-supported `00df` ID and
  a `TUDOR_OPEN_ONLY=1` CLI path that skips every post-open sensor command.
- Reworked the run wrapper for a finite 60 s attempt, retained the 8000 ms USB
  timeout, moved host pairing state/logs to checkout-local `state/`, and removed
  automatic autosuspend/service changes.
- Static open-path analysis found no way to disable the proprietary driver's
  ownership-change firmware update path before `tudor_open` returns. The wrapper
  therefore requires separate `TUDOR_FIRMWARE_WRITE_APPROVED=1` approval; this
  records approval rather than preventing firmware writes. No hardware test was
  executed.

### Track 1 — USB autosuspend (SOLVED)
- **Diagnosed:** `fprintd` enroll failed with `Corrupted message received` /
  `Ignoring device due to initialization error: unsupported firmware version`,
  intermittently. Root cause: the sensor's USB `power/control=auto` with a 2000 ms
  autosuspend delay — it slept after 2 s and returned a garbled first reply.
- **Fixed:** `power/control=on`. Permanent rule:
  `scripts/99-fingerprint-no-autosuspend.rules`. After this, enrollment got past
  init and reached actual capture.

### Track 2 — open libfprint driver (DEAD END, but fully diagnosed)
- Confirmed sensor is `06cb:00f0`, handled by libfprint's built-in (Synaptics-authored)
  `synaptics` driver; firmware already latest on LVFS.
- Enrollment failed instantly with `Enrollment failed (104)`. Decoded `104 =
  BMKT_OUT_OF_MEMORY` from the driver source.
- Built a **diagnostic patch** (`patches/libfprint-synaptics-diag.patch`) adding a
  `GET_DATABASE_CAPACITY` query + raw dump + probe-field logging + a tunable
  `user_id` length. Proved:
  - the bmkt DB is **empty** (`total=10 empty=10 used=0`) — *not* a "storage full" issue;
  - the sensor returns a **7-byte** capacity reply where the driver expects ≤4 →
    this firmware speaks a **newer protocol revision**;
  - enroll fails ~4 ms after `ENROLL_READY`, before any touch, regardless of
    `user_id` length → the firmware's secure enroll engine refuses.
- **Conclusion:** `06cb:00f0` is a *secure* (WBDI) sensor; the open driver can talk
  to it but cannot drive its v10 secure enroll. No proprietary `libfprint-2-tod1-synaptics`
  exists publicly (not in Ubuntu repos, not in the Dell OEM archive — only
  `-broadcom`/`-goodix` there).

### Track 3 — synaTudor HP-110 port (IN PROGRESS, ~90%)
- Chose to relink the **real Windows driver** via
  [synaTudor](https://github.com/Popax21/synaTudor), which PE-loads the driver DLLs
  and shims the Windows/WDF/crypto APIs.
- synaTudor ships a **Lenovo** driver supporting only `06cb:00be`. Our sensor needs
  HP's driver: SoftPaq **`sp111238.exe`** → the **"110" generation** DLLs
  (`synaWudfBioUsb110.dll`, `synaFpAdapter110.dll`); its INF lists
  `06cb:00C0/C4/D8/DF/E9/F0`.
- **Port changes** (`patches/synaTudor-hp110.patch`):
  - point the build at the HP "110" DLLs (`download_driver.sh`, `meson.build`);
    add `06cb:00f0` to the libfprint-tod id table + udev rules.
  - implemented the Windows APIs the 110 driver calls that the 104-tuned shim lacked,
    discovered one-by-one via the `-DDBGIMPORT` "unresolved import" loop and coredump
    backtraces:
    - `GetSystemFirmwareTable` — SMBIOS for host-pairing identity (read from
      `/sys/firmware/dmi/tables/*` in a load-time constructor, before the CLI drops root)
    - `CallNtPowerInformation` — stub
    - `GetModuleHandleW/A` + `winmodule_find` — handle `NULL` (was `strcmp(NULL)` → SIGSEGV)
    - **USER32 window layer** (`user32.c`): `RegisterClassExW`, `CreateWindowExW`
      (with `WM_NCCREATE`/`WM_CREATE` dispatch), `Get/SetWindowLongPtrW`,
      `DefWindowProcW`, `CallWindowProcW`, message-loop no-ops — for the driver's
      `CPowerStateWindow`; plus `WTSRegister/UnRegisterSessionNotification`
    - **CAPI AES symmetric crypto** (`crypt.c`): `CryptSetKeyParam`/`CryptGetKeyParam`/
      `CryptEncrypt`/`CryptDecrypt` (OpenSSL EVP, CBC + PKCS7, CBC chaining)
    - `LoadLibraryW`
    - env-gated infinite-USB-timeout clamp (`SYNA_USB_TIMEOUT`) so a stuck read fails
      instead of hanging forever
- **Result:** the HP driver **runs on Linux** — completes device init, **pairs**,
  brings up the **TLS secure channel**, performs AES-GCM auth crypto, and **reads the
  sensor's secure DB** (`VCSFW_CMD_DB2_GET_DB_INFO`: 0 templates, 11 free slots,
  1 user/payload). Almost certainly the first public success driving this sensor's
  secure stack on Linux.
- **Blocked:** the driver's internal enrollment enumeration chokes on the lone
  secure-DB user record (`_GetCommonPropUsrObjId failed(118)`), so `tudor_open`
  loops and never completes. Confirmed the TLS/"output buffer too small" warnings
  are benign (two-pass size queries); the crypto works. Cold boot + cleared host
  store did not help (record is in sensor flash). The loop is inside the closed
  driver blob — can't be patched or skipped from our side.

### Housekeeping
- Consolidated three scratch clones + scattered `$HOME` scripts into this single
  repo. Captured all our changes as patches; proprietary DLLs kept out of git and
  fetched on demand.
