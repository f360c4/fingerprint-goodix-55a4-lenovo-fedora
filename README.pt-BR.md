# Leitor de digitais Goodix 27c6:55a4 no Fedora (ThinkPad E14 Gen 1)

Como fazer o leitor Goodix `27c6:55a4` do ThinkPad E14 Gen 1 (machine types 20RA / 20RB)
funcionar no Fedora: `sudo`, desbloqueio de tela e, se quiser, login — tudo com digital.

Testado em: ThinkPad E14 Gen 1 **20RB002BBR**, Fedora 44 KDE, kernel 7.2, OpenSSL 3.5,
OpenCV 4.13, 2026-10-08. Trabalho de base: [jith/goodix-55a4-fingerprint](https://github.com/jith/goodix-55a4-fingerprint)
(driver, testado em CachyOS num 20RA) e [goodix-fp-linux-dev](https://github.com/goodix-fp-linux-dev/goodix-fp-dump)
(protocolo). Aqui está o empacotamento pro Fedora, uma ferramenta de pareamento **que não
mexe no firmware**, e as notas do que foi medido.

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
git clone https://github.com/<seu-usuario>/goodix-55a4-fedora && cd goodix-55a4-fedora
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

(Quando houver COPR: `sudo dnf copr enable <usuario>/libfprint-goodixtls-55a4 && sudo dnf swap libfprint libfprint-goodixtls-55a4`.)

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

## SELinux

Ao iniciar, o OpenCV lê `/proc/sys/vm/nr_hugepages` e o SELinux nega (inofensivo, só gera
alerta). Pra silenciar: `sudo dnf install selinux-policy-devel && sudo selinux/install.sh`.

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
