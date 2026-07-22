# Validación y evidencia

## Propósito

Este documento separa pruebas estáticas, contratos simulados y ejecución real. Ningún resultado debe presentarse como más fuerte de lo que demuestra.

## Matriz de estado

| Capacidad | Estado | Evidencia |
|---|---|---|
| Estructura del repositorio | Automatizada | workflow `Repository validation` |
| Sintaxis POSIX y Python | Automatizada | `sh -n` y `compile()` |
| ShellCheck | Automatizado | scripts y contratos shell |
| Construcción Debian ARM64 | Validada | ejecuciones reales y artefactos |
| Arranque UEFI, kernel y systemd | Validado | consola serie y `boot.log` |
| `multi-user.target` Debian | Validado | `MORIMIL_BOOT_PROOF` |
| Reproducibilidad Debian bit a bit | Validada | ejecuciones `29714518572` y `29715172215` |
| Autoridad Arch local | Validada | huella completa y SHA-256 |
| Rootfs Arch AArch64 fijado | Validado | firma, hashes, tamaño y lista |
| Bootstrap Arch real | Validado | ejecución `29880817129` |
| Runtime `systemd-nspawn` | Validado | ejecución `29888136765` |
| UID y red privados | Validados | mapas UID/GID y namespaces |
| Raíz `ro` y `/var` volátil | Validados | `findmnt` dentro del executor |
| Parada limpia | Validada | salida 0 de `systemd-nspawn` |
| Fallo forzado sin afectar Debian | Validado | host antes/después |
| Destrucción y reconstrucción | Validadas | dos generaciones del mismo pin |
| Ciclo operacional | Validado | ejecución `29890214148` |
| Perfil de límites declarativo | Automatizado | contratos de Fase 2F |
| Límites cgroup y `/var` | Validados | ejecución `29892193434` |
| Lista permitida de montajes | Pendiente | contrato explícito sin bind libre |
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
- contratos shell y pruebas Python;
- ausencia de imágenes y evidencia generada rastreada por Git;
- whitespace y parche del commit.

El workflow ejecuta:

```sh
for test_script in tests/shell/*.sh; do
    sh "$test_script"
done
python3 -m unittest discover -s tests/python -p 'test_*.py' -v
```

Las pruebas estáticas no descargan rootfs ni prueban un kernel, contenedor o cgroup real.

## Construcción Debian ARM64

La imagen usa Debian Snapshot y entradas fijadas. La ejecución real exige:

- UEFI;
- kernel ARM64;
- systemd como PID 1;
- `multi-user.target` activo;
- apagado controlado;
- inspección ext4 de solo lectura;
- checksums antes y después de inspección.

Las ejecuciones independientes `29714518572` y `29715172215` produjeron el mismo SHA-256 raw:

```text
1da5031ee0d1b322e30b7c08148856706fb3572f5c3fd15cdc86fd79d4c27983
```

También coincidieron:

```text
root_partition_sha256=04146ee6bd1abdc44805e58186bf964708991b7731d35ab8fa521b07202d9b82
tree_manifest_sha256=a50b78d883fb05cb93b4b9740402b5c9c22fc01598eb885566ba87ba45dca886
```

La afirmación de reproducibilidad se limita a la imagen raw y a las entradas fijadas; no cubre cambios posteriores de herramientas o fuentes.

## Rootfs Arch autenticado

El artefacto fijado contiene:

```text
fingerprint=68B3537F39A313B3E574D06777193F152BDBE6A6
signing_key_sha256=6ce771e853f04a38a5b533cb33e61f877b9b06b58b6db051eb8a15d737a2332f
rootfs_sha256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
rootfs_size=818293654
signature_sha256=17aca89a9de049651310f2a1ac730aea6d886ffe9c8de8c3009986938d145367
archive_entries=48789
archive_list_sha256=09534cd0ae6c2c808a2cb2586de692dce92a0e3c20072bdf0af062d846a42f7d
```

El bootstrap verifica:

1. SHA-256 de la clave local;
2. huella primaria completa;
3. firma con `gpgv`;
4. SHA-256 y SHA-512 del tarball;
5. tamaño exacto;
6. lista y número de entradas;
7. rutas seguras;
8. identidad Arch Linux ARM;
9. `pacman` ELF64 AArch64;
10. publicación atómica y rollback.

La ejecución `29880817129` extrajo `48792` entradas y `2098553789` bytes, y eliminó rootfs y estado al finalizar. No ejecutó `pacman`.

## Runtime Arch aislado

La ejecución ARM64 nativa `29888136765` validó el head `45ea2efeb847501840fe169c1f5703d253e97ec1`.

Demostró:

- dos bootstraps independientes del mismo rootfs fijado;
- dos arranques con systemd como PID 1;
- `morimil-executor.target` activo;
- `PrivateUsers=pick` y propietarios desplazados;
- namespace de red diferente al host;
- única interfaz `lo`;
- raíz de solo lectura;
- `/var` en `tmpfs`;
- `NoNewPrivileges=1`;
- rechazo de escritura sobre `/`;
- parada limpia;
- fallo forzado de PID 1 con salida no nula;
- continuidad del boot ID, red y archivo centinela de Debian;
- reconstrucción desde el mismo SHA-256;
- eliminación final de rootfs, estado, registro y política temporal.

