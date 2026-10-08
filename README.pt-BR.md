# Leitor de digitais do Lenovo ThinkPad E14 Gen 1 no Linux (Fedora) — Goodix 27c6:55a4

*English summary: [README.md](README.md).*

Seu ThinkPad E14 Gen 1 (machine type 20RA ou 20RB) tem leitor de digitais, o `lsusb` mostra
`27c6:55a4 Goodix FingerPrint Device`, mas no Linux o `fprintd-enroll` responde
**`No devices available`** e as configurações de "Impressão digital" do KDE/GNOME não mostram
nada. Isso acontece porque o `libfprint` do Fedora (e de qualquer distro) **não tem driver**
pra esse sensor — ele aparece na lista de "dispositivos não suportados".

Este repositório faz o leitor funcionar no **Fedora** — `sudo`, tela de bloqueio e login por
digital — com:

- um **RPM pronto** do driver da comunidade (`goodixtls`, do
  [jith/goodix-55a4-fingerprint](https://github.com/jith/goodix-55a4-fingerprint), feito pra
  Arch/CachyOS): baixe em [Releases](../../releases) ou compile com `rpm/build.sh`;
- uma ferramenta de **pareamento sem flash**: se o seu leitor já está no firmware universal
  da Lenovo `GF32xx_RTSEC_APP_10062` (provável, se o notebook já rodou Windows com Windows
  Update), **não precisa trocar firmware** — um único comando de 112 bytes troca a chave de
  pareamento do Windows pela do Linux. Sem bootloader, sem apagar nada, sem o risco de
  inutilizar o leitor que um flash de firmware tem;
- um **probe só-leitura** que diz em que firmware, bootloader e estado de pareamento o seu
  leitor está **antes** de você mudar qualquer coisa;
- todos os logs e medições (`NOTES.md`), pra próxima pessoa não precisar adivinhar.

Testado em 2026-10-08: ThinkPad E14 Gen 1 **20RB002BBR**, Fedora 44 KDE Plasma, kernel 7.2,
OpenSSL 3.5, OpenCV 4.13 — cadastro 40/40 toques aceitos, verificação 3/3, `sudo` e tela de
bloqueio por digital, senha continua funcionando, sobrevive a suspend/resume. O mesmo
caminho de só-pareamento foi relatado funcionando num ThinkBook 15-IIL com firmware 10052 no
Omarchy (issue #1 do jith). Trabalho de base: jith (driver) e
[goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev/goodix-fp-dump) (protocolo).

> **Leia antes.** O passo 3 escreve no sensor. É um único comando, com precedente, mas é
> uma escrita. Entenda o que ele faz antes de rodar. Este guia é fornecido sem garantia.

## Como funciona (em 5 linhas)

O 55a4 manda a imagem crua do dedo pro computador dentro de uma sessão TLS; a chave dessa
sessão (PSK) fica gravada no sensor e é definida por quem pareia com ele — normalmente o
Windows, com uma chave secreta por máquina. O Linux não conhece essa chave, então o driver
para em `Invalid device PSK`. A solução da comunidade é gravar no sensor uma chave
conhecida (toda-zero). Depois disso, qualquer Linux com o driver funciona. Windows Hello
para de funcionar até o Windows re-parear (ele faz isso sozinho ao reinstalar).

## Antes de começar: em que estado está o seu sensor?

O driver precisa do firmware **`GF32xx_RTSEC_APP_10062`** (firmware universal da Lenovo,
que vem pelo driver Windows `r16gf09w`). Se a sua máquina já teve Windows com Windows Update,
é provável que já esteja nele — foi o caso desta. Pra saber sem escrever nada:

```bash
git clone https://github.com/f360c4/fingerprint-goodix-55a4-lenovo-fedora
cd fingerprint-goodix-55a4-lenovo-fedora
python3 -m venv .venv && .venv/bin/pip install pyusb
sudo systemctl stop fprintd
sudo .venv/bin/python tools/probe_readonly.py
```

Saída esperada (exemplo desta máquina):

```
firmware_version -> GF3268_RTSEC_APP_10062      ← OK (GF3208/3258/3268 variam; o que importa é _10062)
iap_version      -> MILAN_RTSEC_IAP_10027
psk_hash         -> is_zero_psk: False          ← pareado com o Windows; o passo 3 resolve
```

| Firmware lido | O que fazer |
|---|---|
| `GF32xx_RTSEC_APP_10062` | Siga este guia. **Nenhum flash de firmware necessário.** |
| `GF3208_RTSEC_APP_10039` (fábrica) ou `GF3268_RTSEC_APP_10041` | Este guia **não** cobre. Precisa trocar o firmware pelo bootloader (risco de inutilizar o leitor); veja o [guia do jith](https://github.com/jith/goodix-55a4-fingerprint#1-check-the-firmware-one-time). |
| `MILAN_RTSEC_IAP_10027` como firmware | O sensor está em modo bootloader (app apagada). Idem acima. |

## 1. Instalar o driver (RPM)

O Fedora traz um `libfprint` sem driver pro 55a4. Este pacote **substitui** o `libfprint`
do sistema (mesmo soname, `fprintd` continua o mesmo) e fica travado pra update não desfazer.

```bash
sudo dnf install -y meson ninja-build gcc gcc-c++ glib2-devel libgusb-devel openssl-devel \
  pixman-devel nss-devel libgudev-devel opencv-devel gtk-doc gobject-introspection-devel \
  rpm-build rpmdevtools dnf5-plugins
rpm/build.sh                                   # gera rpm/out/*.rpm (~2 min)
sudo dnf swap libfprint rpm/out/libfprint-goodixtls-55a4-*.x86_64.rpm
sudo dnf versionlock add libfprint-goodixtls-55a4
```

Sem compilar: baixe o `.rpm` pronto na página de **Releases** deste repositório e rode só as duas
linhas `dnf swap` / `dnf versionlock`. (Pacote pronto só pra versão do Fedora indicada na release.)

Teste: `fprintd-list $USER` deve dizer `Goodix TLS Fingerprint Sensor 55X4`. Um `fprintd-enroll`
agora vai falhar com `Invalid device PSK` — é o esperado antes do passo 3.

## 2. Entenda o que o pareamento faz

`tools/pair_psk.py` manda **um** comando ao sensor (`preset_psk_write`, 112 bytes) que troca
a chave do Windows pela chave Linux. Ele:

- recusa qualquer outro comando (lista fixa de opcodes; validado contra o código original);
- aborta se o firmware não for `_10062` ou o bootloader não for `MILAN_RTSEC_IAP_10027`;
- não faz erase, não entra no bootloader, não grava firmware, não dá reset;
- relê a chave depois e só declara sucesso se o hash bater com o esperado.

Consequência irreversível: a chave antiga do Windows se perde. Se você tem dual boot, o
Windows Hello para de funcionar até o Windows re-parear — e aí o Linux para até você rodar
o passo 3 de novo. Só uma chave cabe no sensor.

Detalhes, riscos e precedentes: [`DOSSIER-PSK.md`](DOSSIER-PSK.md).

## 3. Parear (escreve no sensor)

Carregador conectado, tampa aberta.

```bash
sudo tools/run_pair_captured.sh
```

Ele checa AC/bateria, para o `fprintd`, impede suspend, lê o sensor, mostra o que vai gravar,
pede um código de 4 dígitos, grava, relê, e salva log + captura USB em `logs/` e `dumps/`.
Saída esperada: `write reply: 00 -> OK` … `SUCCESS: sensor now has the Linux PSK`.
Se der `FAILED`, **não repita**; abra uma issue com o `logs/pair-*.log`.

## 4. Cadastrar a digital

```bash
tools/enroll.sh            # indicador direito, 40 toques leves, dedo seco
fprintd-verify             # repita algumas vezes
```

Dica que vale ouro: toque **leve** e **curto**, e tire o dedo todo entre os toques. Dedo
suado ou pressão forte "afoga" as cristas e o driver pede de novo.

## 5. PAM (sudo e tela de bloqueio)

```bash
sudo authselect enable-feature with-fingerprint
```

Isso adiciona `pam_fprintd.so` como **`sufficient`**: a senha continua funcionando sempre
(Enter sem dedo → cai na senha). Vale pra `sudo`, desbloqueio do KDE e também pro login do SDDM.

## Depois de updates do sistema

```bash
tools/check-libfprint.sh
```

Se o OpenCV, glib ou OpenSSL mudarem de soname, a lib para de carregar; é só `rpm/build.sh`
e `sudo dnf reinstall rpm/out/libfprint-goodixtls-55a4-*.x86_64.rpm`.

## SELinux (opcional)

Pode aparecer um alerta "SELinux está impedindo fprintd de acessar nr_hugepages". É só o
OpenCV sondando memória ao carregar; o SELinux bloqueia, o OpenCV segue sem, nada deixa de
funcionar. Se o alerta incomodar: `sudo dnf install selinux-policy-devel && sudo selinux/install.sh`.

## Problemas

| Sintoma | O que ver |
|---|---|
| `No devices available` | `lsusb -d 27c6:55a4`; depois de suspend, `sudo systemctl restart fprintd` |
| `Invalid device PSK` depois de ter pareado | O Windows re-pareou o sensor → passo 3 de novo |
| `Invalid device firmware` | Firmware não é `_10062` → tabela do início |
| Muitos "place your finger again" | Dedo seco, toque mais leve; `journalctl -u fprintd -b \| grep valley` mostra a qualidade |
| Logs detalhados | `sudo mkdir -p /etc/systemd/system/fprintd.service.d && printf '[Service]\nEnvironment=G_MESSAGES_DEBUG=all\n' \| sudo tee /etc/systemd/system/fprintd.service.d/50-goodix-debug.conf && sudo systemctl daemon-reload` |

## O que foi medido nesta máquina

- Firmware já era `GF3268_RTSEC_APP_10062` de fábrica/Windows Update; PSK do Windows.
- Pareamento com a app rodando: aceito (`00`), hash depois = chave Linux. Firmware intacto.
- OTP: tcode `0xd0`, FDT delta `0x17`. Imagens: valley depth 0,23–0,54 (gate 0,18), 40/40
  toques aceitos no enroll sem repetição, 3/3 verify.
- TLS funciona com a crypto-policy padrão do Fedora (`SECLEVEL=2`), sem patch de cipher.
- Nada disso precisa do bootloader. O caminho de flash do jith continua valendo como último
  recurso pra quem está no 10039/10041.

Notas completas da investigação: [`NOTES.md`](NOTES.md). Plano: [`PLAN.md`](PLAN.md).

## Por que isso não está "no kernel" ou já no Fedora?

Leitor de digitais no Linux **não é driver de kernel**. O kernel só expõe o dispositivo USB;
o driver vive no **libfprint** (programa de usuário, do freedesktop.org), e o `fprintd` fala
com ele. O libfprint oficial não aceitou driver pra família Goodix "TLS" (5110, 5503, 55a4,
55b4…) por causa de como esses sensores funcionam: eles mandam a **imagem crua** do dedo pro
computador dentro de uma sessão TLS, a comparação é feita no PC (o libfprint oficial prefere
sensores que comparam no próprio chip), a solução da comunidade exige **gravar uma chave
pública conhecida dentro do sensor**, o comparador depende do OpenCV, e protocolo e firmware
foram obtidos por engenharia reversa. Por isso o driver só existe em *forks* (TheWeirdDev →
jith) que substituem o `libfprint` inteiro — e por isso o Fedora não pode distribuir, e este
repositório o empacota como RPM substituto (`Provides/Conflicts: libfprint`) com `versionlock`.

O que dá pra devolver pra comunidade, e o que este repositório devolve:
- pro **jith/goodix-55a4-fingerprint**: um segundo caso confirmado de só-pareamento (10062,
  pareado pelo Windows, 20RB, Fedora) e a ferramenta de pareamento (issue #1);
- pro **TheWeirdDev/libfprint**: o bug de tamanho em `goodix_send_preset_psk_write` (chave
  truncada) e a confirmação de que o TLS funciona com a crypto-policy padrão do Fedora;
- pro **goodix-fp-linux-dev**: o dado de um 10062 pareado pelo Windows e ferramentas de
  leitura/pareamento que nunca chamam o caminho de erase/flash.

E outras distros? O driver é o mesmo. No **Arch/CachyOS/Omarchy** use o pacote do jith. No
**Ubuntu/Debian** não há pacote pronto; seria preciso compilar o fork (mesmas fontes e patches
de `rpm/`) e substituir o `libfprint-2-2` do sistema — possível, mas ninguém empacotou ainda.
A ferramenta de pareamento (`tools/`) é só Python + pyusb e funciona em qualquer distro.

## Segurança

Chave de pareamento pública (toda-zero): alguém com acesso físico ao USB pode se passar pelo
sensor. Sem detecção de dedo falso. Templates em `/var/lib/fprint` (só root). `sufficient`
no PAM significa que a digital **substitui** a senha onde estiver habilitada — avalie se isso
serve pra você.

## Créditos e licença

Driver e patches: [jith](https://github.com/jith/goodix-55a4-fingerprint),
[TheWeirdDev/libfprint](https://github.com/TheWeirdDev/libfprint) (fork 55b4-experimental),
[goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev). libfprint é LGPL-2.1-or-later.
Scripts e notas deste repositório: MIT, salvo indicação. Firmware não é redistribuído aqui.

*Palavras-chave: ThinkPad E14 Gen 1 leitor de digitais Linux, 20RA, 20RB, Goodix 27c6:55a4,
Goodix FingerPrint Device, fprintd No devices available, Invalid device PSK, libfprint
goodixtls, Fedora impressão digital, GF3208_RTSEC_APP_10062, Lenovo biometria Linux,
fingerprint reader Fedora.*
