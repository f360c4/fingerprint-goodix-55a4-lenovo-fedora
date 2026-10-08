# NOTES — goodix-55a4-fedora

Memória do projeto. Uma entrada datada por sessão. Hipóteses marcadas como **[HIPÓTESE]**.

---

## 2026-10-08 — Sessão 1: Fase 0 + Fase 1 (somente leitura)

Regra da sessão: nada que escreva no sensor. `FLASH AUTORIZADO` **não** foi dado.

### Checklist da sessão

- [x] F0: identidade da máquina
- [x] F0: `lsusb` mostra 27c6:55a4
- [x] F0: três repositórios clonados em `vendor/` (no `.gitignore`)
- [x] F0: venv Python do projeto (`.venv/`, no `.gitignore`)
- [ ] F0: pacotes de build (`dnf install`) — precisa sudo do Luiz
- [ ] F0: `sudo lsusb -v` → `logs/lsusb-v.txt` — precisa sudo
- [x] F1.1: auditoria leitura/escrita do goodix-fp-dump e do flash-tool do jith
- [ ] F1.2: `tools/probe_readonly.py` escrito e rodado → `dumps/probe-*.json`
- [ ] F1.3: captura usbmon do fprintd de estoque
- [ ] F1.4: re-enumeração após suspend

### Fase 0 — inventário

| Item | Valor |
|---|---|
| `product_name` | **`20RB002BBR`** (⚠️ não é 20RA — ver abaixo) |
| `product_version` | ThinkPad E14 |
| BIOS | `R16ET30W (1.16)`, 01/17/2021 |
| Fedora | 44 (KDE Plasma) |
| Kernel | 7.2.8-200.fc44.x86_64 |
| libfprint | 1.94.100-1.fc44 |
| fprintd / fprintd-pam | 1.94.5-5.fc44 |
| opencv | `opencv` (meta) não instalado; `opencv-core-4.13.0-1.fc44` |
| libusb1 | 1.0.30-1.fc44 |
| dnf | dnf5 5.4.6 → versionlock vem de `dnf5-plugins` (**já instalado**) |
| fprintd | `inactive` (ativado sob demanda via D-Bus) |
| Sensor | Bus 001 Device 003, porta 9, `27c6:55a4`, iface 0 vendor-specific, EP 0x01 OUT / 0x82 IN bulk 512 B, sem driver de kernel; `bcdDevice 1.00`, sem serial. Nó `/dev/bus/usb/001/003` é `root:root 0664` → acesso exige root ou regra udev |

Evidência: `logs/lsusb-v-nonroot.txt` (sem root: descritores ok, strings/status faltando).

**Modelo 20RB vs 20RA.** A máquina é **20RB**, não 20RA. 20RA e 20RB são ambos machine types
do ThinkPad E14 Gen 1 (Intel) e compartilham a família de BIOS `R16ET..` — o driver Windows
que contém o 10062 se chama `r16gf09w`, mesmo prefixo `R16`, o que sugere mesma plataforma.
**[HIPÓTESE]** a diferença 20RA/20RB é de configuração de venda (região/SKU), não de placa
ou de leitor. O que importa de fato é o sensor: mesmo VID:PID 27c6:55a4 — firmware, IAP e OTP
serão confirmados pelo probe. Até lá, "testado no 20RA" vale para nós só por analogia.

Repositórios (`vendor/`, não versionado):

| Repo | Commit | Data |
|---|---|---|
| goodix-fp-dump | `cc43bb3` | 2023-05-30 (submódulo firmware `7b9a828`) |
| jith-55a4 | `e8ee5bc` | 2026-09-17 |
| libfprint-55b4 (TheWeirdDev, `55b4-experimental`) | `c1937b9` | 2026-08-03 — bate com o snapshot `upstream/...-c1937b9.tar.xz` do jith |

Observações sobre o repo do jith:
- Patches presentes: **0001, 0002, 0008, 0010, 0011** (não 0001..0011 contíguos; 0003–0007 e
  0009 não existem no repo). Ajustar PLAN Fase 2.
- `firmware/GF3208_RTSEC_APP_10062.bin` sha256 `faeb4810…7df3` — **byte-idêntico** a
  `vendor/goodix-fp-dump/firmware/5503/GF3208_RTSEC_APP_10062.bin` (repo oficial
  goodix-firmware). Ou seja, o 10062 não depende só da redistribuição do jith.
