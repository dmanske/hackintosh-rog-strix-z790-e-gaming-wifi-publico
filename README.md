# ASUS Z790 + macOS: BIOS 1904 ou mais nova trava o Hackintosh — correção `RP25.AWAK`

🇧🇷 **Português** · [🇺🇸 English](README.en.md) · [🇪🇸 Español](README.es.md)

Dois patches de ACPI para o **OpenCore** que fazem o macOS voltar a iniciar nas BIOS da ASUS **da 1904 em diante**
(testado na **ROG STRIX Z790-E GAMING WIFI, BIOS 3202**, a mais nova). Sem eles, o Hackintosh só funciona até a
BIOS 1801 (dez/2023), que não tem as correções da Intel contra a degradação dos processadores de 13ª/14ª geração.

**É só um arquivo:** [`patch/RP25-AWAK.plist`](patch/RP25-AWAK.plist). Você copia as duas entradas dele para o
`ACPI > Patch` do seu `config.plist`. Nada mais muda na EFI.

---

## Você tem este problema?

- Placa **ASUS** série 700 (Z790), com a BIOS **1904 ou mais nova** (até a 1801, funciona).
- O macOS trava no começo do boot. Com `-v` (modo texto), ele para logo depois de `adding acpi-wake-type property`.
- **O sinal certeiro** aparece logo depois da lista de tabelas `ACPI: ...` (passa rápido, então filme em câmera lenta):
  ```
  ACPI Error: [\_SB_.PC00.RP25] Namespace lookup failure, AE_NOT_FOUND (20160930/dswload-292)
  ACPI Exception: AE_NOT_FOUND, (DSDT) table load failed (20160930/tbxfload-209)
  ...
  ACPI Error: 8 table load failures, 13 successful
  ```
  Depois vem uma enxurrada de `Namespace lookup failure` e `Invalid handle ... (Not a Descriptor)`.
- O Windows funciona normalmente na mesma BIOS.

