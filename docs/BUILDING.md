# Construcción de la imagen ARM64 de validación

## Estado

Este procedimiento pertenece a la Fase 1. Construye una imagen Debian ARM64 para probar el arranque en QEMU. No produce todavía Morimil OS para un teléfono físico.

La construcción y el arranque completo todavía no han sido registrados como exitosos.

## Entorno admitido

La referencia inicial es un anfitrión Debian 13 `trixie`. Otros anfitriones pueden funcionar, pero no se considerarán reproducibles hasta que exista una ejecución registrada.

Paquetes requeridos:

```sh
sudo apt update
sudo apt install \
    ca-certificates \
    mmdebstrap \
    autopkgtest \
    qemu-system-arm \
    qemu-efi-aarch64 \
    qemu-utils \
    shellcheck
```

No se debe ejecutar un constructor descargado desde una fuente no verificada. Se utilizan paquetes distribuidos por Debian.

## Comprobar el repositorio

```sh
sh scripts/check-repository.sh
sh tests/shell/test-scripts.sh
```

La primera comprobación valida estructura, sintaxis y políticas. La segunda usa mocks para validar el contrato de los scripts. Ninguna construye ni arranca una imagen real.

## Seleccionar un snapshot

La construcción exige una marca temporal exacta de `snapshot.debian.org`, con formato:

```text
YYYYMMDDThhmmssZ
```

El archivo Debian puede resolver una hora solicitada hacia la última importación anterior. Por ello se debe registrar la marca solicitada y comprobar manualmente la marca efectiva antes de declarar una construcción reproducible.

También debe fijarse `SOURCE_DATE_EPOCH` como un entero Unix coherente con el estado del archivo usado.

## Construir

```sh
export DEBIAN_SNAPSHOT='YYYYMMDDThhmmssZ'
export SOURCE_DATE_EPOCH='UNIX_TIMESTAMP'
sh scripts/build-qemu-arm64.sh
```

Artefactos esperados:

```text
build/morimil-trixie-arm64.raw
build/morimil-trixie-arm64.raw.sha256
build/morimil-trixie-arm64.raw.metadata
```

La presencia de estos archivos solo demuestra que terminó la construcción. No demuestra que la imagen arranque.

El constructor crea la imagen temporal dentro de un directorio bajo `/tmp` y ajusta ese directorio a modo `0755`. Esto es deliberado: el manual de Debian exige que todos los componentes del camino sean atravesables por el usuario aislado que escribe la imagen.

Variables opcionales:

```text
BUILD_DIR       directorio de salida
OUTPUT_IMAGE    ruta completa de la imagen
IMAGE_SIZE      tamaño raw, 8G por defecto
DEBIAN_SUITE    trixie por defecto
FORCE           1 permite reemplazar artefactos existentes
```

Por defecto, el constructor se niega a reemplazar una imagen, checksum o metadata existentes.

## Arrancar en QEMU

```sh
sh scripts/run-qemu-arm64.sh
```

La prueba utiliza:

- `qemu-system-aarch64`;
- máquina genérica `virt`;
- CPU virtual AArch64 `cortex-a57`;
- aceleración TCG fija para la primera validación;
- firmware UEFI de `/usr/share/AAVMF/`;
- disco VirtIO;
- consola serie;
- red desactivada;
- modo snapshot para no escribir cambios persistentes en la imagen base.

Variables opcionales:

```text
IMAGE                    ruta de la imagen raw
MEMORY_MIB               memoria, 2048 por defecto
CPUS                     CPU virtuales, 2 por defecto
ALLOW_UNVERIFIED_IMAGE   1 permite una prueba explícitamente no verificada
```

El arranque falla por defecto si no existe el manifiesto SHA-256. KVM no está habilitado en esta fase; se añadirá únicamente después de una prueba específica sobre un anfitrión ARM64 compatible.

Salir de QEMU:

```text
Ctrl-a x
```

## Registrar la consola

En un anfitrión con `script(1)` se puede conservar la sesión completa:

```sh
script -qefc 'sh scripts/run-qemu-arm64.sh' build/boot.log
```

## Evidencia obligatoria

Una ejecución válida debe guardar:

```sh
mmdebstrap --version
qemu-system-aarch64 --version
dpkg-query -W mmdebstrap qemu-system-arm qemu-efi-aarch64
sha256sum -c build/morimil-trixie-arm64.raw.sha256
```

Además debe conservarse el registro completo de la consola, incluyendo:

- inicialización UEFI;
- carga del kernel;
- inicio de systemd;
- llegada a `multi-user.target`;
- apagado controlado.

Hasta que esa evidencia exista, la Fase 1 permanece **no validada**.

## Restricciones actuales

- El constructor usado está orientado a imágenes de prueba de Debian; no define la imagen final del producto.
- Todavía no se han definido particiones A/B, recuperación, raíz inmutable, cifrado ni actualizaciones atómicas.
- No se prueba hardware móvil.
- La red se mantiene desactivada para reducir variables durante la primera prueba de arranque.
- El workflow actual valida sintaxis, políticas y contratos mediante mocks, pero no una construcción real.
- KVM y cualquier optimización dependiente del anfitrión quedan fuera de esta primera prueba.

## Fuentes

- https://packages.debian.org/trixie/mmdebstrap
- https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap-autopkgtest-build-qemu.1.en.html
- https://www.qemu.org/docs/master/system/arm/virt.html
- https://packages.debian.org/trixie/qemu-efi-aarch64
- https://snapshot.debian.org/
