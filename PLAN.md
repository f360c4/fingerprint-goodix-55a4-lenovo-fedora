# Plano — Goodix 27c6:55a4 no Fedora (ThinkPad E14 Gen 1 / 20RB002BBR)

Revisado em 2026-10-08 depois da Fase 1. Mudança central: **o sensor já está no firmware
10062** (o que o driver do jith exige) e **só a PSK está errada** (é a do Windows). Não há
flash de firmware no plano. A única escrita no sensor é **um comando de PSK** (Fase 4), que
continua exigindo `FLASH AUTORIZADO`. Cada fase termina com entrada em `NOTES.md` e commit.

Histórico detalhado e evidências: `NOTES.md`.

---

## Fase 0 — Base ✅ (2026-10-08)

Máquina `20RB002BBR` (E14 Gen 1, BIOS R16ET30W 1.16), Fedora 44, kernel 7.2.8, libfprint
1.94.100, fprintd 1.94.5, OpenSSL 3.5.9. Repos em `vendor/` (gitignored):
goodix-fp-dump `cc43bb3`, jith-55a4 `e8ee5bc`, libfprint-55b4 `c1937b9`. Venv em `.venv/`.

## Fase 1 — Reconhecimento ✅ (2026-10-08)

`tools/probe_readonly.py` (whitelist 0x00/0xa8/0xf6/0xe4/0xa6, captura usbmon confirma) leu:

| | Lido |
|---|---|
| Firmware | **`GF3268_RTSEC_APP_10062`** (universal Lenovo; não é o 10039 de fábrica) |
| Bootloader | `MILAN_RTSEC_IAP_10027` |
| PSK | hash `4e2f7244…e10c` ≠ PSK zero → **pareado pelo Windows** (máquina veio usada com Windows) |
| OTP | tcode `0xd0`, FDT delta `0x17`, FDT offset 0, calibração válida |

Precedentes achados na pesquisa (detalhe em NOTES.md):
- **jith/goodix-55a4-fingerprint#1**: 55a4, firmware 10052 pareado pelo Windows, gravou só a
  PSK (`preset_psk_write(0xbb010003, PSK_WHITE_BOX)`) com a app rodando, sem erase/flash/reset;
  driver do jith funcionou. É o nosso caso, com firmware ainda melhor (10062).
- **TheWeirdDev/libfprint#3**: 55b4, 10056 Windows-paired, mesma gravação, funcionou. Revela
  (a) `goodix_send_preset_psk_write` do fork é **bugada** (PSK truncada) — nunca gravar pelo
  libfprint; (b) `"ALL"` como cipher list quebra TLS-PSK no OpenSSL 3 → fix `"PSK:@SECLEVEL=0"`.

---

## Fase 2 — Pipeline do driver ✅ (2026-10-08 01:33 — parou em `Invalid device PSK`, como previsto)

Objetivo: libfprint patcheado instalado como RPM, driver lendo `GF3268_RTSEC_APP_10062` e
parando em `Invalid device PSK`. Com o firmware certo, essa deve ser a **única** barreira.

1. Árvore de build: `vendor/jith-55a4/driver/upstream/libfprint-…-c1937b9.tar.xz` +
   `patches/0001, 0002, 0008, 0010, 0011` (são só esses cinco). `patch -Np1 --dry-run` em cada.
2. Conferir que nenhum patch adiciona chamada a `goodix_send_preset_psk_write` (grep). O
   driver instalado **não pode** escrever PSK.
3. Patch nosso `0012-goodixtls-openssl3-psk-seclevel.patch`: trocar `"ALL"` por
   `"PSK:@SECLEVEL=0"` em `goodixtls.c` (duas ocorrências), **[HIPÓTESE]** necessário no
   Fedora por causa do crypto-policies `@SECLEVEL=2`. Decidir após o primeiro teste na Fase 4:
   se o handshake falhar com PSK correta, aplicar. Pode ser incluído já na Fase 2 se o build
   permitir testar o caminho TLS em isolamento (ex.: teste unitário com `openssl s_client`).
4. `rpm/libfprint-goodixtls-55a4.spec`: `Name: libfprint-goodixtls-55a4`, `Version: 1.94.6`,
   `Release: 0.<n>.c1937b9%{?dist}`, `Provides: libfprint = %{version}-%{release}`,
   `Conflicts: libfprint`; meson `-D doc=false`; entrega `libfprint-2.so*`, headers, typelib,
   udev rules. Checar dependência `opencv-devel` (sigfm) e se `libfprint-devel` precisa de
   `Provides` também.
5. `rpmbuild -ba` (ou `mock -r fedora-44-x86_64`). Script `rpm/build.sh`.
6. Instalar: `sudo dnf swap libfprint libfprint-goodixtls-55a4-*.rpm`;
   `sudo dnf versionlock add libfprint-goodixtls-55a4`; `sudo systemctl restart fprintd`.
7. Teste: `fprintd-verify` + `journalctl -u fprintd -b` → `logs/phase2-fprintd.log`. Esperado:
   `Device firmware: "GF3268_RTSEC_APP_10062"` e `Invalid device PSK: 0x4e2f…`.
8. Confirmar que sudo e login seguem só por senha.

Pronto quando:
- [ ] RPM builda reproduzivelmente a partir do repo (`rpm/` commitado)
- [ ] versionlock ativo; `dnf upgrade --refresh` não troca o libfprint
- [ ] log mostra firmware 10062 e falha **somente** em `Invalid device PSK`

---

## Fase 3 — Preparação da gravação da PSK ✅ (pair_psk.py + DOSSIER-PSK.md)

