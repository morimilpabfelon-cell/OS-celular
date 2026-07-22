# Validación y evidencia

## Propósito

Este documento separa pruebas estáticas, contratos simulados y ejecución real. Ninguna prueba debe presentarse como más fuerte de lo que demuestra.

## Matriz de estado

| Capacidad | Estado | Evidencia exigida |
|---|---|---|
| Estructura del repositorio | Automatizada | workflow `Repository validation` |
| Sintaxis POSIX | Automatizada | `sh -n` |
| Sintaxis Python | Automatizada | `compile()` sin generar bytecode |
| Análisis de shell | Automatizado | ShellCheck |
| Contratos del constructor y QEMU | Automatizados con mocks | `tests/shell/*.sh` |
| Manifiesto del árbol ext4 | Automatizado con prueba unitaria | `tests/python/*.py` |
| Fuentes APT del invitado fijadas | Automatizada | archivo deb822 y SHA-256 |
| Construcción Debian ARM64 real | Validada | `build.log`, checksum y metadata |
| Arranque UEFI real | Validado | `boot.log` |
| Kernel y systemd | Validados | consola serie |
| `multi-user.target` activo | Validado | marca `MORIMIL_BOOT_PROOF` |
| Apagado controlado | Validado | salida 0 de QEMU |
| Identificadores GPT deterministas | Validado | manifiesto `.identifiers` |
| Localización regional de entropía | Validada | `image-regions.txt` |
| Reproducibilidad bit a bit | Validada | ejecuciones `29714518572` y `29715172215` |
| Autoridad Arch local fijada | Validada | huella completa y SHA-256 de `signing-key.asc` |
| Rootfs Arch AArch64 fijado | Validado | firma, SHA-256, SHA-512, tamaño y lista |
| Bootstrap Arch real | Validado | ejecución `29880817129` |
| `pacman` ELF AArch64 | Validado | `file` y `readelf -h` |
| Eliminación del rootfs de prueba | Validada | `cleanup-status.txt` |
| Arranque `systemd-nspawn` | No iniciado | log y estado del contenedor |
| Soporte de teléfono físico | No iniciado | matriz por componente |

## Pruebas estáticas

```sh
sh scripts/check-repository.sh
```

Comprueban:

- archivos obligatorios;
- sintaxis POSIX;
- sintaxis Python;
- ShellCheck cuando está disponible;
- ausencia de imágenes y evidencia generada rastreada por Git;
- whitespace y parche del commit.

El workflow ejecuta además:

```sh
python3 -m unittest discover -s tests/python -p 'test_*.py' -v
```

## Pruebas contractuales

```sh
for test_script in tests/shell/*.sh; do
    sh "$test_script"
done
```

Usan ejecutables simulados o raíces temporales para verificar:

- opciones EFI, ARM64, snapshot y script de personalización;
- transporte HTTP hacia Debian Snapshot con verificación de Release firmada;
- permisos `0755` del directorio temporal;
- checksum y metadata;
- rechazo de sobrescritura accidental;
- aislamiento de QEMU y red desactivada;
- validación de recursos y firmware;
- normalización determinista de identificadores GPT;
- huellas separadas de regiones de la imagen;
- sustitución determinista de `/etc/resolv.conf` heredado;
- instalación segura de la instrumentación de arranque;
- aceptación y rechazo correctos del verificador de logs;
- creación del dispositivo loop ext4 en modo de solo lectura;
- montaje ext4 con `ro,noload,nodev,nosuid,noexec`;
- detección de cualquier mutación de la imagen durante la inspección;
- rechazo de una clave Arch ausente, mutada o con huella incorrecta;
- rechazo de firma, SHA-256, SHA-512, tamaño o lista Arch distintos;
- rollback del bootstrap sin publicación parcial.

Las pruebas contractuales no descargan paquetes ni prueban un kernel o un contenedor real.

## Control de fuentes APT

La ejecución real entrega a autopkgtest dos fuentes deb822 fijadas al mismo timestamp solicitado:

- archivo principal `debian`;
- archivo de seguridad `debian-security`.

No se permite que `setup-testbed` introduzca `security.debian.org` ni otro repositorio vivo. La configuración usa `Check-Valid-Until: no` porque Debian Snapshot es un archivo histórico, pero mantiene `Signed-By` con el keyring oficial.

La evidencia incluye el contenido exacto y su SHA-256:

```text
build/guest-apt-sources.sources
build/guest-apt-sources.sha256
```

## Prueba real de arranque Debian

La imagen de validación instala un timer de systemd. Cuando se activa, un servicio comprueba:

```sh
systemctl is-active --quiet multi-user.target
```

Solo después imprime en `/dev/console`:

```text
MORIMIL_BOOT_PROOF target=multi-user.target state=active
```

El verificador exige esa marca exacta y rechaza tanto su ausencia como `MORIMIL_BOOT_PROOF_FAILED`.

## Diagnóstico regional de la imagen Debian

`scripts/fingerprint-qemu-image.sh` lee la tabla mediante `sfdisk --dump` y calcula SHA-256 independientes de:

- subregiones del MBR;
- GPT primaria;
- partición EFI;
- espacio entre particiones;
- partición ext4 raíz;
- GPT de respaldo;
- imagen raw completa.

Las primeras comparaciones demostraron que MBR, GPT, EFI y espacios externos a la raíz eran idénticos. La inspección del árbol ext4 redujo la única diferencia a `/etc/resolv.conf`, copiado por `mmdebstrap` desde el contenedor anfitrión. `scripts/configure-validation-image.sh` sustituye ahora cualquier archivo o enlace heredado por un archivo regular `0644` con contenido exacto y estable.

