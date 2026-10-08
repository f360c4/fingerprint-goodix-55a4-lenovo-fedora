# goodix-55a4-fedora

Fazer o leitor de digitais Goodix **27c6:55a4** (ThinkPad E14 Gen 1, machine type **20RB002BBR**;
o trabalho de referência foi feito num 20RA, mesma família) funcionar no **Fedora**, e devolver
o resultado pra comunidade (COPR + patches upstream + guia em português).

## Estado do sensor (lido em 2026-10-08, `dumps/probe-20261008-005703.json`)

- Firmware **`GF3268_RTSEC_APP_10062`** (universal Lenovo — já é o que o driver do jith exige;
  **não** é o 10039 de fábrica). Bootloader `MILAN_RTSEC_IAP_10027`.
- PSK **do Windows** (hash `4e2f7244…e10c`, ≠ PSK zero). A máquina foi comprada usada, com
  Windows, que foi removido — a PSK original é irrecuperável.
- OTP: tcode `0xd0`, FDT delta `0x17`, FDT offset 0.
- **Consequência: não há flash de firmware no plano.** A única escrita prevista é um comando
  `preset_psk_write` (Fase 4), precedente em jith/goodix-55a4-fingerprint#1 e
  TheWeirdDev/libfprint#3. Mesmo assim, exige `FLASH AUTORIZADO`.

Dono do projeto: Luiz Felipe. Linguagem das notas: português. Código e commits: inglês.

## Contexto que você precisa saber antes de qualquer coisa

- O 55a4 é um sensor Goodix **GF3208 "sensor-only"**: manda imagem crua pro host, dentro de
  uma sessão TLS-PSK. O matching é feito no host. Não existe driver upstream no libfprint.
- A PSK é gravada no chip pelo Windows no pareamento (por dispositivo, secreta). O firmware
  de fábrica é `GF3208_RTSEC_APP_10039`. O bootloader esperado é `MILAN_RTSEC_IAP_10027`.
- Trabalho comunitário existente (ler o código, não só o README):
  - `goodix-fp-linux-dev/goodix-fp-dump` — reverse engineering do protocolo; ferramenta de
    flash que grava firmware + PSK toda-zero.
  - `TheWeirdDev/libfprint`, branch `55b4-experimental` — fork do libfprint 1.94.6 com
    driver `goodixtls` e matcher SIGFM (OpenCV).
  - `jith/goodix-55a4-fingerprint` — patches **0001, 0002, 0008, 0010, 0011** (só esses) em
    cima do fork acima, feitos pro 20RA, testados em set/2026 no CachyOS com firmware
    **`GF32xx_RTSEC_APP_10062`** (firmware universal Lenovo, extraído do driver Windows
    `r16gf09w`; o `.bin` é idêntico ao do repo oficial goodix-firmware). Patch 0010 é o fluxo
    de captura reverse-engineered do `Wbdi.dll`. Só o caminho 10041 → 10062 foi testado por ele.
    Issue #1 do repo: outro 55a4 Windows-paired funcionou gravando só a PSK, sem flash.
  - `TheWeirdDev/libfprint` PR #3: mesma gravação só-PSK num 55b4; aponta bug no
    `goodix_send_preset_psk_write` e fix de cipher list `"PSK:@SECLEVEL=0"` pra OpenSSL 3
    (Fedora usa crypto-policies `@SECLEVEL=2` — provável que precisemos).
  - AUR `libfprint-goodixtls-55x4` e COPR `d-k-bo/libfprint-goodixtls` (só 5110/55b4).
- Esta máquina: Fedora KDE Plasma, **sem Windows, sem dual boot**, comprada usada. O irmão do
  Luiz tem a mesma máquina com Windows — a PSK dele é outra e não serve pra nós; capturas
  lá são opcionais (tuning), sempre com autorização dele e sem alterar nada.

## REGRAS DE SEGURANÇA (não negociáveis)

1. **NUNCA execute nada que escreva no sensor** — flash de firmware, gravação de PSK,
   entrada em modo IAP/bootloader, erase, qualquer comando de escrita do protocolo Goodix —
   sem que o usuário digite literalmente `FLASH AUTORIZADO` **na sessão atual**. Antes de
   qualquer passo desses, pare, imprima `⚠️ ESTE PASSO ESCREVE NO SENSOR`, liste exatamente
   o que será escrito, e aguarde.
2. Antes de rodar **qualquer script de terceiro** que fale com o sensor (goodix-fp-dump,
   flash-tool, run_*.py), **leia o código** e identifique cada função que escreve. Se o
   script mistura leitura e escrita, não rode o script: escreva um `tools/probe_readonly.py`
   que importe só as funções de leitura. Documente em NOTES.md quais funções são de escrita.
3. Nunca `meson install` direto em `/usr`. O libfprint patcheado entra no sistema **só como
   RPM** (`Provides: libfprint`, `Conflicts: libfprint`), com `dnf versionlock`.
4. Nunca remova o fallback de senha. PAM sempre com `sufficient`, nunca `required`.
   Não configure login gráfico (SDDM) por digital sem pedido explícito.
5. Não toque em `/boot`, kernel, BIOS, TPM, nem em nada fora do escopo do leitor.
6. Se algo der errado no meio de um passo que fala com o sensor: não reenvie comandos
   "pra ver se vai"; pare, salve logs, pergunte.
7. **Nunca rode `main()` de `driver_55x4.py`/`driver_5503.py`/`flash_55a4_universal.py`**:
   no estado atual do sensor eles gravam PSK sem perguntar, e o `driver_5503.py` upstream
   (regex `GF32[0,5]8`) **apagaria** o nosso 10062. Ferramentas de escrita são só as nossas
   (`tools/pair_psk.py`), com whitelist de opcodes.
8. **Nunca grave PSK pelo libfprint**: `goodix_send_preset_psk_write` do fork c1937b9 está
   bugada (`sizeof(payload)` de ponteiro → PSK truncada, hash errado no sensor). O driver
   instalado só pode **ler** a PSK.

## Como trabalhar

- Leia `PLAN.md` no início de toda sessão e diga em qual fase estamos.
- `NOTES.md` é a memória do projeto. Toda sessão: entrada datada com o que foi feito, o que
  foi descoberto (com evidência: caminho do log/dump), o que ficou aberto. Atualize-a
  **durante** a sessão, não só no fim.
- Saídas de comando relevantes vão pra `logs/`, dumps e capturas pra `dumps/`,
  ferramentas nossas pra `tools/`, empacotamento pra `rpm/`. Commit pequeno e frequente.
- Não chute detalhes de protocolo, firmware ou offsets. Se não está no código-fonte ou numa
  captura, é hipótese — marque como hipótese.
- Use a task list pra cada fase. Um passo de cada vez quando o passo envolve o sensor.
- Quando precisar de algo físico (pôr o dedo, plugar AC, ir na máquina do irmão), peça de
  forma explícita e espere.
- Prefira ferramentas de pesquisa em Python (goodix-fp-dump já é Python) ou Rust; o driver
  final é C dentro do libfprint, e patches devem ficar no formato `git format-patch` em
  cima do snapshot do fork, pra poderem ir upstream.
