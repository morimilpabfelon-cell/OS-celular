# Construcción de la imagen ARM64 de validación

## Estado

Este procedimiento pertenece a la Fase 1. Construye una imagen Debian ARM64 para validar arranque UEFI, kernel y `multi-user.target` en QEMU `virt`.

No produce todavía Morimil OS para un teléfono físico. Una ejecución en QEMU no demuestra compatibilidad con pantalla táctil, batería, módem, cámara, sensores o GPU móvil.

## Entradas fijadas

Una construcción declarada reproducible debe fijar:

- versión de Debian y arquitectura `arm64`;
- marca temporal exacta de `snapshot.debian.org`;
- `SOURCE_DATE_EPOCH`;
- versión de `mmdebstrap` y QEMU;
- script de personalización y su SHA-256;
- fuentes APT del invitado y su SHA-256;
- tamaño de imagen y opciones de construcción.

El constructor rechaza referencias como `latest`: `DEBIAN_SNAPSHOT` debe usar `YYYYMMDDThhmmssZ`.

## Dependencias del anfitrión Debian 13

```sh
sudo apt update
sudo apt install \
    arch-test \
    autopkgtest \
    binutils-multiarch \
    ca-certificates \
    dosfstools \
    dpkg-dev \
    e2fsprogs \
    fdisk \
    gpg \
    libarchive13t64 \
    mmdebstrap \
    mount \
    mtools \
    passwd \
    qemu-efi-aarch64 \
    qemu-system-arm \
    qemu-user-binfmt \
    qemu-utils \
    systemd-boot-efi:arm64 \
    uidmap \
    uuid-runtime
```

`uuid-runtime` aporta `uuidgen`; `dpkg-dev` aporta `dpkg-architecture` y `dpkg-checkbuilddeps`; `binutils-multiarch` aporta utilidades binarias multi-arquitectura; `e2fsprogs` aporta las herramientas ext4 usadas por el constructor.

Para una construcción cruzada `amd64` → `arm64`, Debian 13 instala la regla oficial en:

```text
/usr/lib/binfmt.d/qemu-aarch64.conf
```

En un sistema arrancado con systemd, `systemd-binfmt` procesa esa regla. El controlador de CI trabaja dentro de un contenedor privilegiado sin systemd: monta `binfmt_misc`, registra exclusivamente esa regla oficial y exige que:

```sh
arch-test arm64
```

termine correctamente antes de iniciar `mmdebstrap`.

## Fuentes APT fijadas

La construcción usa Debian Snapshot mediante HTTP. HTTP se utiliza únicamente como transporte; APT sigue verificando la firma de los archivos Release mediante el keyring oficial de Debian.

El transporte HTTP evita depender de certificados dentro del chroot antes de que `setup-testbed` haya terminado de configurar el sistema. No se desactiva la autenticación de paquetes ni se usan repositorios sin firma.

El controlador entrega a autopkgtest una configuración deb822 exacta mediante `AUTOPKGTEST_APT_SOURCES`. Incluye exclusivamente:

```text
http://snapshot.debian.org/archive/debian/<TIMESTAMP>/ trixie
http://snapshot.debian.org/archive/debian-security/<TIMESTAMP>/ trixie-security
```

Ambas entradas usan:

```text
Check-Valid-Until: no
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
```

Esto evita que `setup-testbed` añada silenciosamente `security.debian.org` en vivo. La configuración se conserva en:

```text
build/guest-apt-sources.sources
build/guest-apt-sources.sha256
```

## Validar scripts antes de construir

```sh
sh scripts/check-repository.sh
sh tests/shell/test-scripts.sh
sh tests/shell/test-boot-proof.sh
```

Estas pruebas usan mocks. Comprueban contratos y argumentos, pero no descargan Debian ni arrancan una VM real.

## Construir

```sh
export DEBIAN_SNAPSHOT='20260718T000000Z'
export SOURCE_DATE_EPOCH='1784332800'
export IMAGE_SIZE='4G'
sh scripts/build-qemu-arm64.sh
```

Artefactos esperados:

```text
build/morimil-trixie-arm64.raw
build/morimil-trixie-arm64.raw.sha256
build/morimil-trixie-arm64.raw.metadata
```

El constructor utiliza `mmdebstrap-autopkgtest-build-qemu` con:

