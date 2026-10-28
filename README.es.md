# ASUS Z790 + macOS: la BIOS 1904 o más nueva cuelga el Hackintosh — corrección `RP25.AWAK`

[🇧🇷 Português](README.md) · [🇺🇸 English](README.en.md) · 🇪🇸 **Español**

Dos parches de ACPI para **OpenCore** que hacen que macOS vuelva a arrancar en las BIOS de ASUS **de la 1904 en
adelante** (probado en la **ROG STRIX Z790-E GAMING WIFI, BIOS 3202**, la más reciente). Sin ellos, el Hackintosh solo
funciona hasta la BIOS 1801 (dic/2023), que no tiene las correcciones de Intel contra la degradación de los
procesadores de 13.ª/14.ª generación.

**Es un solo archivo:** [`patch/RP25-AWAK.plist`](patch/RP25-AWAK.plist). Copias sus dos entradas en
`ACPI > Patch` de tu `config.plist`. Nada más cambia en la EFI.

---

## ¿Tienes este problema?

- Placa **ASUS** serie 700 (Z790) con BIOS **1904 o más nueva** (hasta la 1801 funciona).
- macOS se cuelga al principio del arranque. Con `-v` (modo texto) se detiene justo después de
  `adding acpi-wake-type property`.
- **La señal inequívoca** aparece justo después de la lista de tablas `ACPI: ...` (pasa rápido: grábalo en cámara lenta):
  ```
  ACPI Error: [\_SB_.PC00.RP25] Namespace lookup failure, AE_NOT_FOUND (20160930/dswload-292)
  ACPI Exception: AE_NOT_FOUND, (DSDT) table load failed (20160930/tbxfload-209)
  ...
  ACPI Error: 8 table load failures, 13 successful
  ```
  seguida de una avalancha de `Namespace lookup failure` e `Invalid handle ... (Not a Descriptor)`.
- Windows funciona normalmente con la misma BIOS.

