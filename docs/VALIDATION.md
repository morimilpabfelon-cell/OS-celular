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
| Reproducibilidad bit a bit | No validada | dos SHA-256 raw idénticos |
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

Usan ejecutables simulados para verificar:

- opciones EFI, ARM64, snapshot y script de personalización;
- transporte HTTP hacia Debian Snapshot con verificación de Release firmada;
- permisos `0755` del directorio temporal;
- checksum y metadata;
- rechazo de sobrescritura accidental;
- aislamiento de QEMU y red desactivada;
- validación de recursos y firmware;
- normalización determinista de identificadores GPT;
- huellas separadas de regiones de la imagen;
- instalación segura de la instrumentación de arranque;
- aceptación y rechazo correctos del verificador de logs;
- creación del dispositivo loop ext4 en modo de solo lectura;
- montaje ext4 con `ro,noload,nodev,nosuid,noexec`;
- detección de cualquier mutación de la imagen durante la inspección.

No descargan paquetes ni prueban un kernel.

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

## Prueba real de arranque

La imagen de validación instala un timer de systemd. Cuando se activa, el servicio comprueba:

```sh
systemctl is-active --quiet multi-user.target
```

Solo después imprime en `/dev/console`:

```text
MORIMIL_BOOT_PROOF target=multi-user.target state=active
```

El verificador exige esa marca exacta y rechaza tanto su ausencia como `MORIMIL_BOOT_PROOF_FAILED`.

## Diagnóstico regional de la imagen

`scripts/fingerprint-qemu-image.sh` lee la tabla mediante `sfdisk --dump` y calcula SHA-256 independientes de:

- subregiones del MBR;
- GPT primaria;
- partición EFI;
- espacio entre particiones;
- partición ext4 raíz;
- GPT de respaldo;
- imagen raw completa.

Dos ejecuciones reales demostraron que MBR, GPT, EFI y espacios externos a la raíz son idénticos. La diferencia pendiente está confinada a la partición ext4 raíz.

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

## Evidencia conservada

Una ejecución real debe conservar:

```text
build/
├── build.log
├── boot.log
├── ci.log
├── container-image.txt
├── environment.txt
├── ext4-groups.txt
├── ext4-inspection-environment.txt
├── ext4-inspection-status.txt
├── ext4-superblock.txt
├── ext4-tree.jsonl
├── ext4-tree.sha256
├── guest-apt-sources.sources
├── guest-apt-sources.sha256
├── image-regions.txt
├── mmdebstrap-helper-preflight.txt
├── mmdebstrap-helper.sha256
├── morimil-trixie-arm64.raw.identifiers
├── morimil-trixie-arm64.raw.metadata
├── morimil-trixie-arm64.raw.sha256
└── validation-status.txt
```

La imagen raw no se sube a Git ni a los artefactos de CI. El checksum permite identificarla sin consumir almacenamiento innecesario.

## Reproducibilidad

Solo se compararán dos construcciones cuando coincidan:

- commit;
- snapshot solicitado;
- `SOURCE_DATE_EPOCH`;
- digest del contenedor;
- versiones de herramientas;
- fuentes APT y su SHA-256;
- script de personalización y su SHA-256;
- tamaño y opciones de imagen;
- identificadores GPT derivados.

La igualdad exacta de SHA-256 es obligatoria. Un build exitoso demuestra construcción y arranque. Dos árboles de archivos iguales tampoco bastan si la representación ext4 raw difiere.

## Límites

QEMU `virt` no representa un teléfono. Incluso una ejecución completamente verde no demuestra pantalla táctil, batería, suspensión móvil, módem, cámara, sensores, GPU ni consumo energético.
