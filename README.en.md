# ASUS Z790 + macOS: BIOS 1904 or newer hangs the Hackintosh — the `RP25.AWAK` fix

[🇧🇷 Português](README.md) · 🇺🇸 **English** · [🇪🇸 Español](README.es.md)

Two ACPI patches for **OpenCore** that make macOS boot again on ASUS BIOS **1904 and newer**
(tested on the **ROG STRIX Z790-E GAMING WIFI, BIOS 3202**, the latest). Without them, the Hackintosh only works up to
BIOS 1801 (Dec 2023), which lacks Intel's fixes for the 13th/14th-gen CPU degradation issue.

**It's a single file:** [`patch/RP25-AWAK.plist`](patch/RP25-AWAK.plist). Copy its two entries into
`ACPI > Patch` of your `config.plist`. Nothing else in the EFI changes.

---

## Do you have this problem?

- **ASUS** 700-series board (Z790) on BIOS **1904 or newer** (up to 1801 it works).
- macOS hangs early in boot. With `-v` (verbose) it stops right after `adding acpi-wake-type property`.
- **The telltale sign** shows up right after the `ACPI: ...` table list (it scrolls fast — record it in slow motion):
  ```
  ACPI Error: [\_SB_.PC00.RP25] Namespace lookup failure, AE_NOT_FOUND (20160930/dswload-292)
  ACPI Exception: AE_NOT_FOUND, (DSDT) table load failed (20160930/tbxfload-209)
  ...
  ACPI Error: 8 table load failures, 13 successful
  ```
  followed by a flood of `Namespace lookup failure` and `Invalid handle ... (Not a Descriptor)`.
- Windows works fine on the same BIOS.