Objetivo: ferramenta auditada e dossiê, pra Fase 4 ser um passo único e curto.

1. **`tools/pair_psk.py`** — escrito do zero sobre o framing do `probe_readonly.py`, **sem**
   importar `driver_*.py` nem chamar `main()` do goodix-fp-dump. Whitelist: 0x00, 0xa8, 0xf6,
   0xe4, **0xe0**. Fluxo:
   - lê firmware; aborta se não casar `GF32[0-9]{2}_RTSEC_APP_10062`;
   - lê IAP; aborta se ≠ `MILAN_RTSEC_IAP_10027`;
   - lê hash; se já `== PMK_HASH` → "já pareado", sai sem escrever;
   - imprime `⚠️ ESTE PASSO ESCREVE NO SENSOR` e o payload exato; exige confirmação
     interativa **e** flag `--i-typed-flash-autorizado`;
   - `preset_psk_write(0xbb010003, PSK_WHITE_BOX)` (1 comando); espera reply `0x00`;
   - relê hash; sucesso ⇔ `== PMK_HASH`. Em falha: **não reenvia**; salva log e sai.
   - `--dry-run` imprime os bytes; salva `dumps/pair-YYYYMMDD.json` com log USB completo.
   - validar no dry-run que os bytes batem com `goodix.preset_psk_write` original.
2. **`DOSSIER-PSK.md`**: estado atual (probe), o que será escrito (byte a byte), precedentes
   (jith#1, PR#3), riscos (app rejeitar; hash não bater; travamento), mitigações, o que **não**
   fazemos (erase/IAP/firmware), plano B (caminho IAP do jith, só como último recurso, dossiê
   separado), e peça de reposição.
3. **H4 — Peça**: Lenovo Parts Lookup pelo serial do 20RB: o leitor é FRU separado? preço BR.
4. **H5 (opcional, pesquisa)**: derivação do `PMK_HASH` a partir da PSK (não é
   `sha256(pmk)` nem `sha256(psk)` — testado). Útil só como oráculo; não bloqueia nada.
5. Capturas Windows na máquina do irmão: **rebaixadas a opcional** (a PSK dele não é a nossa).
   Só se precisarmos entender o fluxo de captura do Windows pra tuning (Fase 5).

Pronto quando:
- [ ] `pair_psk.py` com dry-run validado e recusando qualquer opcode fora da whitelist
- [ ] `DOSSIER-PSK.md` lido pelo Luiz

---

## Fase 4 — Gravar a PSK ✅ (2026-10-08 01:41 — `SUCCESS`, hash = PSK zero, firmware intacto)

Só começa depois do dossiê lido e `FLASH AUTORIZADO` digitado na sessão.

Pré-condições (abortar se alguma falhar):
- [ ] AC conectada, bateria > 50 %
- [ ] `systemd-inhibit --what=sleep:idle:handle-lid-switch --who=psk --why="goodix psk" sleep infinity &`
- [ ] `fprintd` parado; `fuser /dev/bus/usb/001/00N` vazio
- [ ] `probe_readonly.py` imediatamente antes: firmware 10062, IAP 10027, hash `4e2f…` (estado inalterado)
- [ ] usbmon gravando (`dumps/pair.pcapng`)

Executar `sudo tools/pair_psk.py --i-typed-flash-autorizado`. Depois: `probe_readonly.py`
(hash deve ser `81b8ff49…0361`), `systemctl start fprintd`, `fprintd-verify` deve passar da
fase TLS. Se o handshake TLS falhar com PSK correta → aplicar patch 0012 (Fase 2.3), rebuild.

Rollback: a PSK do Windows não volta — irrelevante (sem Windows). Firmware fica intacto.

---

## Fase 5 — Entrega (em andamento: enroll 40/40 e verify 3/3 feitos; TLS OK sem patch)

1. Enroll com `vendor/jith-55a4/scripts/enroll.sh` adaptado (sem pacman); 40 presses.
2. `fprintd-verify` ×10; registrar taxa e scores SIGFM. Tuning (tcode do nosso OTP é 0xd0,
   não 0xf0 — os defaults do jith podem precisar ajuste; documentar).
3. PAM: `sudo authselect enable-feature with-fingerprint` (sufficient). Senha continua.
4. Repetir teste de suspend com driver carregado (re-enumeração relatada pelo jith).
5. Publicar: COPR com o spec; `README.pt-BR.md`; comentar em **jith#1** como segundo caso
   (20RB, 10062 Windows-paired, pairing-only) e propor PR do helper pairing-only; reportar o
   bug de `goodix_send_preset_psk_write` e o fix de cipher list (se confirmado no Fedora)
   pra TheWeirdDev/libfprint e goodix-fp-linux-dev.
6. `tools/check-libfprint.sh`: hook pós-update que testa se `libfprint-2.so` ainda carrega.

---

## Fase 6 — Pacotes Debian/Ubuntu ✅ (2026-10-08, manhã)

`deb/` (debian/control, rules, install, copyright + `build.sh` com podman). `.deb` pra Ubuntu
24.04, Ubuntu 26.04 e Debian 13, versionados `1:1.94.9+goodix55a4.1.94.6.c1937b9-1~<distro>`
pra satisfazer o `libfprint-2-2 (>= 1:1.94.9)` do fprintd; `Provides/Conflicts/Replaces`
`libfprint-2-2` e `libfprint-2-tod1`. Testado em contêiner (instalação, símbolos do fprintd,
deps); **não** testado com sensor real nessas distros. Anexados à release v0.1.0.