- `--boot=efi`;
- `--arch=arm64`;
- mirror fechado de Debian Snapshot;
- tamaño explícito;
- `scripts/configure-validation-image.sh` mediante `--script`.

El script de personalización instala dentro de la imagen una prueba temporal. Tras activarse `multi-user.target`, un timer comprueba que el target esté activo, escribe en la consola:

```text
MORIMIL_BOOT_PROOF target=multi-user.target state=active
```

y solicita un apagado controlado. Esta instrumentación pertenece únicamente a la imagen de validación y no define el comportamiento del producto final.

Por defecto, el constructor se niega a reemplazar una imagen, checksum o metadata existentes. Para una reconstrucción deliberada:

```sh
FORCE=1 sh scripts/build-qemu-arm64.sh
```

## Arrancar en QEMU

```sh
sh scripts/run-qemu-arm64.sh > build/boot.log 2>&1
sh scripts/verify-boot-log.sh build/boot.log
```

La prueba utiliza:

- `qemu-system-aarch64`;
- máquina `virt`;
- CPU AArch64 `cortex-a57`;
- aceleración TCG;
- firmware UEFI AAVMF de Debian;
- disco VirtIO;
- consola serie mediante `-nographic`;
- red desactivada;
- modo snapshot para no modificar persistentemente la imagen.

El lanzador exige el manifiesto SHA-256 antes de arrancar. `ALLOW_UNVERIFIED_IMAGE=1` existe solo para diagnósticos explícitos y no es aceptable como evidencia.

## Criterio de éxito

Una ejecución aprobada requiere conjuntamente:

1. el constructor termina con código 0;
2. el checksum de la imagen es válido;
3. QEMU inicia mediante UEFI;
4. el kernel ARM64 y systemd arrancan;
5. el log contiene la marca exacta de `multi-user.target` activo;
6. la VM se apaga y QEMU termina con código 0;
7. se conservan versiones, fuentes APT, logs, checksum y metadata.

La existencia de un archivo `.raw`, una captura o un login visible no es evidencia suficiente por sí sola.

## Construcción real en GitHub Actions

El workflow `Repository validation` contiene un job `Debian 13 ARM64 real build and boot`. Se ejecuta:

- manualmente mediante `workflow_dispatch`; o
- en un pull request cuyo cuerpo incluya exactamente:

```text
<!-- run-arm64-build -->
```

El job utiliza la imagen oficial fechada `debian:trixie-20260623`, registra su digest real, cambia APT al snapshot fijado, instala herramientas desde ese snapshot y ejecuta la construcción y el arranque con TCG.

Antes de construir, el job conserva la huella SHA-256 del helper oficial, un extracto de su prevalidación de dependencias y el archivo exacto de fuentes APT del invitado.

El contenedor se ejecuta con privilegios porque la construcción cruzada necesita `binfmt_misc` y operaciones de imagen. Para reducir superficie:

- no recibe secretos;
- el repositorio se monta de solo lectura;
- únicamente `build/` se monta con escritura;
- la red de la VM QEMU permanece desactivada;
- el archivo raw no se publica como artefacto.

Se conservan durante siete días:

```text
build.log
boot.log
ci.log
container-image.txt
environment.txt
guest-apt-sources.sources
guest-apt-sources.sha256
mmdebstrap-helper-preflight.txt
mmdebstrap-helper.sha256
morimil-trixie-arm64.raw.metadata
morimil-trixie-arm64.raw.sha256
validation-status.txt
```

## Fuentes primarias

- https://packages.debian.org/trixie/mmdebstrap
- https://sources.debian.org/src/mmdebstrap/1.5.7-1%2Bdeb13u1/debian/control
- https://packages.debian.org/trixie/uuid-runtime
- https://packages.debian.org/trixie/dpkg-dev
- https://packages.debian.org/trixie/binutils-multiarch
- https://packages.debian.org/trixie/e2fsprogs
- https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap-autopkgtest-build-qemu.1.en.html
- https://manpages.debian.org/trixie/autopkgtest/autopkgtest-build-qemu.1.en.html
- https://manpages.debian.org/trixie/apt/sources.list.5.en.html
- https://snapshot.debian.org/
- https://www.qemu.org/docs/master/system/arm/virt.html
- https://packages.debian.org/trixie/qemu-efi-aarch64
- https://docs.github.com/en/actions/tutorials/store-and-share-data