**Not sure?** Run the checker ([Check](#check-whether-your-bios-needs-it)). It reads your BIOS table and tells you.

---

## Plain-language explanation

The BIOS hands the operating system a kind of hardware "map" called the **DSDT**. Starting with version 1904, ASUS put
a line in that map saying "inside the **RP25** part, add the **AWAK** function". The catch: the RP25 part is only
created **later**, further down the same map.

- **Windows** reads the map leniently: it sees the error, skips that line and carries on.
- **macOS** uses a map reader from **2016** that is much stricter: when it hits the error, it **throws the whole map
  away**. Without the map, the Mac can't find most of the hardware (CPU, USB, graphics…) and hangs.

The patch changes the line's address: instead of "inside RP25" it says "inside **LPCB**", a part that already exists at
that moment. The function is still there (and still called when the PC wakes from sleep), but the macOS reader no
longer trips over it. **Nothing is written to the BIOS**: OpenCore only fixes what macOS receives, on every boot.
Remove the patch and everything is back as it was.

---

## Technical explanation

From 1904 on, the DSDT (OEM `ALASKA` / `A M I`) contains, **at table level** (outside any `If`/`Method`):

```asl
Scope (_SB.PC00.RP25)
{
    Method (AWAK, 1, NotSerialized)
    {
        If ((UHCS == One))
        {
            If (((Arg0 == 0x03) || (Arg0 == 0x04))) { WK34 = One }
        }
    }
}
```

and `\_WAK` now calls `\_SB.PC00.RP25.AWAK (Arg0)`. But `Device (RP25)` is only declared **inside**
`If (LPEN == Zero)` (in `\_SB.PC00`) and `If (PCHS == 0x04)` (in `\_SB.PC00.VMD0`).

AppleACPIPlatform embeds **ACPICA 20160930**. In that version:
1. module-level code (the `If` blocks outside methods) only runs **after** the table is loaded, so when the `Scope` is
   parsed, `RP25` does not exist yet → `AE_NOT_FOUND` in `dswload`;
2. **any error during table load rejects the whole table**. That only changed in ACPICA 20180531/20180810
   (*"continue loading ACPI tables regardless of malformed AML"*).

Result: the DSDT is discarded, taking down every SSDT that depends on it (`CpuSsdt`, `SaSsdt`, `IgfxSsdt`, `xh_*`,
`SSDT-EC`, `SSDT-HPET`…). Windows and current ACPICA (`acpiexec` 2024) load the same DSDT without errors. Up to 1801,
the only `Scope (_SB.PC00.RP25)` in the DSDT was **inside** `If (PCHS == 0x04)`, which is why it worked.

### The patch

Retargets to `\_SB.PC00.LPCB` (declared outside any `If`, exists at load time, has no `AWAK`), both in the definition
and in the call. `TableSignature` = `DSDT`:

| Comment | Count | Find | Replace |
|---|---|---|---|
| RP25.AWAK to LPCB.AWAK | 1 | `2F035F53425F5043303052503235141F4157414B` | `2F035F53425F504330304C504342141F4157414B` |
| _WAK: call RP25.AWAK to LPCB.AWAK | 2 | `5C2F045F53425F50433030525032354157414B` | `5C2F045F53425F504330304C5043424157414B` |

- `2F 03` = `MultiNamePrefix` with 3 segments (`_SB_` `PC00` `RP25`); `14 1F` = `MethodOp` + `AWAK`'s `PkgLength`.
- The 2nd one matches twice: the call in `\_WAK` and `External (\_SB.PC00.RP25.AWAK)` (inside `If (Zero)`, ignored).
- Same length (`RP25` → `LPCB`): no `PkgLength` changes; OpenCore recomputes the checksum.
- Runtime effect: `AWAK` only does anything with `UHCS == 1` (USB4/ASM4242 enabled by the BIOS). On the Z790-E, 3202
  leaves `UHCS = 0`; even with 1 the method is still called by `_WAK`, just from another scope.
- On BIOSes without the block (up to 1801) neither patch matches, so the same EFI works before and after updating.
- Tested with `acpiexec` (patched DSDT loads, `\_SB.PC00.LPCB.AWAK` exists, `_WAK` calls it) and on real hardware.

### If the checker says "different length"

Another board/BIOS may have the same block with a different-sized `AWAK`; then the byte after `14` changes.
Run `iasl -d DSDT.aml`, confirm the block above, and adjust Find/Replace 1 changing only that byte (in both).
Patch 2 does not depend on it.

---

## How to apply

> **Back up** your EFI first (copy the whole `EFI` folder somewhere else).

**ProperTree (recommended):**
1. Open your `EFI/OC/config.plist` and, in another window, [`patch/RP25-AWAK.plist`](patch/RP25-AWAK.plist).
2. In the patch file, expand `ACPI > Patch`, select items `0` and `1` and copy (Ctrl/Cmd+C).
3. In your config, select `ACPI > Patch` and paste (Ctrl/Cmd+V). Both items are appended to the list.
4. Save. Reboot and pick macOS.

**OCAT (OpenCore Auxiliary Tools):** `ACPI` tab → `Patch` → add two rows with the values above
(`TableSignature` = `DSDT`, `Enabled` checked).

**Text editor:** copy both `<dict>…</dict>` blocks from the patch file into `<key>Patch</key><array>` in your
`config.plist`.

**To undo:** untick `Enabled` on both entries (or delete them).

---

## Check whether your BIOS needs it

**Windows** (boot **without** OpenCore: F8 on the ASUS screen → *Windows Boot Manager*):
```powershell
powershell -ExecutionPolicy Bypass -File verificar\verificar-rp25.ps1
```

**Any OS, with a `DSDT.aml`** (Linux: `sudo cat /sys/firmware/acpi/tables/DSDT > DSDT.aml`;
OpenCore DEBUG: `SysReport/ACPI/DSDT.aml`):
```bash
python3 verificar/verificar_rp25.py DSDT.aml
```

| Answer | What to do |
|---|---|
| `NEEDS the patch, and it matches exactly` | Apply `patch/RP25-AWAK.plist` |
| `No RP25.AWAK block` | This patch is not for your BIOS (your problem is something else) |
| `Same block with a different length` | Adapt Find 1 (technical section) |
| `Already patched` / `booted through OpenCore` | Dump the DSDT without going through OpenCore |

---

## Why updating the BIOS is worth it

**Plain language:** Intel 13th and 14th-gen CPUs (i5/i7/i9 13xxx and 14xxx) had a flaw: in some situations they
requested too much voltage, which **wears the processor out permanently**. Over time you get random crashes and
errors, and it can't be repaired afterwards. Intel fixed it with "microcode" updates, which **only arrive through the
BIOS**. 1801 predates all of those fixes.

**Technical:**

| | BIOS 1801 (Z790-E) | BIOS 3202 (Z790-E) |
|---|---|---|
| i7-14700K microcode (CPUID `0xB0671`) | `0x11F` | **`0x133`** (confirmed in macOS: `sysctl machdep.cpu.microcode_version`) |
| Intel "Vmin Shift Instability" fixes | none | all up to `0x133` (series including `0x125`, `0x129`, `0x12B`, `0x12F`) |
| Intel ME | old | 16.1.40 |
| ASUS/Intel 2024–2025 security fixes | no | yes |

- The main gain is **protecting the CPU** (degradation is irreversible).
- Intel's recommended power/voltage limits may slightly reduce peak performance.
- After the ME update, going back to a very old BIOS requires USB BIOS Flashback.

---

## Tested on

| Board | BIOS | CPU | macOS | OpenCore | Result |
|---|---|---|---|---|---|
| ROG STRIX Z790-E GAMING WIFI | 3202 | i7-14700K | 26 (Tahoe) | 1.0.7 | ✅ boots (used to hang) |
| ROG STRIX Z790-E GAMING WIFI | 1801 | i7-14700K | 26 (Tahoe) | 1.0.7 | ✅ patches don't match (checked on the official DSDT) |

Analysis of the official Z790-E DSDTs shows the block in **every** BIOS from 1904 to 3202. Other ASUS boards with the
same USB4 code (ASMedia ASM4242) may be affected too: run the checker. Worked for you? Open an issue with your board,
BIOS and result.

## FAQ

- **Do I need the `UHCS` patch?** No. It only disables the new USB4 block when the BIOS enables it (`UHCS = 1`); on the
  Z790-E, 3202 already leaves it at 0. The hang is caused by `RP25.AWAK`.
- **Does it change sleep?** `AWAK` is still called on wake, just from `LPCB`. It only acts with `UHCS = 1`.
- **Why doesn't OpenCore DEBUG show the error?** It happens in the macOS kernel, after OpenCore has exited. Use `-v`
  and record the screen.

## Credits and the other fix (CorpNewt)

The same diagnosis had already been made in **November 2024** by **CorpNewt** (author of SSDTTime) in
[corpnewt/SSDTTime#73](https://github.com/corpnewt/SSDTTime/issues/73), for the same board on BIOS 2703. We reached it
independently (and only found the issue afterwards) — full credit to him.

His fix attacks the other side: instead of moving `AWAK`, it turns the `If (LPEN == Zero)` that hides `Device (RP25)`
into `Noop`s, so `RP25` exists at load time. A single patch (no table filter):

| Comment | Count | Find | Replace |
|---|---|---|---|
| \_SB.PC00.RP25 NoOp to force-enable | 0 | `43A02F934C50454E00` | `43A3A3A3A3A3A3A3A3` |

| | This repository (`RP25.AWAK` → `LPCB`) | CorpNewt (`Noop` the `If`) |
|---|---|---|
| Patches | 2 | 1 |
| What changes | only where `AWAK` lives (and the `_WAK` call) | `RP25` is always created, even if `LPEN ≠ 0` |
| On BIOS 1801 | no match, nothing changes | matches (the `If` exists there too) |
| On Z790-E 3202 | matches (1 and 2) | matches (1) |

Both work; use **one** of them, not both.

## License

MIT. No warranty: back up your EFI. ASUS/Intel/Apple names belong to their owners.
