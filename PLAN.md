# Plano — Goodix 27c6:55a4 no Fedora (ThinkPad E14 Gen 1 / 20RA)

Fases 0–3 não escrevem nada no sensor. A Fase 4 é a única com risco de brick e só começa
com `FLASH AUTORIZADO`. Cada fase termina com uma entrada em `NOTES.md` e um commit.

---

## Fase 0 — Base (sem risco)

Objetivo: ambiente pronto, fontes clonadas, inventário da máquina.

```bash
# identidade da máquina
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version /sys/class/dmi/id/bios_version
rpm -E %fedora; uname -r
lsusb -d 27c6:55a4
sudo lsusb -v -d 27c6:55a4 > logs/lsusb-v.txt
rpm -q libfprint fprintd fprintd-pam opencv

# ferramentas
sudo dnf install -y git usbutils wireshark-cli meson ninja-build gcc gcc-c++ pkgconf \
  glib2-devel libgusb-devel openssl-devel pixman-devel nss-devel libgudev-devel \
  opencv-devel gtk-doc gobject-introspection-devel doctest-devel \
  python3 python3-devel rpm-build rpmdevtools dnf-plugins-core fprintd fprintd-pam
# versionlock: dnf4 -> python3-dnf-plugin-versionlock ; dnf5 -> dnf5-plugins
sudo dnf install -y python3-dnf-plugin-versionlock || sudo dnf install -y dnf5-plugins

# fontes (como submódulos ou clones em vendor/)
mkdir -p vendor logs dumps tools rpm
git clone https://github.com/jith/goodix-55a4-fingerprint vendor/jith-55a4
git clone --recurse-submodules https://github.com/goodix-fp-linux-dev/goodix-fp-dump vendor/goodix-fp-dump
git clone -b 55b4-experimental https://github.com/TheWeirdDev/libfprint vendor/libfprint-55b4
```

Pronto quando:
- [ ] `product_name` começa com `20RA` (se não, registrar o modelo real e reavaliar)
- [ ] `lsusb` mostra `27c6:55a4`
- [ ] três repositórios clonados, `vendor/` no `.gitignore` ou como submódulo
- [ ] NOTES.md tem: modelo, BIOS, Fedora, kernel, versões de libfprint/fprintd/opencv

---

## Fase 1 — Reconhecimento (sem risco)

Objetivo: saber exatamente o estado do sensor sem escrever nele.

1. **Auditar o goodix-fp-dump** (`goodix.py`, `protocol.py`, `driver_55x4.py`, `run_55b4.py`,
   `flash-tool/`): listar em `NOTES.md` cada função que **escreve** no sensor (firmware,
   PSK, IAP, erase, reset de config) e cada função de **leitura** (firmware version,
   MCU info, OTP, PSK hash/check, config). Não rodar `run_*.py` inteiro.
2. Escrever `tools/probe_readonly.py` usando só as funções de leitura:
   - versão de firmware (esperado: `GF3208_RTSEC_APP_10039`)
   - info do MCU / bootloader (esperado: `MILAN_RTSEC_IAP_10027`)
   - OTP (calibração: tcode, FDT delta/offset)
   - se o protocolo permitir checar a PSK sem escrever: fazer, e registrar que a PSK
     toda-zero **não** é aceita (confirma que estamos pareados com Windows)
   - salvar tudo em `dumps/probe-YYYYMMDD.json`
   - precisa parar o `fprintd` antes (`sudo systemctl stop fprintd`) e rodar como root ou
     com regra udev
3. **Captura USB do fprintd de estoque** (controle): `sudo modprobe usbmon`, descobrir o
   barramento do sensor, `sudo tshark -i usbmonN -w dumps/stock-fprintd.pcapng` enquanto
   roda `fprintd-list $USER` e `fprintd-verify`. Serve de baseline do que o Linux manda hoje.
4. Verificar se o sensor **re-enumera após suspend** (relatado pelo jith) — anotar.

