# Findings — Synaptics `06cb:00f0` on Linux

Technical detail behind the [CHANGELOG](../CHANGELOG.md). Useful if you're trying
to finish this, or hit the same sensor on another machine.

## 1. The hardware & two storage areas

- `06cb:00f0` = Synaptics **FS7605 PurePrint**, a **secure / match-in-sensor**
  ("Synaptics UWP WBDI") sensor. Firmware **v10.1**, build `3273255` (latest on LVFS;
  `fwupdmgr` shows it up to date — a firmware update is *not* the fix).
- It exposes **two independent on-sensor databases**:
  1. a legacy **bmkt** DB (what the open libfprint `synaptics` driver speaks; ~10 slots)
  2. a **tudor "DB2"** secure store (126 user slots / template slots), used only over
     the encrypted channel.
- **Critical:** the HP BIOS "fingerprint reset" clears the **bmkt** DB but **not**
  the DB2. That's why BIOS resets "didn't work."

## 2. USB autosuspend (the one clean win)

`/sys/bus/usb/devices/<x>/power/control = auto`, `autosuspend_delay_ms = 2000`.
The sensor slept after 2 s; the next command woke it mid-transfer and the first
reply was corrupted → `fprintd`: *Corrupted message received* → *unsupported
firmware version*, intermittently. Fix = `power/control=on`
(`scripts/99-fingerprint-no-autosuspend.rules`).

## 3. Why the open libfprint driver can't enroll

