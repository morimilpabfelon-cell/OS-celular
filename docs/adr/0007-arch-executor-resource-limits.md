# ADR-0007: límites de recursos del Arch Executor

- Estado: aceptada para validación
- Fecha: 2026-07-22

## Contexto

La Fase 2E demostró un ciclo operacional estable para crear, iniciar, consultar, detener, reconstruir y destruir el Arch Executor. Sin límites explícitos, un proceso dentro de Arch podría consumir CPU, memoria, swap, procesos o almacenamiento volátil hasta afectar al anfitrión Debian.

El executor se inicia mediante una unidad transitoria de systemd creada por Debian. `systemd-nspawn` normalmente puede crear una unidad de alcance separada; por tanto, aplicar límites únicamente a su proceso lanzador no garantiza que el payload permanezca contenido.

## Decisión

Debian aplica los límites mediante propiedades de la unidad transitoria que ejecuta `systemd-nspawn`:

```text
CPUQuota=100%
MemoryHigh=536870912
MemoryMax=805306368
MemorySwapMax=0
TasksMax=256
```

La unidad habilita contabilidad de CPU, memoria y tareas, y usa `Delegate=yes` para permitir que systemd dentro del executor administre subcgroups sin escapar del cgroup padre.

`systemd-nspawn` se inicia con `--keep-unit`. El PID 1 del executor debe permanecer dentro del cgroup de la unidad transitoria o uno de sus descendientes.

La raíz continúa en solo lectura. El estado escribible se limita mediante un `tmpfs` explícito:

```text
/var:mode=0755,nodev,nosuid,size=268435456,nr_inodes=65536
```

Los valores canónicos están en:

```text
config/arch-executor-resource-limits.env
```

El archivo instalado de límites debe coincidir exactamente con la versión del repositorio. El ciclo de vida rechaza el arranque o la destrucción cuando detecta divergencia.

## Validación obligatoria

Una ejecución AArch64 nativa debe demostrar:

1. cgroup v2 activo;
2. `cpu.max` finito y equivalente al porcentaje declarado;
3. `memory.high`, `memory.max` y `memory.swap.max` exactos;
4. `pids.max` exacto;
5. PID 1 de Arch contenido en el cgroup limitado;
6. `/var` como `tmpfs` con tamaño e inodos exactos;
7. rechazo de una reserva mayor que el límite de `/var`;
8. parada y destrucción completas;
9. Debian sin cambios en boot ID, red y archivo centinela.

## Consecuencias

- Arch no puede utilizar más de una CPU equivalente de forma sostenida.
- La presión de memoria comienza en 512 MiB y el límite duro es 768 MiB.
- El executor no puede consumir swap del anfitrión.
- El número total de tareas queda limitado a 256.
- El almacenamiento volátil de `/var` queda limitado a 256 MiB y 65 536 inodos.
- Estos valores son un perfil inicial verificable, no una optimización definitiva para un teléfono físico.

## Fuera de alcance

- cuotas persistentes para datos de usuario;
- bind mounts de datos;
- límites de I/O por dispositivo;
- perfiles dinámicos según batería o temperatura;
- acceso a hardware físico.
