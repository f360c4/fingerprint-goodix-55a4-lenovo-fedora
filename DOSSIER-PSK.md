# Dossiê — gravação da PSK Linux no Goodix 27c6:55a4

Leia antes de digitar `FLASH AUTORIZADO`. Versão 2026-10-08.

## 1. Estado atual do sensor (lido, não inferido)

Fonte: `dumps/probe-20261008-005703.json` + captura `dumps/probe-20261008-005703.pcapng`.

| | |
|---|---|
| Firmware | `GF3268_RTSEC_APP_10062` — universal Lenovo, o que o driver do jith exige |
| Bootloader | `MILAN_RTSEC_IAP_10027` |
| PSK | hash `4e2f7244…e10c` — não é a Linux (toda-zero). Gravada pelo Windows do dono anterior |
| OTP | tcode `0xd0`, FDT delta `0x17`, offset 0 — calibração válida |

## 2. O que será escrito (byte a byte)

Um único comando do protocolo Goodix, com a app rodando:

```
0xe0 preset_psk_write
flags   = 0xbb010003
payload = 030001bb 60000000 <96 bytes white-box PSK do goodix-fp-dump>
frame USB (112 B, 2 transfers de 64 B):
a06c000ce06900030001bb60000000ec35ae3abb45ed3f12c4751f1e5c2cc05b3c5452e9104d9f2a3118644f37a04b
6fd66b1d97cf80f1345f76c84f03ff30bb51bf308f2a9875c41e6592cd2a2f9e60809b17b5316037b69bb2fa5d4c8ac3
1edb3394046ec06bbdacc57da6a756c50d
```

Depois: `0xe4 preset_psk_read(0xbb020007)` e comparação do hash com `81b8ff49…0361`
(hash conhecido da PSK zero, `goodix_55x4_psk_0` no driver).

**Não** será enviado: `0xa4 erase`, `0xf0 write_firmware`, `0xf4 check_firmware`, `0xa2 reset`,
nada de IAP/bootloader. A ferramenta (`tools/pair_psk.py`) recusa esses opcodes antes de
qualquer I/O; validado em dry-run (`build/pair-dry.json`).

## 3. Precedentes

| Caso | Sensor | Firmware | Resultado |
|---|---|---|---|
| jith/goodix-55a4-fingerprint#1 (ThinkBook 15-IIL, Omarchy) | **55a4** | 10052, Windows-paired | gravou só a PSK com a app rodando; driver do jith funcionou (enroll, verify, sudo, lockscreen) |
| TheWeirdDev/libfprint#3 (Void Linux) | 55b4 | 10056, Windows-paired | idem, via driver; funcionou |
| goodix-fp-dump `driver_5503.py` `main()` | 5503/55a4 | 10062 | é exatamente o ramo `WORKING_FIRMWARE and not valid_psk → write_psk` |
| jith (20RA) | 55a4 | 10041 → 10062 via IAP | funcionou, mas pelo caminho longo (não é o nosso) |

Nenhum relato de falha dessa gravação com a app rodando. n pequeno (2 relatos públicos + o
código da comunidade que a assume).

## 4. Riscos

| Risco | Probabilidade | Consequência | Mitigação |
|---|---|---|---|
| App 10062 rejeita o 0xe0 (status ≠ 0) | baixa (precedentes) | nada muda; sensor segue com PSK Windows | ferramenta para, não repete; discutimos |
| Hash após gravação ≠ esperado | baixa | PSK "estranha" no sensor; Linux e Windows não pareiam | regravar (mesmo comando) — é o que o `main()` da comunidade faz em loop |
| Travamento do MCU durante o comando | muito baixa | sensor não responde até re-enumerar | replug lógico (suspend/resume ou `authorized` em sysfs); firmware intacto |
| Pior caso: app corrompida | sem relato | sensor cai pro IAP | caminho de flash do jith (10062, testado) como último recurso — dossiê separado |
| Windows Hello deixa de funcionar | certa | — | **irrelevante**: não há Windows nesta máquina; a PSK antiga já era irrecuperável |
| Bug `goodix_send_preset_psk_write` do libfprint | n/a | PSK truncada | **não usamos o libfprint pra gravar**; driver instalado só lê |

Rollback para a PSK do Windows: **não existe** (e não é necessário).

## 5. Pré-condições (abortar se alguma falhar)

- [ ] AC conectada, bateria > 50 %
- [ ] `systemd-inhibit --what=sleep:idle:handle-lid-switch --who=psk --why="goodix psk" sleep infinity &`
- [ ] `sudo systemctl stop fprintd`; `fuser /dev/bus/usb/001/003` vazio
- [ ] `probe_readonly.py` logo antes: firmware 10062, IAP 10027, hash `4e2f…` (nada mudou)
- [ ] usbmon gravando (`tools/run_pair_captured.sh` faz probe → pair → probe sob captura)
- [ ] `FLASH AUTORIZADO` digitado na sessão

## 6. Depois

1. `probe_readonly.py`: hash deve ser `81b8ff49…0361`.
2. `systemctl start fprintd`; `fprintd-verify`: driver deve passar de `Checking PSK` e abrir TLS.
3. Se o handshake TLS falhar com PSK certa → aplicar patch de cipher list (`PSK:@SECLEVEL=0`,
   do PR #3), rebuild do RPM. Teste offline sugere que **não** será necessário no Fedora.
4. Fase 5: enroll, PAM, publicação.

## 7. Peça de reposição (H4)

A verificar no Lenovo Parts Lookup pelo serial. Pendente.
