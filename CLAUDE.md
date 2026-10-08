# goodix-55a4-fedora

Fazer o leitor de digitais Goodix **27c6:55a4** (ThinkPad E14 Gen 1, machine type 20RA)
funcionar no **Fedora**, e devolver o resultado pra comunidade (COPR + patches upstream +
guia em português).

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
  - `jith/goodix-55a4-fingerprint` — patches 0001..0011 em cima do fork acima, feitos pro
    20RA, testados em set/2026 no CachyOS com firmware **`GF32xx_RTSEC_APP_10062`** (firmware
    universal Lenovo, extraído do driver Windows `r16gf09w`). Patch 0010 é o fluxo de captura
    reverse-engineered do `Wbdi.dll`. Só o caminho 10041 → 10062 foi testado por ele.
  - AUR `libfprint-goodixtls-55x4` e COPR `d-k-bo/libfprint-goodixtls` (só 5110/55b4).
- Esta máquina: Fedora KDE Plasma, **sem Windows, sem dual boot**. O irmão do Luiz tem a
  mesma máquina com Windows — disponível pra capturas USB do lado Windows (Fase 3), com
  autorização dele e sem alterar nada lá.

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
