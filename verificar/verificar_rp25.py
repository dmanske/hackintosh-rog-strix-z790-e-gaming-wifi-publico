#!/usr/bin/env python3
"""Diz se uma DSDT precisa do patch RP25.AWAK (BIOS ASUS 1904+ no macOS).
Tells whether a DSDT needs the RP25.AWAK patch. / Dice si una DSDT necesita el parche RP25.AWAK.

Uso / Usage / Uso:  python3 verificar_rp25.py DSDT.aml
De onde tirar a DSDT / Where to get the DSDT / De donde sacar la DSDT:
  - Windows: verificar-rp25.ps1 (lê do registro / reads it from the registry / la lee del registro)
  - Linux:   sudo cat /sys/firmware/acpi/tables/DSDT > DSDT.aml
  - OpenCore DEBUG + Misc > Debug > SysReport: SysReport/ACPI/DSDT.aml
"""
import re
import sys

FIND_SCOPE = bytes.fromhex('2F035F53425F5043303052503235141F4157414B')  # Scope(\_SB.PC00.RP25){Method(AWAK..
FIND_CALL = bytes.fromhex('5C2F045F53425F50433030525032354157414B')     # \_SB.PC00.RP25.AWAK
JA_CORRIGIDO = bytes.fromhex('2F035F53425F504330304C504342141F4157414B')  # mesmo bloco ja em LPCB
VARIANTE = re.compile(rb'\x2f\x03_SB_PC00RP25\x14[\x00-\xff]{1,3}AWAK')  # mesmo bloco, outro tamanho


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    d = open(sys.argv[1], 'rb').read()
    if d[:4] != b'DSDT':
        print('!! O arquivo não é uma DSDT / not a DSDT / no es una DSDT')
        return 2
    oem = d[10:16].decode('latin1').strip('\0 ')
    print(f'DSDT {len(d)} bytes, OEM "{oem}"')
    scope, call = d.count(FIND_SCOPE), d.count(FIND_CALL)
    print(f'  Find 1 (Scope RP25 + AWAK): {scope}   Find 2 (chamada/call/llamada RP25.AWAK): {call}')

    if d.count(JA_CORRIGIDO):
        print('== Esta DSDT já está corrigida (veio do OpenCore com o patch?).')
        print('== Already patched (dumped from OpenCore with the patch applied?).')
        print('== Ya está corregida (¿extraída desde OpenCore con el parche?).')
        return 0
    if scope == 1 and call >= 1:
        print('>> PRECISA do patch, e ele casa exatamente. Use patch/RP25-AWAK.plist.')
        print('>> NEEDS the patch, and it matches exactly. Use patch/RP25-AWAK.plist.')
        print('>> NECESITA el parche, y coincide exactamente. Usa patch/RP25-AWAK.plist.')
        return 0
    if VARIANTE.search(d):
        print('?? Tem o mesmo bloco, mas com outro tamanho: o Find 1 precisa ser ajustado (ver README, seção técnica).')
        print('?? Same block with a different length: Find 1 must be adapted (see README, technical section).')
        print('?? Mismo bloque con otro tamaño: hay que ajustar el Find 1 (ver README, sección técnica).')
        return 1
    print('OK Não tem o bloco RP25.AWAK: este patch não é para a sua BIOS.')
    print('OK No RP25.AWAK block: this patch is not for your BIOS.')
    print('OK No tiene el bloque RP25.AWAK: este parche no es para tu BIOS.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
