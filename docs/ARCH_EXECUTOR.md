# Arch Executor

## Estado

Las Fases 2A–2D están validadas. Existe evidencia AArch64 nativa de que el rootfs autenticado arranca con systemd como PID 1 dentro de `systemd-nspawn`, usa UID y red privados, conserva la raíz en solo lectura, mantiene `/var` volátil y puede fallar, detenerse, destruirse y reconstruirse sin afectar Debian.

La Fase 2E introduce una interfaz operacional estable. Todavía no se han validado límites definitivos de CPU, memoria o almacenamiento.

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
- estado temporal para las escrituras de ejecución;
- espacio de red privado;
- ninguna interfaz virtual por defecto;
- ningún bind mount del anfitrión;
- ninguna capacidad adicional;
- ningún puerto ni interfaz física expuestos.

La política se comprueba con:

```sh
sh scripts/check-arch-executor-policy.sh
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

Descarga, autentica y publica el rootfs fijado. Después instala el target mínimo, enmascara servicios de red no permitidos y desplaza propietarios para `PrivateUsers=pick`.

No arranca Arch.

### `start`

Inicia el executor mediante una unidad transitoria de systemd y exige la política instalada en modo `trusted`. El comando solo termina correctamente cuando `morimil-executor.target` y el archivo de readiness están activos.

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
```

Estados válidos:

- `absent`;
- `stopped`;
- `running`;
- `inconsistent`.

### `stop`

Solicita apagado mediante `machinectl poweroff`, espera la desaparición del registro y conserva rootfs y metadata.

### `destroy`

Solo opera con el executor detenido. Elimina rootfs, metadata y política instalada. Se niega a borrar una política que no coincida con la versión del repositorio.

### `rebuild`

Ejecuta `stop`, `destroy` y `create`. Descarga de nuevo el artefacto fijado y deja el executor detenido.

## Rutas predeterminadas

```text
/etc/systemd/nspawn/morimil-arch.nspawn
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
```

Validación de evidencia:

```sh
sh scripts/check-arch-executor-lifecycle-evidence.sh build/arch-executor-lifecycle/evidence
```

La ejecución real requiere un host AArch64 nativo con systemd y `systemd-container`.

## Fuera de alcance actual

- límites definitivos de CPU, memoria y almacenamiento;
- acceso a GPU, módem, cámara, batería, sensores o audio;
- red del anfitrión o interfaces `veth`;
- integración de aplicaciones gráficas;
- montajes de directorios personales;
- actualización automática mediante `pacman`;
- compatibilidad con teléfono físico.