El artefacto de evidencia tuvo digest:

```text
sha256:dde5245fde37efdde46efa67cc3bcfec94dd4f54c310c4cf9ddd27887da6a347
```

## Ciclo de vida operacional

La ejecución ARM64 nativa `29890214148` validó el código operacional del head `7e9a02e8259e5f408e77cc864096b613842330a3`.

Operaciones probadas:

```text
create
start
status
stop
destroy
rebuild
```

Resultados:

- `create` dejó el executor en estado `stopped`;
- dos llamadas a `start` alcanzaron systemd como PID 1 y `morimil-executor.target`;
- `status` reflejó correctamente `stopped`, `running` y `absent`;
- `stop` conservó el rootfs;
- `/var` usó `tmpfs` y el marcador volátil no persistió;
- `rebuild` dejó el executor detenido;
- ambas generaciones usaron el SHA-256 `3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a`;
- ambos ciclos usaron UID shift `479133696`;
- solo existió la interfaz `lo`;
- los namespaces de red fueron distintos del host;
- la raíz permaneció de solo lectura;
- `NoNewPrivileges=1` se mantuvo;
- `destroy` eliminó rootfs, metadata y política;
- Debian conservó boot ID, red y archivo centinela.

El artefacto contiene 44 archivos y tuvo digest:

```text
sha256:69123abf328f4778e77db3f0dfd368b0a9dec7b3e5f711c8afc966b3474955d5
```

## Límites de recursos

El perfil canónico de Fase 2F es:

```text
CPUQuota=100%
MemoryHigh=536870912
MemoryMax=805306368
MemorySwapMax=0
TasksMax=256
var_size_bytes=268435456
var_inodes=65536
```

Los contratos estáticos verifican:

- claves exactas y valores numéricos;
- relación `MemoryHigh <= MemoryMax`;
- swap desactivada;
- rangos máximos y mínimos;
- correspondencia exacta entre el archivo declarativo y `TemporaryFileSystem=/var`;
- presencia de `--keep-unit`, `Delegate=yes` y propiedades de cgroup;
- rechazo de evidencia alterada.

La ejecución AArch64 `29892193434` validó el head `66fa058a2aaa5692d1c2d7ae578cdce6e5a17b7e`.

Resultados observados:

```text
unit_cgroup=/system.slice/morimil-arch-resource-limits-ci.service
leader_cgroup=/system.slice/morimil-arch-resource-limits-ci.service/payload/init.scope
cpu.max=100000 100000
memory.high=536870912
memory.max=805306368
memory.swap.max=0
pids.max=256
var_fstype=tmpfs
var_size_bytes=268435456
var_inodes=65536
var_overflow_rejected=yes
```

La prueba confirmó:

1. cgroup v2 activo;
2. PID 1 de Arch contenido en la unidad limitada;
3. CPU equivalente a una CPU completa;
4. presión de memoria desde 512 MiB y límite duro de 768 MiB;
5. swap completamente desactivada;
6. máximo de 256 tareas;
7. `/var` limitado a 256 MiB y 65 536 inodos;
8. reserva superior al límite rechazada;
9. rootfs, estado, política, perfil y registro eliminados;
10. Debian sin cambios en boot ID, red, namespace y archivo centinela.

El perfil declarado tuvo SHA-256:

```text
3246d3497f9da39d5fc13523467cd95688042806c6a1ad0a2e7389563e57132a
```

El artefacto tuvo digest:

```text
morimil-arch-executor-resource-limits-29892193434
sha256:e51a51f81225dbf7e5fe1bc500cc358abf29bd7ea8e56cb3fe26905c63f2b086
```

Contratos:

```sh
sh tests/shell/test-arch-executor-resource-limits.sh
sh tests/shell/test-arch-executor-resource-limits-evidence.sh
```

Validación de evidencia:

```sh
sh scripts/check-arch-executor-resource-limits-evidence.sh \
  build/arch-executor-resource-limits/evidence
```

## Evidencia conservada

Los artefactos de CI conservan únicamente logs, estados, metadata, mapas de namespaces, archivos cgroup, opciones de montaje y checksums.

No se conservan:

- imagen raw Debian;
- tarball Arch;
- firma descargada;
- rootfs Arch extraído.

## Límites

QEMU `virt` y `systemd-nspawn` no representan un teléfono. Las validaciones actuales no demuestran pantalla táctil, batería, suspensión móvil, módem, cámara, sensores, GPU, audio, consumo energético ni compatibilidad de firmware.

La Fase 2F tampoco autoriza bind mounts ni datos persistentes. La lista permitida de montajes se definirá en un bloque separado antes de iniciar Morimil Core.
