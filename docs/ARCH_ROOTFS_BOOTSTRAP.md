# Bootstrap del rootfs Arch Linux ARM

## Estado

La adquisición autenticada, validación del archivo, publicación atómica e inspección real del rootfs AArch64 están validadas. Este bloque no inicia `systemd-nspawn` ni demuestra todavía aislamiento en tiempo de ejecución.

## Artefacto y autoridad fijados

La configuración canónica es:

```text
config/arch-rootfs-release.env
```

La clave pública exacta, verificada por huella y checksum, se conserva en:

```text
config/keys/archlinuxarm-build-system.asc
```

Huella primaria:

```text
68B3537F39A313B3E574D06777193F152BDBE6A6
```

SHA-256 de la clave local:

```text
6ce771e853f04a38a5b533cb33e61f877b9b06b58b6db051eb8a15d737a2332f
```

Rootfs aceptado:

```text
URL=https://mirror.math.princeton.edu/pub/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz
SHA-256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
size=818293654
archive_entries=48789
```

El nombre `latest` continúa siendo mutable. Morimil no confía en ese nombre: exige que firma, SHA-256, SHA-512, tamaño, checksum de la firma, número de entradas y checksum de la lista coincidan con el pin versionado.

## Ejecución

```sh
sudo sh scripts/bootstrap-arch-rootfs.sh
```

Las rutas predeterminadas son:

```text
/var/lib/machines/morimil-arch
/var/lib/morimil/executors/arch/rootfs-source.env
```

El script rechaza destinos o metadata ya existentes. Una actualización del rootfs requiere descubrir y aprobar explícitamente un nuevo artefacto.

## Flujo de seguridad

El script realiza, en orden:

1. valida el archivo de pin, URLs, digests y rutas;
2. compara el SHA-256 de la clave pública local;
3. obtiene su huella mediante `gpg --show-keys`;
4. crea un keyring temporal y verifica la firma con `gpgv`;
5. compara SHA-256 y SHA-512 del rootfs;
6. compara tamaño, checksum de la firma, número de entradas y checksum de la lista;
7. rechaza rutas absolutas y traversal dentro del tarball;
8. extrae en un directorio temporal del mismo filesystem;
9. comprueba `ID=archarm` y `pacman` ejecutable;
10. escribe metadata de procedencia dentro y fuera del rootfs;
11. publica mediante renombrado atómico.

El bootstrap privilegiado no usa keyserver, `dirmngr` ni `gpg-agent`.

## Validación real

La ejecución `29880817129`, sobre el commit `864cd5b97869b6da924b17f71dce564140eb24fe`, completó:

- segunda descarga independiente del artefacto fijado;
- firma válida mediante la clave local y `gpgv`;
- coincidencia exacta de todos los valores versionados;
- extracción de `48792` entradas de filesystem;
- tamaño extraído de `2098553789` bytes;
- `os-release` con `ID=archarm`;
- `/usr/bin/pacman` identificado como ELF64 AArch64;
- publicación atómica;
- metadata interna y externa;
- eliminación completa del rootfs y del estado.

La evidencia contiene:

```text
bootstrap.log
cleanup-status.txt
environment.txt
os-release
pacman-elf-header.txt
pacman-file.txt
pin.env
rootfs-inspection.txt
rootfs-source.env
signing-key.asc
validation-status.txt
```

La imagen extraída no se conserva como artefacto de CI.

## Validación contractual

```sh
sh tests/shell/test-arch-rootfs-pin.sh
sh tests/shell/test-arch-rootfs-bootstrap.sh
sh tests/shell/test-arch-rootfs-release-evidence.sh
python3 -m unittest tests/python/test_validate_rootfs_archive.py -v
```

Las pruebas negativas rechazan:

- clave local ausente o con checksum distinto;
- huella incorrecta;
- fallo de `gpgv`;
- transporte HTTP;
- firma o digests distintos;
- tamaño o estructura diferentes;
- destinos fuera de las raíces permitidas;
- publicación parcial después de un fallo.

## Sobrescritura y reconstrucción

El script no actualiza ni destruye automáticamente un ejecutor previo. La destrucción y reconstrucción serán operaciones explícitas y separadas. La ejecución real de validación sí eliminó su rootfs temporal después de inspeccionarlo.

## Límites

- no configura contraseñas ni usuarios;
- no ejecuta `pacman`;
- no habilita red dentro del ejecutor;
- no instala la definición `.nspawn` en el anfitrión;
- no inicia el contenedor;
- no expone GPU, audio, módem, cámara, sensores ni almacenamiento personal;
- no demuestra compatibilidad con un teléfono físico.