- The built-in `synaptics` driver (Synaptics' own contribution) matches `00f0` and
  talks bmkt fine: version, FPS_INIT, and a `GET_DATABASE_CAPACITY` we added all work.
- Enroll fails **instantly** with `Enrollment failed (104)` = **`BMKT_OUT_OF_MEMORY`**,
  ~4 ms after `ENROLL_READY`, **before any finger**, on an **empty** DB, **regardless
  of `user_id` length**.
- The capacity reply is **7 bytes** where the driver's parser allows only 2–4 → this
  firmware is a **newer bmkt revision** than libfprint implements.
- Interpretation: real enrollment on this firmware requires the **secure (WBDI/TLS)
  path**, which the open driver doesn't implement. Hence the pivot to running the
  real Windows driver.
- (Diagnostics that proved all this: `patches/libfprint-synaptics-diag.patch`.)

## 4. The synaTudor relink approach

[synaTudor](https://github.com/Popax21/synaTudor) doesn't reimplement the protocol —
it **PE-loads the actual Windows driver DLLs** (`libtudor` = PE loader + Windows /
WDF / bcrypt / CAPI shims), runs them, and exposes the sensor through a libfprint TOD
module. synaTudor ships a **Lenovo** driver good only for `06cb:00be`.

For `00f0` we substitute **HP's** driver (SoftPaq `sp111238.exe`), the **"110"
generation** (`synaWudfBioUsb110.dll` + `synaFpAdapter110.dll`). It uses the standard
WBF entry points (`FxDriverEntryUm`, `WbioQuerySensorInterface/...EngineInterface`),
so it's interface-compatible — but it calls extra Windows APIs the 104-tuned shim
didn't provide.

### Windows APIs we had to add (the `-DDBGIMPORT` loop)
Build with `-DDBGIMPORT=true`; unresolved imports log their name when called
(SIGABRT in a coredump → `coredumpctl info`). Each one we then implemented:

| Import | Why the driver calls it | Our handling |
|---|---|---|
| `GetSystemFirmwareTable` | reads SMBIOS to derive a **host-pairing identity** | serve real DMI from `/sys/firmware/dmi/tables/*`, cached in a load-time constructor (root, before priv-drop) |
| `CallNtPowerInformation` | power query during init | success + zeroed output |
| `GetModuleHandleW/A(NULL)` | "handle to main module" | return current module (was `strcmp(NULL)` → **SIGSEGV**) |
| USER32 (`RegisterClassExW`, `CreateWindowExW`, `Get/SetWindowLongPtrW`, `DefWindowProcW`, `CallWindowProcW`, msg loop) | the driver's **`CPowerStateWindow`** | minimal real window layer in `user32.c` |
| `WTSRegister/UnRegisterSessionNotification` | session-change notifications | success |
| `CryptSetKeyParam/GetKeyParam/Encrypt/Decrypt` | **CAPI symmetric crypto** (this driver uses legacy CAPI; the 104 used BCrypt) | OpenSSL EVP, AES-CBC + PKCS7, CBC chaining (`crypt.c`) |
| `LoadLibraryW` | loads a helper DLL during pairing | wrap `LoadLibraryExW` |

## 5. How far it gets (the breakthrough)

With the above, the HP driver, **on Linux**:
1. PE-loads, runs `DriverEntry` → `EvtDeviceAdd` → `OnPrepareHardware`,
2. opens the USB device, sets interrupt endpoints, runs `tudorOpen`/`tudorUsbProtoOpen`,
3. **pairs** with the host, brings up the **TLS** channel (`ssiTlsWrap`/`Unwrap`),
   does **AES-GCM** auth crypto (`palCryptoEncryptAuth`/`DecryptAuth`),
4. **reads the secure DB**: `VCSFW_CMD_DB2_GET_DB_INFO` →
   `NumCurrentUsers=1, NumCurrentPayloads=1, NumCurrentTemplates=0`, 126 free user
   slots, 11 free template slots; then `VCSFW_CMD_DB2_GET_OBJECT_LIST`.

The encrypted secure channel to the sensor is **live and working**.

## 6. The wall

During the driver's **own** device bring-up (inside the closed `synaWudfBioUsb110.dll`,
before `libtudor`'s `tudor_open` returns), it enumerates the secure DB and chokes on
the lone user record:
```
_GetCommonPropUsrObjId failed(118)
stiTudorGetNextEnrollment() failed
```
…then loops forever (re-pair → check sensor SBL bootloader → close → repeat), so
`tudor_open` never completes and we never reach the CLI menu.

- The recurring `TLS context is not initialized` warnings are **benign** (per-op
  rechecks; `ssiTlsUnwrap` succeeds). The `palCrypto: Output buffer too small`
  warnings are **benign** two-pass size queries (the op completes immediately after).
  So the crypto/TLS we built are sound.
- An infinite (`timeout=0`) libusb bulk read was making it *hang*; the
  `SYNA_USB_TIMEOUT` clamp turns that into a *failure* instead, but the driver just
  loops on the failure.
- **Catch-22:** clearing the bad record needs the CLI menu; the menu needs
  `tudor_open` to finish; open dies on the record. The loop is in the **closed driver
  blob**, so it can't be patched or told to skip.
- Cold-boot + cleared host store (`~/.tudor-store`) did **not** help — the record is
  in the sensor's **persistent flash** (and may be a malformed record our own
  kill-9'd pairing runs wrote, vs leftover Windows data — undetermined).

## 7. Ways forward (all heavy)

1. **Normalize/clear the DB2 from another OS** (Windows Hello "remove all" /
   Synaptics tool writes a well-formed or empty DB2). Then the port likely finishes.
   *Rejected by the owner (no Microsoft).*
2. **Determine if our own pairing writes the malformed user object** and fix the
   storage/crypto round-trip so the driver can read it — all-Linux, deep, uncertain.
3. **Reverse-engineer the tudor DB2 "delete user / format" command** and issue it on
   the secure channel before the driver's enumeration — large.
4. **Upstream** the HP-110 work to synaTudor so the community can finish `00f0`.

## Reproduce / continue

`./setup.sh` (deps in its header) prepares the build only. The local `00df` wrapper
is deliberately approval-gated; see below. Debug builds use `-DDBGIMPORT=true`.
Crash analysis with `coredumpctl info <pid>` is host-side and optional.

## 8. EliteBook 830 G7 (`00df`) open-only preparation and firmware boundary

`patches/synaTudor-hp110-storage-ipc.patch` adds the package-listed `06cb:00df` ID and an
environment-controlled exit after successful `tudor_open` (`TUDOR_OPEN_ONLY=1`). The
CLI then saves its local pairing data and closes normally without accepting post-open
commands. The wrapper uses `state/tudor-store`, not a prior developer's home
directory. That open-only guard is only relevant to the probe wrapper; the working
stack (section 9) runs the same code path with post-open commands enabled.

This guard is **not** a firmware-update guard. `tudor_open` calls the proprietary
HP DLL's hardware-preparation and pipeline initialization before returning. Those
DLLs can issue arbitrary control/bulk writes; the open-source USB layer does not
classify them as reads, pairing, DB2 mutation, SBL entry, or image download. The
native registry state includes `DeviceUpdateInProcess`,
`updateFirmwareFailureCount`, and `LastUpdateSystemTimeStamp`. Together with the
observed ownership-change reflash note and repeated SBL checks, that makes firmware
writes reachable during the first open. Static source evidence does not establish
that a particular attempt actually completed a reflash.

No disable flag was found in the CLI, HP patch, native DLL environment, or registry
state. `TUDOR_OPEN_ONLY` and `SYNA_USB_TIMEOUT` respectively suppress post-open CLI
commands and clamp waits; neither filters outbound USB writes. A protocol-aware
write guard validated on an offline/mock transport, or a precisely identified DLL
update-branch patch, is required before calling this firmware-safe. The wrapper's
`TUDOR_FIRMWARE_WRITE_APPROVED=1` check is only an approval gate, not a technical
prevention mechanism.

For log triage, the useful markers are:
- secure channel activity: `ssiTlsWrap`, successful `ssiTlsUnwrap`, and
  `palCryptoEncryptAuth` / `palCryptoDecryptAuth`;
- secure DB2 reads: `VCSFW_CMD_DB2_GET_DB_INFO`, a response containing
  `NumCurrentUsers=`, and `VCSFW_CMD_DB2_GET_OBJECT_LIST`;
- complete host-side open-only success: `Open-only test succeeded; skipping all
  post-open sensor commands` followed by `Saving data to data store`;
- the known unresolved DB2 enumeration defect: `_GetCommonPropUsrObjId failed(118)`
  and `stiTudorGetNextEnrollment() failed`, especially when followed by another
  pairing/SBL/open cycle. DB2 reads before these lines do not mean open completed.

`TLS context is not initialized` and `palCrypto: Output buffer too small` are not by
themselves failures when the subsequent unwrap/size retry succeeds.

## 9. Why `00df` works and where enrollment actually fails

The `00df` sensor completes the same secure path that `00f0` stalls in: driver init,
pairing, TLS, DB2 access. The difference is the state of the sensor's own database,
not the driver.

### The duplicate-enrollment trap

`WinBioEnrollCommit` refuses a finger that already has a record and the vendor
framework then discards the pending enrollment. The old host-side code turned that
into `abort()`, which killed `tudor_host` mid-session; `fprintd` saw a dead IPC peer
and segfaulted. The logs looked like a crash, not a duplicate:

```
Enrollment of GUID 9fcfd7fb... finger 2 is a duplicate - discarding
Reported IPC error code 1 to the module
fprintd.service: Main process exited, code=dumped, status=11/SEGV
Failed to start Tudor host process ... ObjectPathInUse: A host for this USB device already exists
```

After the patch the same condition surfaces as a normal fprintd error
(`FP_DEVICE_ERROR_DATA_DUPLICATE`) and the device stays usable.

### The record the query API cannot see

The critical asymmetry:

| Operation | Scope |
|---|---|
| `QueryByContent` / `FirstRecord` / `NextRecord` | records the vendor DB links normally |
| `DeleteEnrolledFingers` (fprintd) | only records exposed by that query |
| `EraseDatabase` (adapter interface) | **entire** database, linked or not |

A record can exist, answer identify (`Identify result -> matches GUID 00000001...`),
and still be invisible to enumeration. Observed symptoms of exactly that state:

```
[INF] Cleared 0 records
[INF] Identify result -> matches GUID 00000001... finger 2
[INF] Deleted 0 records with GUID 00000001... finger 2
[WRN] Enrollment of GUID <new>... finger 2 is a duplicate - discarding
```

So fprintd reports "no fingers enrolled", every new enrollment of that finger is
rejected as a duplicate, and no amount of `fprintd-delete` clears it. Only
`EraseDatabase` does, and it needs the vendor adapter from `tudor_cli`.

### Current gaps in the TOD module worth closing

- Enrollment records created on the sensor have `record size 0`: the template lives
  in sensor flash and the host stores identity only
  (`Committed enrollment ... no host side record data`). `EraseDatabase` is
  therefore destructive and unrecoverable by design.
- `tudor-host-launcher` keeps a host object per USB device. A crashed session leaves
  it behind, and every later `fprintd` start fails with `ObjectPathInUse` until the
  launcher is restarted. Making the launcher reap a dead host's object, or keying it
  on the current `fprintd` connection, would remove a manual restart.
- `EraseDatabase` tears down the adapter's DB session; the driver must be reopened
  before the database is usable again. Any future in-process caller has to reload
  the device rather than continuing.
