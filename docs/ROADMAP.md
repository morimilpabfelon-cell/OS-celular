# Hoja de ruta verificable

Esta hoja de ruta define resultados y puertas de validación. No representa funciones ya implementadas.

## Fase 0 — Fundamentos del repositorio

**Objetivo:** establecer alcance, fronteras y disciplina de desarrollo.

Entregables:

- arquitectura inicial;
- ADR sobre Debian Host y Arch Executor;
- reglas de contribución;
- riesgos y decisiones pendientes explícitos.

**Puerta de salida:** revisión y fusión del PR fundacional.

## Fase 1 — Debian ARM64 mínimo en QEMU

**Objetivo:** producir una imagen Debian ARM64 reproducible y arrancable en QEMU `virt`.

Entregables previstos:

- definición declarativa o script de construcción;
- versiones y fuentes fijadas;
- verificación de firmas y sumas;
- kernel e initramfs compatibles con QEMU `virt`;
- consola serie;
- servicio de salud mínimo;
- comando documentado para construir y arrancar;
- registro de prueba guardado como artefacto de CI.

**Prueba obligatoria:** una ejecución limpia debe alcanzar `multi-user.target` sin intervención manual.

**No incluido:** interfaz móvil, módem, llamadas, cámara o teléfono físico.

## Fase 2 — Arch Executor aislado

**Objetivo:** iniciar un rootfs Arch Linux ARM AArch64 aislado desde Debian.

Entregables previstos:

- descarga desde fuente oficial;
- verificación criptográfica disponible y checksum;
- definición `.nspawn` versionada;
- límites de CPU, memoria y almacenamiento;
- red desactivada por defecto o limitada explícitamente;
- montaje de datos mediante lista permitida;
- prueba de destrucción y reconstrucción;
- prueba de fallo forzado.

**Prueba obligatoria:** al destruir o corromper el ejecutor de prueba, Debian debe continuar operativo y poder reconstruirlo.

## Fase 3 — Morimil Core mínimo

**Objetivo:** implementar un supervisor nativo pequeño y auditable.

Capacidades iniciales:

- consultar estado del anfitrión;
- iniciar y detener Arch Executor;
- imponer límites;
- registrar eventos estructurados;
- exponer una API local autenticada;
- operar sin interfaz gráfica.

**Prueba obligatoria:** ninguna acción privilegiada debe depender de ejecutar comandos de texto arbitrarios proporcionados por el ejecutor.

## Fase 4 — Morimil Shell en Wayland

**Objetivo:** construir la primera interfaz táctil nativa.

Alcance inicial:

- sesión y bloqueo;
- lanzador básico;
- estado del sistema;
- control del ejecutor;
- notificaciones locales;
- recuperación de una caída de la interfaz.

**Prueba obligatoria:** el cierre de Morimil Shell no debe detener Morimil Core ni Arch Executor.

## Fase 5 — Selección de hardware

**Objetivo:** elegir un dispositivo de referencia con evidencia de soporte Linux.

Matriz mínima de evaluación:

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
- disponibilidad de firmware;
- método de recuperación física.

**Puerta de salida:** no se compra ni anuncia un dispositivo objetivo sin completar la matriz y registrar sus limitaciones.

## Fase 6 — Port físico

Solo comienza después de aprobar la Fase 5. El éxito se medirá componente por componente; arrancar una consola no equivale a tener un sistema móvil funcional.

## Riesgos principales

1. Soporte incompleto de hardware móvil en Linux mainline.
2. Módem y telefonía dependientes de firmware o interfaces propietarias.
3. Consumo energético y suspensión deficientes.
4. Superficie de ataque introducida por paquetes recientes del ejecutor.
5. Complejidad de actualizaciones atómicas y rollback.
6. Alcance excesivo antes de validar el arranque básico.

## Regla de ejecución

Cada fase debe cerrar sus pruebas antes de abrir trabajo sustancial de la siguiente. Se permiten prototipos exploratorios, pero no deben confundirse con componentes de producción.