**Não tem certeza?** Rode o verificador (seção [Verificar](#verificar-se-a-sua-bios-precisa)). Ele lê a tabela da
sua BIOS e diz se precisa ou não.

---

## Explicação para leigos

A BIOS entrega ao sistema operacional uma espécie de "mapa" do hardware, chamado **DSDT**. A partir da versão 1904, a
ASUS colocou nesse mapa uma linha que diz: "dentro da peça **RP25**, acrescente a função **AWAK**". O problema é que
a peça RP25 só é criada **depois**, mais adiante no mesmo mapa.

- O **Windows** lê o mapa com tolerância: vê o erro, pula a linha e segue.
- O **macOS** usa um leitor desse mapa de **2016**, bem mais rígido: ao achar o erro, ele **joga o mapa inteiro fora**.
  Sem o mapa, o Mac não encontra quase nada do hardware (processador, USB, vídeo…) e trava.

O patch troca o endereço dessa linha: em vez de "dentro da RP25", ela passa a dizer "dentro da **LPCB**", uma peça que
já existe naquele momento. A função continua lá (e continua sendo chamada quando o PC acorda do repouso), mas o
leitor do macOS não tropeça mais. **Nada é gravado na BIOS**: o OpenCore só corrige o que o macOS recebe, toda vez que
liga. Se tirar o patch, tudo volta a ser como antes.

---

## Explicação técnica

A partir da 1904, a DSDT (OEM `ALASKA` / `A M I`) contém, **no nível da tabela** (fora de `If`/`Method`):

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

e o `\_WAK` passou a chamar `\_SB.PC00.RP25.AWAK (Arg0)`. Porém o `Device (RP25)` só é declarado **dentro** de
`If (LPEN == Zero)` (em `\_SB.PC00`) e de `If (PCHS == 0x04)` (em `\_SB.PC00.VMD0`).

O AppleACPIPlatform embute o **ACPICA 20160930**. Nessa versão:
1. o *module-level code* (os `If` fora de métodos) só é executado **depois** do carregamento da tabela, então no
   momento do `Scope` o `RP25` ainda não existe → `AE_NOT_FOUND` em `dswload`;
2. **qualquer erro durante o carregamento rejeita a tabela inteira**. Isso só mudou no ACPICA 20180531/20180810
   (*"continue loading ACPI tables regardless of malformed AML"*).

Resultado: a DSDT é descartada, e com ela caem as SSDT que dependem dela (`CpuSsdt`, `SaSsdt`, `IgfxSsdt`, `xh_*`,
`SSDT-EC`, `SSDT-HPET`…). O Windows e o ACPICA atual (`acpiexec` 2024) carregam a mesma DSDT sem erro. Até a 1801, o
único `Scope (_SB.PC00.RP25)` da DSDT ficava **dentro** de `If (PCHS == 0x04)`, por isso funcionava.

### O patch

Renomeia o alvo para `\_SB.PC00.LPCB` (declarado fora de `If`, existe desde o carregamento e não tem `AWAK`), na
definição e na chamada. `TableSignature` = `DSDT`:

| Comment | Count | Find | Replace |
|---|---|---|---|
| RP25.AWAK to LPCB.AWAK | 1 | `2F035F53425F5043303052503235141F4157414B` | `2F035F53425F504330304C504342141F4157414B` |
| _WAK: call RP25.AWAK to LPCB.AWAK | 2 | `5C2F045F53425F50433030525032354157414B` | `5C2F045F53425F504330304C5043424157414B` |

- `2F 03` = `MultiNamePrefix` com 3 segmentos (`_SB_` `PC00` `RP25`); `14 1F` = `MethodOp` + `PkgLength` do `AWAK`.
- O 2º casa 2 vezes: a chamada no `\_WAK` e o `External (\_SB.PC00.RP25.AWAK)` (dentro de `If (Zero)`, ignorado).
- Mesmo tamanho (`RP25` → `LPCB`): nenhum `PkgLength` muda; o OpenCore recalcula o checksum.
- Efeito em funcionamento: o `AWAK` só faz algo com `UHCS == 1` (USB4/ASM4242 ligado pela BIOS). Na Z790-E a 3202
  deixa `UHCS = 0`; mesmo com 1, o método continua sendo chamado pelo `_WAK`, só que em outro escopo.
- Em BIOS sem o bloco (até a 1801) os dois patches não casam e não fazem nada: a mesma EFI serve antes e depois.
- Testado com `acpiexec` (DSDT corrigida carrega, `\_SB.PC00.LPCB.AWAK` existe, o `_WAK` o chama) e no boot real.

### Se o verificador disser "outro tamanho"

Outra placa ou BIOS pode ter o mesmo bloco com um `AWAK` de tamanho diferente. Nesse caso, o byte depois de `14`
muda. Faça `iasl -d DSDT.aml`, confira o bloco acima e ajuste o `Find`/`Replace` 1 trocando só esse byte (nos dois).
O patch 2 não depende disso.

---

## Como aplicar

> Faça **backup** da sua EFI antes (copie a pasta `EFI` inteira para outro lugar).

**ProperTree (recomendado):**
1. Abra o seu `EFI/OC/config.plist` e, em outra janela, o [`patch/RP25-AWAK.plist`](patch/RP25-AWAK.plist).
2. No arquivo do patch, abra `ACPI > Patch`, selecione os itens `0` e `1` e copie (Ctrl/Cmd+C).
3. No seu config, selecione `ACPI > Patch` e cole (Ctrl/Cmd+V). Os dois itens entram no fim da lista.
4. Salve. Reinicie e escolha o macOS.

**OCAT (OpenCore Auxiliary Tools):** aba `ACPI` → `Patch` → adicione duas linhas com os valores da tabela acima
(`TableSignature` = `DSDT`, `Enabled` marcado).

**Editor de texto:** copie os dois blocos `<dict>…</dict>` do arquivo do patch para dentro de `<key>Patch</key><array>`
no seu `config.plist`.

**Para desfazer:** desmarque `Enabled` nas duas entradas (ou apague-as).

---

## Verificar se a sua BIOS precisa

**Windows** (inicie **sem** o OpenCore: F8 na tela da ASUS → *Windows Boot Manager*):
```powershell
powershell -ExecutionPolicy Bypass -File verificar\verificar-rp25.ps1
```

**Qualquer sistema, com um `DSDT.aml`** (Linux: `sudo cat /sys/firmware/acpi/tables/DSDT > DSDT.aml`;
OpenCore DEBUG: `SysReport/ACPI/DSDT.aml`):
```bash
python3 verificar/verificar_rp25.py DSDT.aml
```

| Resposta | O que fazer |
|---|---|
| `PRECISA do patch, e ele casa exatamente` | Aplique o `patch/RP25-AWAK.plist` |
| `Não tem o bloco RP25.AWAK` | Este patch não é para a sua BIOS (o seu problema é outro) |
| `mesmo bloco com outro tamanho` | Ajuste o Find 1 (seção técnica) |
| `já está corrigida` / `iniciado pelo OpenCore` | Tire a DSDT sem passar pelo OpenCore |

---

## Por que vale a pena atualizar a BIOS

**Para leigos:** os Intel de 13ª e 14ª geração (i5/i7/i9 13xxx e 14xxx) tinham um defeito: em certas situações
pediam voltagem alta demais, o que **desgasta o processador para sempre**. Com o tempo vêm travamentos e erros
aleatórios, e não tem conserto depois. A Intel corrigiu isso com atualizações de "microcode", que **só chegam pela
BIOS**. A 1801 é anterior a todas essas correções.

**Técnico:**

| | BIOS 1801 (Z790-E) | BIOS 3202 (Z790-E) |
|---|---|---|
| Microcode i7-14700K (CPUID `0xB0671`) | `0x11F` | **`0x133`** (confirmado no macOS: `sysctl machdep.cpu.microcode_version`) |
| Correções "Vmin Shift Instability" da Intel | nenhuma | todas até o `0x133` (série que inclui `0x125`, `0x129`, `0x12B`, `0x12F`) |
| Intel ME | antigo | 16.1.40 |
| Correções de segurança ASUS/Intel 2024–2025 | não | sim |

- O ganho principal é **proteger o processador** (a degradação é irreversível).
- Os limites de energia/voltagem recomendados pela Intel podem reduzir um pouco o desempenho de pico.
- Depois de atualizar o ME, voltar a uma BIOS muito antiga exige o USB BIOS Flashback.

---

## Testado em

| Placa | BIOS | CPU | macOS | OpenCore | Resultado |
|---|---|---|---|---|---|
| ROG STRIX Z790-E GAMING WIFI | 3202 | i7-14700K | 26 (Tahoe) | 1.0.7 | ✅ inicia (antes travava) |
| ROG STRIX Z790-E GAMING WIFI | 1801 | i7-14700K | 26 (Tahoe) | 1.0.7 | ✅ os patches não casam (conferido na DSDT oficial) |

Pela análise das DSDT oficiais da Z790-E, o bloco existe em **todas** as BIOS da 1904 à 3202. Outras placas ASUS
com o mesmo código de USB4 (ASMedia ASM4242) podem ter o mesmo problema: rode o verificador.
Funcionou na sua? Abra uma *issue* com placa, BIOS e resultado.

## Perguntas

- **Preciso do patch `UHCS`?** Não. Ele só desliga o bloco USB4 novo quando a BIOS liga (`UHCS = 1`); na Z790-E a
  3202 já deixa 0. A causa do travamento é o `RP25.AWAK`.
- **Muda algo no repouso?** O `AWAK` continua sendo chamado ao acordar, só que em `LPCB`. Ele só age com `UHCS = 1`.
- **Por que o OpenCore de debug não mostra o erro?** Ele acontece no kernel do macOS, depois que o OpenCore já saiu.
  Use `-v` e filme.

## Créditos e a outra solução (CorpNewt)

O mesmo diagnóstico já tinha sido feito em **novembro de 2024** pelo **CorpNewt** (autor do SSDTTime), na issue
[corpnewt/SSDTTime#73](https://github.com/corpnewt/SSDTTime/issues/73), para a mesma placa na BIOS 2703. Chegamos
nele de forma independente (só achamos a issue depois) — fica aqui o crédito.

A correção dele ataca o outro lado: em vez de mudar o `AWAK` de lugar, ela transforma em `Noop` o `If (LPEN == Zero)`
que esconde o `Device (RP25)`, para o `RP25` existir desde o carregamento. Um patch só (`TableSignature` livre):

| Comment | Count | Find | Replace |
|---|---|---|---|
| \_SB.PC00.RP25 NoOp to force-enable | 0 | `43A02F934C50454E00` | `43A3A3A3A3A3A3A3A3` |

| | Este repositório (`RP25.AWAK` → `LPCB`) | CorpNewt (`Noop` no `If`) |
|---|---|---|
| Patches | 2 | 1 |
| O que muda | só o endereço do `AWAK` (e a chamada no `_WAK`) | o `RP25` passa a ser criado sempre, mesmo se `LPEN ≠ 0` |
| Na BIOS 1801 | não casa, nada muda | casa (o `If` também existe lá) |
| Na 3202 da Z790-E | casa (1 e 2) | casa (1) |

As duas funcionam; use **uma** delas, não as duas juntas.

## Licença

MIT. Sem garantia: faça backup da EFI. Os nomes ASUS/Intel/Apple pertencem aos seus donos.