- `GF3268_RTSEC_APP_10041.bin` idêntico ao de `goodix-fp-dump/firmware/55x4/`.
- `flash-tool/{goodix,protocol,tool,driver_5503}.py` são **idênticos** aos do goodix-fp-dump
  (diff vazio). Só `flash_55a4_universal.py` é do jith.

### Fase 1.1 — Auditoria leitura/escrita (goodix-fp-dump `cc43bb3` + flash-tool do jith)

Transporte (`protocol.py`, `USBProtocol`): `__init__` faz `usb.core.find`, `get_status`,
`detach_kernel_driver` se houver, e **`set_configuration()`** (request USB padrão, não é
comando Goodix; reseta o estado de interface). Escrita em blocos de 0x40. `protocol.py`
importa `periphery` e `spidev` no topo (SPI) → não dá pra importar sem esses pacotes.

Framing (`goodix.py`): pacote `[flags=0xa0][len LE16][sum]` + mensagem
`[cmd][len+1 LE16][payload][checksum = 0xaa - sum]`; resposta: ACK (`0xb0`) + mensagem.

#### Comandos do protocolo (`goodix.py`, classe `Device`)

| Op | Função | Classe | Observação |
|---|---|---|---|
| 0x00 | `nop` | neutro | usado no init de todos os fluxos |
| 0xa8 | `firmware_version` | **LEITURA** | string da app (ou do IAP se estiver no bootloader) |
| 0xf6 | `get_iap_version(25)` | **LEITURA** | versão do bootloader |
| 0xa6 | `read_otp` | **LEITURA** | payload fixo `00 00`; nos fluxos é chamado após `reset` |
| 0xe4 | `preset_psk_read(flags)` | **LEITURA** | `0xbb020007` devolve hash do PMK; comparado com `PMK_HASH` (PSK zero) |
| 0x82 | `read_sensor_register` | **LEITURA** | chip ID em 0x0000; nos fluxos é após `reset` |
| 0xf2 | `read_firmware(off,len)` | **LEITURA** (só no IAP) | nenhum fluxo usa; exige estar no bootloader → H3 |
| 0xae | `query_mcu_state(payload)` | ambíguo | payload `000132`/`010032` sem semântica documentada → tratar como não-leitura |
| 0xd6 | `pov_image_check` | ambíguo | não usar |
| 0xd2 | `mcu_get_pov_image` | ambíguo | não usar |
| 0x20 | `mcu_get_image` | estado (RAM) | captura; precisa TLS |
| 0x32/0x34/0x36 | `mcu_switch_to_fdt_*` | estado (RAM) | |
| 0x50 | `nav` | estado | |
| 0x60/0x70/0x92 | sleep/idle modes | estado (RAM) | |
| 0x94 | `set_powerdown_scan_frequency` | estado | |
| 0x96 | `enable_chip` | estado | |
| 0xc4 | `set_drv_state` | estado | |
| 0xd0/0xd4 | TLS request / established | sessão | 0xd0 só abre handshake; sem PSK certa falha |
| 0x80 | `write_sensor_register` | **ESCRITA** (registrador do sensor, volátil?) | **[HIPÓTESE]** volátil; não usar |
| 0x90 | `upload_config_mcu` | **ESCRITA** (config do MCU) | **[HIPÓTESE]** RAM; não usar |
| 0xac | `set_pov_config` | **ESCRITA** (config) | persistência desconhecida |
| 0xa2 | `reset(sensor, soft_mcu, t)` | **reset** | não grava flash, mas `soft_reset_mcu=True` re-enumera o device; não usar nesta sessão |
| 0xe0 | `preset_psk_write(flags, payload)` | ⛔ **ESCRITA PERSISTENTE** | grava a PSK (`0xbb010003` + `PSK_WHITE_BOX`) |
| 0xa4 | `mcu_erase_app` | ⛔ **ESCRITA DESTRUTIVA** | apaga a app; device reaparece no bootloader IAP |
| 0xf0 | `write_firmware` | ⛔ **ESCRITA PERSISTENTE** | só no IAP |
| 0xf4 | `check_firmware(crc, hmac)` | ⛔ **ESCRITA/commit** | valida/ativa firmware gravado (HMAC derivado da PSK) |

