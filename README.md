# EliteBook 840 G8 Fingerprint on Linux (Synaptics `06cb:00f0`)

Getting the **Synaptics FS7605 "PurePrint" fingerprint sensor** (`06cb:00f0`) working
on Linux in an **HP EliteBook 840 G8** (also 845 G8), running Kubuntu / Ubuntu 26.04.

This repo captures everything from that effort: a **working fix** for one real
problem, a **~90%-complete reverse-engineering port** for the hard problem, and a
full write-up so anyone (future me included) can continue.

---

## TL;DR — current status

| Track | Status |
|---|---|
| **USB autosuspend fix** (sensor kept getting put to sleep) | ✅ **Working** — see [`scripts/99-fingerprint-no-autosuspend.rules`](scripts/99-fingerprint-no-autosuspend.rules) |
| **Actual enrollment via the open `libfprint` driver** | ❌ Dead end — this firmware needs a *secure* enroll the open driver can't do (`Enrollment failed (104)` = `BMKT_OUT_OF_MEMORY`) |
| **Running the real Windows driver via [synaTudor](https://github.com/Popax21/synaTudor)** | 🟡 **~90%** — driver loads, **pairs, brings up the TLS channel, and reads the sensor's secure DB**; blocked on a stale secure-DB record |

Full story: [`CHANGELOG.md`](CHANGELOG.md) · deep technical detail: [`docs/FINDINGS.md`](docs/FINDINGS.md) · credit to the projects that made this possible: [`docs/ACKNOWLEDGMENTS.md`](docs/ACKNOWLEDGMENTS.md).

---

## The device

- **Sensor:** Synaptics FS7605 Touch Fingerprint Sensor w/ PurePrint, USB `06cb:00f0`
- **Class:** "Synaptics UWP WBDI" — a **secure / match-in-sensor** sensor (Windows Hello style), firmware **v10.1** (build `3273255`, latest on LVFS)
- **Laptop:** HP EliteBook 840 G8 (and 845 G8), Kubuntu / Ubuntu 26.04, kernel 7.0

Two independent on-sensor storage areas matter here:
- the **bmkt** DB the open libfprint driver sees (BIOS "fingerprint reset" clears this), and
- the **tudor DB2** secure store (126 user slots) the *secure* driver uses — **not** cleared by BIOS reset.

---

## Quick start

### 1. The autosuspend fix (independent, recommended regardless)
The sensor is put into USB autosuspend after 2 s; its first reply then comes back
garbled. Install the rule to keep it awake:
```bash
sudo cp scripts/99-fingerprint-no-autosuspend.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 2. Build the synaTudor HP-110 port
```bash
# install build deps (see setup.sh header), then:
./setup.sh
```
This clones synaTudor at the pinned base commit, applies [`patches/synaTudor-hp110.patch`](patches),
fetches the HP driver DLLs ([`scripts/fetch-hp-driver.sh`](scripts/fetch-hp-driver.sh)), and builds.

### 3. Run the CLI test
```bash
sudo bash scripts/syna-cli.sh      # press 'y'; menu: e=enroll i=identify q=query w=wipe
```

---

## Repo layout

```
.
├── README.md                 # this file
├── CHANGELOG.md              # chronological account of the whole effort
├── setup.sh                  # reproduce the build from a clean checkout
├── patches/
│   ├── synaTudor-hp110.patch          # our port: HP "110" driver support + ~10 Win-API shims
│   └── libfprint-synaptics-diag.patch # diagnostic patch used to prove root causes
├── scripts/
│   ├── 99-fingerprint-no-autosuspend.rules   # ✅ the working autosuspend fix
│   ├── fetch-hp-driver.sh     # download + extract the HP "110" DLLs (proprietary; not in git)
│   ├── syna-cli.sh            # run the synaTudor CLI against 06cb:00f0
│   └── fp-test.sh, fp-debug-on.sh, fp-debug-off.sh   # libfprint diagnostics
├── docs/
│   ├── FINDINGS.md            # deep technical findings
│   └── ACKNOWLEDGMENTS.md     # the upstream repos/drivers that got us here
└── work/   (git-ignored)      # live build tree (synaTudor clone + build + HP DLLs)
```

> **No proprietary binaries are committed.** The HP/Synaptics driver DLLs are
> fetched on demand from HP's public SoftPaq and live only under git-ignored `work/`.

---

## Where it's blocked (the last 10%)

The HP driver runs on Linux and reaches its **own** secure-DB enumeration during
device bring-up, where it chokes on a leftover record
(`NumCurrentUsers=1` / `_GetCommonPropUsrObjId failed(118)`) and loops, so
`tudor_open` never completes. That loop is **inside the closed driver blob**, and
clearing the record needs the menu, which needs open to finish — a catch-22.
See [`docs/FINDINGS.md`](docs/FINDINGS.md) → *The wall* and *Ways forward*.

## Credits

Built entirely on the shoulders of open-source RE work — see
[`docs/ACKNOWLEDGMENTS.md`](docs/ACKNOWLEDGMENTS.md). Especially
**[Popax21/synaTudor](https://github.com/Popax21/synaTudor)** (the driver-relinking
framework) and **[uunicorn](https://github.com/uunicorn/synaWudfBioUsb-sandbox)**.