**¿No estás seguro?** Ejecuta el verificador ([Verificar](#verificar-si-tu-bios-lo-necesita)). Lee la tabla de tu BIOS
y te lo dice.

---

## Explicación sencilla

La BIOS le entrega al sistema operativo una especie de "mapa" del hardware llamado **DSDT**. A partir de la versión
1904, ASUS puso en ese mapa una línea que dice "dentro de la pieza **RP25**, agrega la función **AWAK**". El problema:
la pieza RP25 recién se crea **después**, más adelante en el mismo mapa.

- **Windows** lee el mapa con tolerancia: ve el error, salta esa línea y sigue.
- **macOS** usa un lector de ese mapa de **2016**, mucho más estricto: al encontrar el error, **descarta el mapa
  entero**. Sin el mapa, el Mac no encuentra casi nada del hardware (procesador, USB, video…) y se cuelga.

El parche cambia la dirección de esa línea: en lugar de "dentro de RP25" dice "dentro de **LPCB**", una pieza que ya
existe en ese momento. La función sigue ahí (y se sigue llamando cuando el PC despierta del reposo), pero el lector
de macOS ya no tropieza. **No se graba nada en la BIOS**: OpenCore solo corrige lo que recibe macOS, en cada arranque.
Si quitas el parche, todo vuelve a ser como antes.

---

## Explicación técnica

Desde la 1904, la DSDT (OEM `ALASKA` / `A M I`) contiene, **a nivel de tabla** (fuera de `If`/`Method`):

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

y `\_WAK` pasó a llamar a `\_SB.PC00.RP25.AWAK (Arg0)`. Pero el `Device (RP25)` solo se declara **dentro** de
`If (LPEN == Zero)` (en `\_SB.PC00`) y de `If (PCHS == 0x04)` (en `\_SB.PC00.VMD0`).

AppleACPIPlatform incluye **ACPICA 20160930**. En esa versión:
1. el *module-level code* (los `If` fuera de métodos) solo se ejecuta **después** de cargar la tabla, así que cuando se
   procesa el `Scope`, `RP25` todavía no existe → `AE_NOT_FOUND` en `dswload`;
2. **cualquier error durante la carga rechaza la tabla entera**. Eso recién cambió en ACPICA 20180531/20180810
   (*"continue loading ACPI tables regardless of malformed AML"*).

Resultado: la DSDT se descarta y con ella caen las SSDT que dependen de ella (`CpuSsdt`, `SaSsdt`, `IgfxSsdt`, `xh_*`,
`SSDT-EC`, `SSDT-HPET`…). Windows y el ACPICA actual (`acpiexec` 2024) cargan la misma DSDT sin errores. Hasta la 1801,
el único `Scope (_SB.PC00.RP25)` de la DSDT estaba **dentro** de `If (PCHS == 0x04)`, por eso funcionaba.

### El parche

Cambia el destino a `\_SB.PC00.LPCB` (declarado fuera de `If`, existe desde la carga y no tiene `AWAK`), en la
definición y en la llamada. `TableSignature` = `DSDT`:

| Comment | Count | Find | Replace |
|---|---|---|---|
| RP25.AWAK to LPCB.AWAK | 1 | `2F035F53425F5043303052503235141F4157414B` | `2F035F53425F504330304C504342141F4157414B` |
| _WAK: call RP25.AWAK to LPCB.AWAK | 2 | `5C2F045F53425F50433030525032354157414B` | `5C2F045F53425F504330304C5043424157414B` |

- `2F 03` = `MultiNamePrefix` con 3 segmentos (`_SB_` `PC00` `RP25`); `14 1F` = `MethodOp` + `PkgLength` de `AWAK`.
- El 2.º coincide 2 veces: la llamada en `\_WAK` y el `External (\_SB.PC00.RP25.AWAK)` (dentro de `If (Zero)`, ignorado).
- Mismo tamaño (`RP25` → `LPCB`): ningún `PkgLength` cambia; OpenCore recalcula el checksum.
- Efecto en funcionamiento: `AWAK` solo hace algo con `UHCS == 1` (USB4/ASM4242 activado por la BIOS). En la Z790-E la
  3202 deja `UHCS = 0`; aun con 1, `_WAK` sigue llamando al método, solo que desde otro ámbito.
- En BIOS sin el bloque (hasta la 1801) ninguno de los dos coincide: la misma EFI sirve antes y después de actualizar.
- Probado con `acpiexec` (la DSDT corregida carga, `\_SB.PC00.LPCB.AWAK` existe, `_WAK` lo llama) y en el equipo real.

### Si el verificador dice "otro tamaño"

Otra placa o BIOS puede tener el mismo bloque con un `AWAK` de distinto tamaño; entonces cambia el byte después de
`14`. Ejecuta `iasl -d DSDT.aml`, confirma el bloque de arriba y ajusta el Find/Replace 1 cambiando solo ese byte (en
los dos). El parche 2 no depende de eso.

---

## Cómo aplicarlo

> Haz una **copia de seguridad** de tu EFI antes (copia toda la carpeta `EFI` a otro lugar).

**ProperTree (recomendado):**
1. Abre tu `EFI/OC/config.plist` y, en otra ventana, [`patch/RP25-AWAK.plist`](patch/RP25-AWAK.plist).
2. En el archivo del parche, expande `ACPI > Patch`, selecciona los ítems `0` y `1` y copia (Ctrl/Cmd+C).
3. En tu config, selecciona `ACPI > Patch` y pega (Ctrl/Cmd+V). Los dos ítems se agregan al final de la lista.
4. Guarda. Reinicia y elige macOS.

**OCAT (OpenCore Auxiliary Tools):** pestaña `ACPI` → `Patch` → agrega dos filas con los valores de la tabla
(`TableSignature` = `DSDT`, `Enabled` marcado).

**Editor de texto:** copia los dos bloques `<dict>…</dict>` del archivo del parche dentro de
`<key>Patch</key><array>` en tu `config.plist`.

**Para deshacer:** desmarca `Enabled` en las dos entradas (o bórralas).

---

## Verificar si tu BIOS lo necesita

**Windows** (arranca **sin** OpenCore: F8 en la pantalla de ASUS → *Windows Boot Manager*):
```powershell
powershell -ExecutionPolicy Bypass -File verificar\verificar-rp25.ps1
```

**Cualquier sistema, con un `DSDT.aml`** (Linux: `sudo cat /sys/firmware/acpi/tables/DSDT > DSDT.aml`;
OpenCore DEBUG: `SysReport/ACPI/DSDT.aml`):
```bash
python3 verificar/verificar_rp25.py DSDT.aml
```

| Respuesta | Qué hacer |
|---|---|
| `NECESITA el parche, y coincide exactamente` | Aplica `patch/RP25-AWAK.plist` |
| `No tiene el bloque RP25.AWAK` | Este parche no es para tu BIOS (tu problema es otro) |
| `Mismo bloque con otro tamaño` | Ajusta el Find 1 (sección técnica) |
| `Ya está corregida` / `se inició con OpenCore` | Extrae la DSDT sin pasar por OpenCore |

---

## Por qué vale la pena actualizar la BIOS

**En sencillo:** los Intel de 13.ª y 14.ª generación (i5/i7/i9 13xxx y 14xxx) tenían un defecto: en ciertas
situaciones pedían demasiado voltaje, lo que **desgasta el procesador para siempre**. Con el tiempo aparecen cuelgues y
errores aleatorios, y después no tiene arreglo. Intel lo corrigió con actualizaciones de "microcode", que **solo llegan
a través de la BIOS**. La 1801 es anterior a todas esas correcciones.

**Técnico:**

| | BIOS 1801 (Z790-E) | BIOS 3202 (Z790-E) |
|---|---|---|
| Microcode i7-14700K (CPUID `0xB0671`) | `0x11F` | **`0x133`** (confirmado en macOS: `sysctl machdep.cpu.microcode_version`) |
| Correcciones "Vmin Shift Instability" de Intel | ninguna | todas hasta `0x133` (serie que incluye `0x125`, `0x129`, `0x12B`, `0x12F`) |
| Intel ME | antiguo | 16.1.40 |
| Correcciones de seguridad ASUS/Intel 2024–2025 | no | sí |

- La ganancia principal es **proteger el procesador** (la degradación es irreversible).
- Los límites de energía/voltaje recomendados por Intel pueden reducir un poco el rendimiento máximo.
- Después de actualizar el ME, volver a una BIOS muy antigua requiere USB BIOS Flashback.

---

## Probado en

| Placa | BIOS | CPU | macOS | OpenCore | Resultado |
|---|---|---|---|---|---|
| ROG STRIX Z790-E GAMING WIFI | 3202 | i7-14700K | 26 (Tahoe) | 1.0.7 | ✅ arranca (antes se colgaba) |
| ROG STRIX Z790-E GAMING WIFI | 1801 | i7-14700K | 26 (Tahoe) | 1.0.7 | ✅ los parches no coinciden (verificado en la DSDT oficial) |

El análisis de las DSDT oficiales de la Z790-E muestra el bloque en **todas** las BIOS de la 1904 a la 3202. Otras
placas ASUS con el mismo código de USB4 (ASMedia ASM4242) pueden estar afectadas: ejecuta el verificador.
¿Te funcionó? Abre un *issue* con tu placa, BIOS y resultado.

## Preguntas

- **¿Necesito el parche `UHCS`?** No. Solo desactiva el bloque USB4 nuevo cuando la BIOS lo activa (`UHCS = 1`); en la
  Z790-E la 3202 ya lo deja en 0. El cuelgue lo causa `RP25.AWAK`.
- **¿Cambia algo en el reposo?** `AWAK` se sigue llamando al despertar, solo que desde `LPCB`. Solo actúa con `UHCS = 1`.
- **¿Por qué OpenCore DEBUG no muestra el error?** Ocurre en el kernel de macOS, cuando OpenCore ya terminó. Usa `-v` y
  graba la pantalla.

## Créditos y la otra solución (CorpNewt)

El mismo diagnóstico ya lo había hecho en **noviembre de 2024** **CorpNewt** (autor de SSDTTime) en
[corpnewt/SSDTTime#73](https://github.com/corpnewt/SSDTTime/issues/73), para la misma placa con la BIOS 2703. Llegamos a
él de forma independiente (encontramos la issue después) — el crédito es suyo.

Su corrección ataca el otro lado: en lugar de mover `AWAK`, convierte en `Noop` el `If (LPEN == Zero)` que esconde el
`Device (RP25)`, para que `RP25` exista desde la carga. Un solo parche (sin filtro de tabla):

| Comment | Count | Find | Replace |
|---|---|---|---|
| \_SB.PC00.RP25 NoOp to force-enable | 0 | `43A02F934C50454E00` | `43A3A3A3A3A3A3A3A3` |

| | Este repositorio (`RP25.AWAK` → `LPCB`) | CorpNewt (`Noop` en el `If`) |
|---|---|---|
| Parches | 2 | 1 |
| Qué cambia | solo dónde vive `AWAK` (y la llamada en `_WAK`) | `RP25` se crea siempre, aunque `LPEN ≠ 0` |
| En la BIOS 1801 | no coincide, nada cambia | coincide (el `If` también existe ahí) |
| En la 3202 de la Z790-E | coincide (1 y 2) | coincide (1) |

Las dos funcionan; usa **una**, no las dos juntas.

## Licencia

MIT. Sin garantía: haz copia de seguridad de tu EFI. Los nombres ASUS/Intel/Apple pertenecen a sus dueños.