#### Funções de alto nível (driver_55x4.py / driver_5503.py — idênticas em estrutura)

| Função | Escreve? | O que faz |
|---|---|---|
| `init_device` | não | `Device(...)` + `nop()` (+ `set_configuration` USB) |
| `check_psk` | não | `preset_psk_read(0xbb020007)`, compara com `PMK_HASH` |
| `write_psk` | ⛔ **SIM** | `preset_psk_write(0xbb010003, PSK_WHITE_BOX)` |
| `erase_firmware` | ⛔ **SIM** | `mcu_erase_app(50)` |
| `update_firmware` | ⛔ **SIM** | `write_firmware` em blocos de 256 + `check_firmware`; em erro chama `erase_firmware` |
| `run_driver` | sim (RAM/estado) | `reset`, OTP, TLS com PSK zero, `upload_config_mcu`, capturas |
| **`main()`** | ⛔ **SIM — perigosíssimo** | ver abaixo |

**`main()` (chamado por `run_55a4.py`, `run_55b4.py` e `flash_55a4_universal.py`):**
1. lê firmware, PSK-hash, IAP; aborta se IAP ≠ `MILAN_RTSEC_IAP_10027`;
2. se firmware == alvo e PSK não-zero → **`write_psk`** (grava PSK no app em execução!);
3. se firmware casa `GF32[0-9]{2}_RTSEC_APP_100[0-9]{2}` e ≠ alvo → **`erase_firmware`
   imediato**, sem outra confirmação;
4. se está no IAP → `write_psk` (se preciso) + `update_firmware`.

⇒ **Rodar `run_55a4.py` no nosso sensor (10039) apagaria a app na primeira iteração**, e então
gravaria o **10041** (GF3268, que o jith reporta como ruim neste chip). O `flash_55a4_universal.py`
do jith faz o mesmo caminho mas com alvo 10062. Nenhum deles será executado.

Notas para a Fase 3:
- **H1** (só PSK): no código, `write_psk` é chamado **com a app rodando** (passo 2) — ou seja,
  o comando 0xe0 é aceito pela app em pelo menos um firmware (10041/10062). Se a app 10039
  aceita 0xe0 sobrescrevendo uma PSK do Windows é **[HIPÓTESE]** não testada.
- Ordem no `update_firmware`: o HMAC do firmware é derivado da PSK (zero) → o IAP valida o
  firmware com a PSK atual; por isso o fluxo grava a PSK zero **antes** do firmware.
- **H3**: `read_firmware` (0xf2) existe no código, mas nenhum fluxo o usa e exige o device
  no IAP (= erase da app antes). Ler de volta o 10039 *antes* de apagá-lo não é possível por
  esse caminho. **[HIPÓTESE]** existe outro jeito de entrar no IAP sem erase — nada no código.
- driver libfprint (`goodix55x4.c`): checa firmware string, depois `preset_psk_read` e exige
  PSK == zero (`Invalid device PSK`). Patch 0010 do jith afrouxa a checagem de firmware para
  `GF32*_RTSEC_APP_100*` (aceitaria 10039) e decodifica OTP (`data[0x16]`, `data[0x17]`,
  `data[0x11]`) conforme `Wbdi.dll`.

#### Conjunto permitido no `tools/probe_readonly.py`

Whitelist rígida no transporte (qualquer outro opcode → exceção antes de tocar no USB):
`0x00 nop`, `0xa8 firmware_version`, `0xf6 get_iap_version`, `0xe4 preset_psk_read`,
`0xa6 read_otp`. Sem `set_configuration`, sem `reset`. Transporte reescrito (não importa
`protocol.py`). `read_sensor_register` (0x82) fica de fora: nos fluxos só roda após reset.

#### Validação do probe (sem USB)

`--dry-run`: os 5 frames gerados são **byte-idênticos** aos de `goodix.py` original
(`encode_message_pack(encode_message_protocol(...))`), e `command()`/`_write()` recusam
0xa4, 0xe0, 0xf0, 0xf4, 0xa2, 0x90, 0x80 (`NotAllowed`) antes de qualquer I/O.
Frames que serão enviados:
`a00800a80005000000000088` (nop), `a00600a6a803000000ff` (fw), `a00600a6f60300190098` (iap),
`a00c00ace40900070002bb00000000f9` (psk hash), `a00600a6a60300000001` (otp).
