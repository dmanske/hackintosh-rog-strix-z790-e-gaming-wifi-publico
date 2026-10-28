# Diz se a DSDT da sua BIOS precisa do patch RP25.AWAK (BIOS ASUS 1904+ no macOS).
# Tells whether your BIOS DSDT needs the RP25.AWAK patch. / Dice si la DSDT de tu BIOS necesita el parche RP25.AWAK.
#
# Uso / Usage / Uso (PowerShell, no Windows iniciado SEM o OpenCore / Windows booted WITHOUT OpenCore / Windows
# iniciado SIN OpenCore — F8 > Windows Boot Manager):
#   powershell -ExecutionPolicy Bypass -File verificar-rp25.ps1
# A DSDT vem do registro (HKLM\HARDWARE\ACPI\DSDT) e é salva como DSDT.aml na pasta atual.
param([string]$Saida = (Get-Location).Path)
$ErrorActionPreference = 'Stop'

$chave = Get-ChildItem 'HKLM:\HARDWARE\ACPI\DSDT' -Recurse |
    Where-Object { $_.GetValueNames() -contains '00000000' } | Select-Object -First 1
if (-not $chave) { throw 'DSDT não encontrada no registro / not found in the registry / no encontrada en el registro' }
[byte[]]$dsdt = $chave.GetValue('00000000')
$arquivo = Join-Path $Saida 'DSDT.aml'
[IO.File]::WriteAllBytes($arquivo, $dsdt)

# BitConverter gera "AA-BB-CC": o casamento é sempre alinhado ao byte
$hex = [BitConverter]::ToString($dsdt)
function Conta([string]$h) {
    $p = (($h -split '(..)') | Where-Object { $_ }) -join '-'
    [regex]::Matches($hex, [regex]::Escape($p)).Count
}

$bios = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS')
$scope = Conta '2F035F53425F5043303052503235141F4157414B'
$call = Conta '5C2F045F53425F50433030525032354157414B'
$fixed = Conta '2F035F53425F504330304C504342141F4157414B'
$xprw = Conta '58505257'
$variante = [regex]::Matches($hex, '2F-03-5F-53-42-5F-50-43-30-30-52-50-32-35-14-(..-){1,3}41-57-41-4B').Count

"Placa / Board: $($bios.BaseBoardManufacturer) $($bios.BaseBoardProduct) | BIOS $($bios.BIOSVersion)"
"DSDT: $($dsdt.Length) bytes -> $arquivo"
"Find 1 (Scope RP25 + AWAK): $scope   Find 2 (RP25.AWAK): $call"

if ($xprw -gt 0 -or $fixed -gt 0) {
    '!! Este Windows foi iniciado pelo OpenCore (a DSDT já vem com patches). Reinicie com F8 > Windows Boot Manager.'
    '!! Windows was booted through OpenCore (DSDT already patched). Reboot with F8 > Windows Boot Manager.'
    '!! Windows se inició con OpenCore (la DSDT ya viene parcheada). Reinicia con F8 > Windows Boot Manager.'
} elseif ($scope -eq 1 -and $call -ge 1) {
    '>> PRECISA do patch, e ele casa exatamente. Use patch/RP25-AWAK.plist.'
    '>> NEEDS the patch, and it matches exactly. Use patch/RP25-AWAK.plist.'
    '>> NECESITA el parche, y coincide exactamente. Usa patch/RP25-AWAK.plist.'
} elseif ($variante -gt 0) {
    '?? Tem o mesmo bloco com outro tamanho: o Find 1 precisa ser ajustado (README, seção técnica).'
    '?? Same block with a different length: Find 1 must be adapted (README, technical section).'
    '?? Mismo bloque con otro tamaño: hay que ajustar el Find 1 (README, sección técnica).'
} else {
    'OK Não tem o bloco RP25.AWAK: este patch não é para a sua BIOS.'
    'OK No RP25.AWAK block: this patch is not for your BIOS.'
    'OK No tiene el bloque RP25.AWAK: este parche no es para tu BIOS.'
}
