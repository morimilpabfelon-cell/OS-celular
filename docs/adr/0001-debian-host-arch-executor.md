# ADR-0001: Debian como anfitrión y Arch Linux ARM como ejecutor aislado

- **Estado:** Aceptada
- **Fecha:** 2026-07-19
- **Ámbito:** arquitectura base

## Contexto

Morimil OS necesita una base móvil estable y controlada, pero también un entorno capaz de ejecutar software reciente, herramientas de desarrollo y procesos experimentales.

Instalar paquetes Debian y Arch en una misma raíz produciría conflictos de propiedad de archivos, dependencias, bibliotecas y políticas de actualización. Un dual boot tampoco permitiría que ambos sistemas colaboren durante una misma sesión.

## Decisión

1. Debian 13 `trixie` será el sistema anfitrión inicial para ARM64.
2. Debian controlará arranque, kernel, almacenamiento, red, dispositivos, energía, recuperación y servicios críticos.
3. Arch Linux ARM funcionará como un sistema de archivos independiente y aislado.
4. El primer mecanismo de ejecución evaluado será `systemd-nspawn` con administración mediante `machinectl`.
5. Morimil Core será el intermediario entre las solicitudes del ejecutor y las capacidades del anfitrión.
6. El ejecutor deberá poder eliminarse, reconstruirse y restaurarse sin reinstalar Debian.

## Consecuencias positivas

- El sistema base mantiene un ciclo de cambios conservador.
- El entorno Arch puede actualizarse o reemplazarse de forma independiente.
- Una avería del ejecutor no debería bloquear el arranque del anfitrión.
- `apt` y `pacman` conservan raíces y responsabilidades separadas.
- Las capacidades del hardware pueden concederse de forma limitada.

## Costes y riesgos

- Mayor complejidad operativa que una sola distribución.
- Consumo adicional de almacenamiento.
- Necesidad de diseñar una interfaz estable entre Morimil Core y Arch Executor.
- `systemd-nspawn` comparte el kernel del anfitrión; no equivale a una máquina virtual ni elimina por sí solo todos los riesgos.
- Los paquetes de Arch y del AUR no deben considerarse confiables automáticamente.
- La estrategia de actualizaciones y rollback todavía debe diseñarse.

## Alternativas rechazadas

### Arch como sistema anfitrión

Se rechaza para la primera fase porque un sistema móvil necesita minimizar cambios no controlados en componentes críticos. Podrá reevaluarse únicamente con evidencia de mantenimiento y recuperación superior.

### Debian y Arch en la misma raíz

Se rechaza por conflictos entre gestores de paquetes y ausencia de fronteras de responsabilidad.

### Dual boot

Se rechaza porque no cumple el objetivo de usar Debian como autoridad y Arch como ejecutor simultáneo.

### Android o capas de compatibilidad Android

Se rechaza porque el alcance definido es una plataforma GNU/Linux nativa sin Android Runtime, APK, Waydroid ni Halium.

## Criterios de validación

La decisión se considera técnicamente validada cuando una prueba automatizada demuestra que:

1. Debian ARM64 arranca en QEMU;
2. Arch Executor inicia dentro del anfitrión;
3. el ejecutor no puede modificar rutas protegidas del anfitrión;
4. el ejecutor puede detenerse de forma forzada;
5. Debian continúa operativo después del fallo;
6. el ejecutor puede reconstruirse desde una fuente verificada;
7. los registros permiten explicar el resultado.

## Fuentes

- Debian ARM64: https://www.debian.org/releases/stable/arm64/
- Arch Linux ARM AArch64: https://archlinuxarm.org/platforms/armv8/generic
- Descargas de Arch Linux ARM: https://archlinuxarm.org/about/downloads
- `systemd-nspawn`: https://www.freedesktop.org/software/systemd/man/systemd-nspawn.html
