# Hoja de ruta verificable

Esta hoja de ruta define resultados y puertas de validación. Un estado completado significa que existe evidencia reproducible en el repositorio o en CI; no implica soporte para teléfono físico.

## Fase 0 — Fundamentos del repositorio

**Estado:** completada.

Entregables:

- arquitectura inicial;
- ADR sobre Debian Host y Arch Executor;
- reglas de contribución;
- riesgos y decisiones pendientes explícitos.

## Fase 1 — Debian ARM64 mínimo en QEMU

**Estado:** completada.

Resultado validado:

- imagen Debian 13 ARM64 reproducible;
- UEFI y kernel en QEMU `virt`;
- systemd y `multi-user.target`;
- consola serie;
- apagado controlado;
- inspección ext4 de solo lectura;
- reproducibilidad bit a bit en dos ejecuciones independientes.

**No incluido:** interfaz móvil, módem, llamadas, cámara o teléfono físico.

## Fase 2 — Arch Executor aislado

**Objetivo:** operar un rootfs Arch Linux ARM AArch64 aislado desde Debian.

### Fase 2A — Política de aislamiento

**Estado:** completada.

- definición `.nspawn` versionada;
- UID/GID privados;
- red privada sin `veth`;
- raíz de solo lectura;
- estado volátil;
- sin bind mounts, capacidades, puertos ni dispositivos adicionales.

### Fase 2B — Bootstrap autenticado

**Estado:** completada.

- autoridad local fijada;
- verificación de firma;
- SHA-256, SHA-512, tamaño y estructura exactos;
- extracción segura;
- publicación atómica y rollback.

### Fase 2C — Rootfs real fijado

**Estado:** completada.

- artefacto AArch64 exacto fijado;
- segunda descarga independiente;
- `pacman` identificado como ELF64 AArch64;
- eliminación final del rootfs de validación.

### Fase 2D — Runtime aislado

**Estado:** completada.

- dos arranques con systemd como PID 1;
- aislamiento efectivo de usuarios y red;
- raíz de solo lectura y `/var` volátil;
- parada limpia;
- fallo forzado sin afectar Debian;
- destrucción y reconstrucción desde el mismo pin.

### Fase 2E — Ciclo de vida operacional

**Estado:** completada.

Resultado validado:

- comandos `create`, `start`, `status`, `stop`, `destroy` y `rebuild`;
- bloqueo contra operaciones concurrentes;
- rollback de creación;
- estado estable `clave=valor`;
- unidad transitoria administrada por Debian;
- dos arranques mediante la interfaz operacional;
- `stop` conserva el rootfs y `rebuild` conserva el SHA-256 fijado;
- `/var` no persiste entre arranques;
- `destroy` elimina rootfs, estado y política;
- Debian conserva boot ID, red y archivo centinela.

Evidencia principal: ejecución AArch64 `29890214148` y artefacto `morimil-arch-executor-lifecycle-29890214148`.

### Pendiente para cerrar Fase 2

- límites de CPU;
- límites de memoria;
- límites de almacenamiento;
- lista permitida explícita para futuros montajes de datos.

**Puerta de salida:** destruir o corromper el executor no debe afectar Debian, y el sistema debe poder reconstruirlo desde el pin aprobado.

## Fase 3 — Morimil Core mínimo

**Objetivo:** implementar un supervisor nativo pequeño y auditable.

Capacidades iniciales:

- consultar estado del anfitrión;
- invocar operaciones delimitadas del Arch Executor;
- imponer límites;
- registrar eventos estructurados;
- exponer una API local autenticada;
- operar sin interfaz gráfica.

**Prueba obligatoria:** ninguna acción privilegiada debe depender de ejecutar comandos de texto arbitrarios proporcionados por el executor.

## Fase 4 — Morimil Shell en Wayland

**Objetivo:** construir la primera interfaz táctil nativa.

Alcance inicial:

- sesión y bloqueo;
- lanzador básico;
- estado del sistema;
- control del executor;
- notificaciones locales;
- recuperación de una caída de la interfaz.

**Prueba obligatoria:** el cierre de Morimil Shell no debe detener Morimil Core ni Arch Executor.

## Fase 5 — Selección de hardware

**Objetivo:** elegir un dispositivo de referencia con evidencia de soporte Linux.

Matriz mínima:

- bootloader documentado y desbloqueable legalmente;
- kernel mainline o estrategia de mantenimiento verificable;
- pantalla y táctil;
- almacenamiento;
- Wi-Fi y Bluetooth;
- audio;
- carga y batería;
- suspensión y reanudación;
- sensores;
- GPU;
- módem y telefonía;
- firmware;
- recuperación física.

No se compra ni anuncia un dispositivo objetivo sin completar la matriz y registrar sus limitaciones.

## Fase 6 — Port físico

Solo comienza después de aprobar la Fase 5. El éxito se medirá componente por componente; arrancar una consola no equivale a tener un sistema móvil funcional.

## Riesgos principales

1. Soporte incompleto de hardware móvil en Linux mainline.
2. Módem y telefonía dependientes de firmware o interfaces propietarias.
3. Consumo energético y suspensión deficientes.
4. Superficie de ataque introducida por paquetes recientes del executor.
5. Complejidad de actualizaciones atómicas y rollback.
6. Alcance excesivo antes de validar cada frontera.

## Regla de ejecución

Cada bloque debe cerrar sus pruebas antes de fusionarse. Los prototipos exploratorios no se presentan como componentes de producción.
