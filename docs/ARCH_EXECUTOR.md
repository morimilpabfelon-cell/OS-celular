# Arch Executor

## Estado

Las Fases 2A–2E están validadas. Existe evidencia AArch64 nativa de que el rootfs autenticado arranca con systemd como PID 1 dentro de `systemd-nspawn`, usa UID y red privados, conserva la raíz en solo lectura y puede fallar, detenerse, destruirse y reconstruirse sin afectar Debian.

La Fase 2F incorpora límites explícitos de CPU, memoria, swap, tareas y almacenamiento volátil. Su aplicación real permanece en validación hasta completar el job AArch64 dedicado.

## Frontera de aislamiento

La configuración canónica es:

```text
config/nspawn/morimil-arch.nspawn
```

La política exige:

- arranque mediante el init del contenedor;
- espacio privado de UID y GID;
- prohibición de adquirir nuevos privilegios;
- raíz de solo lectura;
- `/var` temporal y limitado;
- espacio de red privado;
- ninguna interfaz virtual por defecto;
- ningún bind mount del anfitrión;
- ninguna capacidad adicional;
- ningún puerto ni interfaz física expuestos.

La política se comprueba con:

```sh
sh scripts/check-arch-executor-policy.sh \
  config/nspawn/morimil-arch.nspawn \
  config/arch-executor-resource-limits.env
```

## Rootfs autenticado y fijado

Los valores aprobados están en:

```text
config/arch-rootfs-release.env
config/keys/archlinuxarm-build-system.asc
```

El bootstrap:

- usa HTTPS para el tarball y la firma;
- fija la huella completa `68B3537F39A313B3E574D06777193F152BDBE6A6`;
- verifica el SHA-256 de la clave local;
- verifica la firma con `gpgv`, sin keyserver ni agente;
- exige SHA-256, SHA-512, tamaño y estructura exactos;
- rechaza rutas absolutas o traversal dentro del archivo;
- extrae como root para preservar propietarios, ACL y xattrs;
- publica mediante renombrado atómico;
- conserva metadata dentro y fuera del rootfs;
- no inicia el contenedor.

## Runtime validado

La ejecución `29888136765` completó:

1. dos bootstraps independientes del mismo pin;
2. dos arranques con systemd como PID 1;
3. target mínimo `morimil-executor.target`;
4. `PrivateUsers=pick` con propietarios previamente desplazados;
5. namespace de red separado con únicamente `lo`;
6. raíz de solo lectura;
7. `/var` en `tmpfs`;
8. `NoNewPrivileges=1`;
9. parada limpia;
10. fallo forzado de PID 1 sin afectar Debian;
11. destrucción y reconstrucción;
12. eliminación final del rootfs, estado y política temporal.

## Interfaz operacional

La herramienta es:

```sh
sudo sh scripts/morimil-arch-executor.sh COMMAND
```

### `create`

Descarga, autentica y publica el rootfs fijado. Después instala el target mínimo, enmascara servicios de red no permitidos, desplaza propietarios para `PrivateUsers=pick` e instala copias exactas de la política y del perfil de límites.

No arranca Arch.

### `start`

Inicia el executor mediante una unidad transitoria de systemd y exige la política instalada en modo `trusted`.

Debian aplica:

```text
CPUQuota=100%
MemoryHigh=536870912
MemoryMax=805306368
MemorySwapMax=0
TasksMax=256
```

`systemd-nspawn` usa `--keep-unit`, por lo que el payload permanece dentro del cgroup limitado. `Delegate=yes` permite que systemd dentro de Arch administre subcgroups sin escapar de la unidad padre.

El comando solo termina correctamente cuando `morimil-executor.target` y el archivo de readiness están activos.

### `status`

Devuelve pares `clave=valor`:

```text
machine=morimil-arch
created=yes
running=no
state=stopped
leader=
rootfs_sha256=...
uid_shift=...
resource_limits_sha256=...
cpu_quota_percent=100
memory_high_bytes=536870912
memory_max_bytes=805306368
memory_swap_max_bytes=0
tasks_max=256
var_size_bytes=268435456
var_inodes=65536
```

Estados válidos:

- `absent`;
- `stopped`;
- `running`;
- `inconsistent`.

### `stop`

Solicita apagado mediante `machinectl poweroff`, espera la desaparición del registro y conserva rootfs, metadata, política y perfil de límites.

### `destroy`

Solo opera con el executor detenido. Elimina rootfs, metadata, política instalada y perfil de límites instalado.

Se niega a borrar una política o un perfil de límites que no coincida con la versión del repositorio.

### `rebuild`

Ejecuta `stop`, `destroy` y `create`. Descarga de nuevo el artefacto fijado y deja el executor detenido.

## Límites declarados

El archivo canónico es:

```text
config/arch-executor-resource-limits.env
```

Se valida mediante:

```sh
sh scripts/check-arch-executor-resource-limits.sh
```

El almacenamiento escribible de estado se limita con:

```text
TemporaryFileSystem=/var:mode=0755,nodev,nosuid,size=268435456,nr_inodes=65536
```

La raíz permanece en solo lectura. No existe almacenamiento persistente de Arch fuera del rootfs autenticado y de metadata controlada por Debian.

## Rutas predeterminadas

```text
/etc/systemd/nspawn/morimil-arch.nspawn
/etc/morimil/arch-executor-resource-limits.env
/var/lib/machines/morimil-arch/
/var/lib/morimil/executors/arch/
/run/lock/morimil-arch-executor.lock
```

El rootfs se mantiene separado de su metadata. Ninguna ruta de Arch puede convertirse en raíz de Debian ni ser administrada por `apt`.

## Pruebas

Contratos estáticos:

```sh
sh tests/shell/test-arch-executor-lifecycle.sh
sh tests/shell/test-arch-executor-lifecycle-evidence.sh
sh tests/shell/test-arch-executor-resource-limits.sh
sh tests/shell/test-arch-executor-resource-limits-evidence.sh
```

Validación de evidencia:

```sh
sh scripts/check-arch-executor-lifecycle-evidence.sh \
  build/arch-executor-lifecycle/evidence
sh scripts/check-arch-executor-resource-limits-evidence.sh \
  build/arch-executor-resource-limits/evidence
```

La ejecución real requiere un host AArch64 nativo con systemd, cgroup v2 y `systemd-container`.

## Fuera de alcance actual

- lista permitida de montajes de datos;
- límites de I/O por dispositivo;
- perfiles dinámicos según batería o temperatura;
- acceso a GPU, módem, cámara, batería, sensores o audio;
- red del anfitrión o interfaces `veth`;
- integración de aplicaciones gráficas;
- actualización automática mediante `pacman`;
- compatibilidad con teléfono físico.
