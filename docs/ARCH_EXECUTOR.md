# Arch Executor

## Estado

Las Fases 2A–2F están validadas. Existe evidencia AArch64 nativa de que el rootfs autenticado arranca con systemd como PID 1 dentro de `systemd-nspawn`, usa UID y red privados, conserva la raíz en solo lectura, respeta límites cgroup y de almacenamiento, y puede fallar, detenerse, destruirse y reconstruirse sin afectar Debian.

Solo queda definir una lista permitida explícita para futuros montajes de datos antes de iniciar Morimil Core.

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

## Límites validados

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

La ejecución AArch64 `29892193434`, sobre el head `66fa058a2aaa5692d1c2d7ae578cdce6e5a17b7e`, observó:

```text
cpu.max=100000 100000
memory.high=536870912
memory.max=805306368
memory.swap.max=0
pids.max=256
var_fstype=tmpfs
var_size_bytes=268435456
var_inodes=65536
```

El PID 1 de Arch quedó en:

```text
/system.slice/morimil-arch-resource-limits-ci.service/payload/init.scope
```

La unidad limitada fue:

```text
/system.slice/morimil-arch-resource-limits-ci.service
```

La prueba confirmó además rechazo de una reserva superior al límite de `/var`, eliminación completa y Debian sin cambios.

Artefacto:

```text
morimil-arch-executor-resource-limits-29892193434
sha256:e51a51f81225dbf7e5fe1bc500cc358abf29bd7ea8e56cb3fe26905c63f2b086
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
