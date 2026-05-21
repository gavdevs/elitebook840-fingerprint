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

`./setup.sh` (deps in its header), then `sudo bash scripts/syna-cli.sh`.
Debug loop: build is `-DDBGIMPORT=true`; read crashes with
`coredumpctl info <pid>`; live log at `/tmp/syna-cli.log`.