Pronto quando:
- [ ] `NOTES.md` tem a tabela leitura/escrita do goodix-fp-dump
- [ ] `dumps/probe-*.json` com firmware, bootloader e OTP
- [ ] sabemos se o firmware é 10039 (caminho não testado) ou outro

---

## Fase 2 — Pipeline do driver (sem risco)

Objetivo: libfprint patcheado instalado como RPM, driver reconhecendo o device e parando
em `Invalid device PSK`. Prova que tudo funciona até a camada TLS.

1. Montar a árvore de build a partir de `vendor/jith-55a4/driver/`:
   snapshot `upstream/*.tar.xz` (commit `c1937b9` do fork) + `patches/0001..0011`.
   Conferir se os patches aplicam limpo (`patch -Np1 --dry-run`).
2. `rpm/libfprint-goodixtls-55a4.spec`:
   - `Name: libfprint-goodixtls-55a4`, `Version: 1.94.6`, `Release: 0.<n>.c1937b9%{?dist}`
   - `Provides: libfprint = %{version}-%{release}`, `Conflicts: libfprint`
   - build com meson, `-D doc=false`, sem instalar nada além de `libfprint-2.so*`,
     headers, typelib e as regras udev que o pacote original já entrega
   - checar se o Fedora precisa do pacote `libfprint-devel` separado (provavelmente não)
3. `rpmbuild -ba` (ou `mock -r fedora-$(rpm -E %fedora)-x86_64` pra build limpo).
4. Instalar: `sudo dnf swap libfprint libfprint-goodixtls-55a4-*.rpm`,
   `sudo dnf versionlock add libfprint-goodixtls-55a4`, `sudo systemctl restart fprintd`.
5. Teste: `fprintd-verify` e `journalctl -u fprintd -b`. Esperado: driver `goodixtls`
   carrega, lê `Device firmware: "GF3208_RTSEC_APP_10039"`, falha em `Invalid device PSK`
   ou `Invalid device firmware`. Guardar o log em `logs/phase2-fprintd.log`.
6. Confirmar que `sudo` e login continuam só por senha (nada de PAM ainda).

Pronto quando:
- [ ] RPM builda reproduzivelmente a partir do repo
- [ ] `dnf versionlock` ativo; `dnf upgrade --refresh` não tenta trocar o libfprint
- [ ] log mostra o driver chegando na fase TLS e falhando pela PSK (não antes)
- [ ] `rpm/` commitado com spec + script `build.sh`

---

## Fase 3 — Investigação da PSK (sem risco de brick)

Objetivo: responder se existe caminho **sem flash** ou, pelo menos, reduzir o risco do flash.
Tudo aqui é pesquisa; registrar hipóteses como hipóteses.

Hipóteses a testar, em ordem de custo:

**H1 — Gravar só a PSK no firmware de fábrica.** No `flash-tool` do goodix-fp-dump, a
gravação da PSK é um comando separado do upload do firmware? Se sim, dá pra escrever a PSK
toda-zero no 10039 sem erase/IAP? (É escrita no sensor → mesmo assim só com
`FLASH AUTORIZADO`, mas o risco é muito menor que trocar o app.) O driver do jith aceita
`GF32xx_RTSEC_APP_100xx` — então 10039 + PSK Linux pode até rodar o fluxo de captura.
Analisar o código; não executar.

**H2 — Recuperar a PSK do Windows.** Na máquina do irmão (só leitura, com permissão dele):
- instalar USBPcap + Wireshark, capturar (a) boot/inicialização do driver, (b) um
  `verify` do Windows Hello; salvar em `dumps/windows-*.pcapng`