## Inspección ext4 de solo lectura

`scripts/inspect-ext4-root.sh` limita un dispositivo loop exactamente al desplazamiento y tamaño de la segunda partición mediante `--offset` y `--sizelimit`. Exige que el loop reporte `RO=1` y monta con:

```text
ro,noload,nodev,nosuid,noexec
```

La inspección conserva:

- cabecera del superblock mediante `dumpe2fs -h`;
- distribución de grupos mediante `dumpe2fs -g`;
- manifiesto JSON Lines del árbol;
- checksum del manifiesto;
- entorno de herramientas;
- SHA-256 de la imagen antes y después.

El manifiesto registra de forma ordenada rutas, tipos, modos, propietarios, tamaños, inodos, enlaces, bloques, tiempos, xattrs, destinos de enlaces y SHA-256 del contenido regular. Los nombres de ruta y xattr también se conservan en Base64 para no perder bytes no UTF-8.

El inspector falla si la imagen cambia durante el proceso. Esta inspección identifica diferencias; no normaliza ni reescribe ext4.

## Reproducibilidad Debian validada

Solo se comparan construcciones cuando coinciden:

- commit de construcción;
- snapshot solicitado;
- `SOURCE_DATE_EPOCH`;
- digest del contenedor;
- versiones de herramientas;
- fuentes APT y su SHA-256;
- script de personalización y su SHA-256;
- tamaño y opciones de imagen;
- identificadores GPT derivados.

Las ejecuciones independientes `29714518572` y `29715172215`, ambas sobre el commit de construcción `50d40bc11f88b3e9c93ac7ed8ac1eac23a2fe221`, produjeron imágenes raw con el mismo SHA-256 completo:

```text
1da5031ee0d1b322e30b7c08148856706fb3572f5c3fd15cdc86fd79d4c27983
```

También coincidieron exactamente `image-regions.txt`, los identificadores GPT, la metadata del constructor, el superblock ext4, los descriptores de grupos y el manifiesto de `27157` entradas:

```text
root_partition_sha256=04146ee6bd1abdc44805e58186bf964708991b7731d35ab8fa521b07202d9b82
tree_manifest_sha256=a50b78d883fb05cb93b4b9740402b5c9c22fc01598eb885566ba87ba45dca886
```

Los ZIP de evidencia no tienen que ser idénticos porque contienen logs y envoltorios específicos de cada ejecución. La afirmación de reproducibilidad se limita a la imagen raw y a las entradas fijadas descritas aquí; no implica reproducibilidad automática después de cambiar esas entradas.

## Descubrimiento autenticado del rootfs Arch

La ejecución `29880034099` descargó el rootfs y la firma como usuario sin privilegios, importó la autoridad mediante HKPS y comprobó:

```text
fingerprint=68B3537F39A313B3E574D06777193F152BDBE6A6
signing_key_sha256=6ce771e853f04a38a5b533cb33e61f877b9b06b58b6db051eb8a15d737a2332f
rootfs_sha256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
rootfs_size=818293654
signature_sha256=17aca89a9de049651310f2a1ac730aea6d886ffe9c8de8c3009986938d145367
archive_entries=48789
archive_list_sha256=09534cd0ae6c2c808a2cb2586de692dce92a0e3c20072bdf0af062d846a42f7d
```

La clave exportada fue inspeccionada nuevamente mediante `gpg --show-keys` antes de versionarse.

## Bootstrap real del rootfs Arch

La ejecución independiente `29880817129`, sobre el commit `864cd5b97869b6da924b17f71dce564140eb24fe`, utilizó exclusivamente la clave local fijada. No utilizó keyserver, `dirmngr` ni `gpg-agent`.

El trabajo completó:

1. descarga de rootfs y firma;
2. comprobación del SHA-256 de la clave local;
3. comprobación de la huella primaria;
4. verificación de firma mediante `gpgv`;
5. coincidencia de SHA-256, SHA-512, tamaño y estructura;
6. extracción con propietarios, ACL y xattrs;
7. publicación atómica;
8. inspección de identidad y arquitectura;
9. metadata interna y externa;
10. eliminación de rootfs y estado.

Resultados observados:

```text
rootfs_filesystem_entries=48792
rootfs_extracted_bytes=2098553789
pacman_elf_class=ELF64
pacman_elf_machine=AArch64
rootfs_removed=yes
state_removed=yes
MORIMIL_ARCH_ROOTFS_BOOTSTRAP_VALIDATED=yes
```

La ejecución no inició `systemd-nspawn` ni ejecutó `pacman`.

## Evidencia conservada

La validación Debian conserva logs, metadata, fuentes, manifiestos y checksums bajo `build/`; la imagen raw no se sube.

La validación Arch conserva:

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

El tarball Arch, su firma descargada y el rootfs extraído no se conservan en Git ni en los artefactos de CI.

## Límites

QEMU `virt` no representa un teléfono. Incluso una ejecución completamente verde no demuestra pantalla táctil, batería, suspensión móvil, módem, cámara, sensores, GPU ni consumo energético.

La validación Arch demuestra adquisición, autenticidad, extracción, arquitectura, publicación y limpieza. No demuestra arranque de systemd dentro de `systemd-nspawn`, límites de recursos, aislamiento efectivo en ejecución ni recuperación ante un contenedor activo defectuoso.
