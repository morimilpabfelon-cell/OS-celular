# ADR-0007: límites de recursos del Arch Executor

- Estado: aceptada y validada
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

## Validación

La ejecución AArch64 nativa `29892193434`, sobre el head `66fa058a2aaa5692d1c2d7ae578cdce6e5a17b7e`, demostró:

1. cgroup v2 activo;
2. `cpu.max=100000 100000`;
3. `memory.high=536870912`;
4. `memory.max=805306368`;
5. `memory.swap.max=0`;
6. `pids.max=256`;
7. PID 1 de Arch bajo `/system.slice/morimil-arch-resource-limits-ci.service/payload/init.scope`;
8. `/var` como `tmpfs` de `268435456` bytes y `65536` inodos;
9. rechazo de una reserva superior al límite de `/var`;
10. parada y destrucción completas;
11. Debian sin cambios en boot ID, red, namespace y archivo centinela.

Artefacto:

```text
morimil-arch-executor-resource-limits-29892193434
sha256:e51a51f81225dbf7e5fe1bc500cc358abf29bd7ea8e56cb3fe26905c63f2b086
```

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