- localizar onde o driver Goodix guarda o estado do pareamento: chaves de registro do
  driver (`HKLM\SYSTEM\CurrentControlSet\...`, `Enum\USB\VID_27C6&PID_55A4`), arquivos em
  `C:\Windows\System32\drivers`, `WinBioDatabase`; copiar `Wbdi.dll`, `.inf`, `.sys` e o
  pacote do driver `r16gf09w` pra `dumps/windows-driver/` (contém o firmware 10062 — fonte
  legítima, sem depender da redistribuição do jith)
- analisar o `Wbdi.dll` (Ghidra/radare2) pra ver como a PSK é derivada/armazenada;
  se vier de TPM/DPAPI por máquina, o caminho sem flash morre aqui — registrar e seguir
- **não** reinstalar driver nem forçar re-pareamento na máquina dele

**H3 — Dump do app atual antes do flash.** O bootloader MILAN IAP permite ler o app de
volta? Se sim, `dumps/app-10039-backup.bin` vira o caminho de volta pro estado de fábrica
que hoje não existe na comunidade. Só leitura, mas passa pelo IAP → tratar como escrita
(exige `FLASH AUTORIZADO`) e discutir antes.

**H4 — Peça de reposição.** Verificar no Lenovo Parts Lookup (pelo serial) se o leitor de
digitais do 20RA é FRU separado e quanto custa no Brasil. Se for uma plaquinha barata,
o pior caso da Fase 4 vira "comprar peça".

Pronto quando:
- [ ] cada hipótese tem veredito em NOTES.md: confirmada / refutada / inconclusiva + evidência
- [ ] dossiê `DOSSIER-FLASH.md` com: estado atual do sensor, caminho de flash proposto
  (10039 → ? → 10062), o que é testado e o que não é, mitigações, plano de rollback
  (ou "não há rollback"), custo da peça

---

## Fase 4 — Flash (ÚNICO passo com risco)

Só começa depois do dossiê lido pelo Luiz e `FLASH AUTORIZADO` digitado na sessão.

Pré-condições (checar todas, abortar se alguma falhar):
- [ ] AC conectada, bateria > 50%
- [ ] `systemd-inhibit --what=sleep:idle:handle-lid-switch --who=flash --why="goodix flash" sleep infinity &`
- [ ] tampa aberta, laptop numa mesa, nada no USB além do necessário
- [ ] `fprintd` parado, nenhum outro processo com o device aberto (`lsof /dev/bus/usb/...`)
- [ ] SHA-256 do firmware conferido contra o esperado
- [ ] bootloader confirmado `MILAN_RTSEC_IAP_10027` na Fase 1
- [ ] captura usbmon rodando pra ter o registro do flash (`dumps/flash.pcapng`)

Executar o `flash-firmware.sh` do jith (ou o equivalente auditado), sem interromper.
Depois: `lsusb`, `probe_readonly.py` de novo, `systemctl start fprintd`, e
`journalctl -u fprintd -b | grep "Device firmware"` deve mostrar `_10062`.

---

## Fase 5 — Entrega

1. Enroll com `vendor/jith-55a4/scripts/enroll.sh` (adaptar o que for pacman-específico):
   sensor limpo, dedo seco, toque leve, 40 presses.
2. `fprintd-verify` ×10, registrar taxa de acerto e scores SIGFM.
3. PAM no Fedora: `sudo authselect enable-feature with-fingerprint` (sudo e desbloqueio KDE);
   conferir que a senha continua funcionando com o sensor desplugado/lógico.
4. Tuning se precisar (`tune.sh`, tcode, threshold) — documentar valores do **nosso** sensor.
5. Publicar: COPR `luizfelipe/libfprint-goodixtls-55a4` (ou nome que ele escolher) com
   o spec; `README.pt-BR.md` com o guia; issue/PR no repo do jith e no
   `goodix-fp-linux-dev` com o caminho 10039 documentado, dumps anonimizados e os patches
   em `git format-patch`.
6. Pós-update: hook `dnf` (ou script em `tools/check-libfprint.sh`) que testa se a
   `libfprint-2.so` ainda carrega depois de update de opencv/glib2/openssl/libgusb.
