# Arquitectura de Morimil OS

**Estado:** línea base de diseño, no implementación terminada  
**Fecha:** 2026-07-19  
**Arquitectura objetivo inicial:** ARM64/AArch64

## 1. Propósito

Morimil OS será un sistema móvil GNU/Linux nativo organizado en capas con responsabilidades estrictamente separadas:

> **Debian gobierna. Morimil decide. Arch ejecuta.**

La separación evita mezclar dos gestores de paquetes en una misma raíz y permite que el entorno de ejecución de actualización rápida falle sin derribar el sistema anfitrión.

## 2. Lo que existe hoy

El repositorio está en Fase 0. Actualmente no existe:

- imagen arrancable;
- kernel configurado para un teléfono;
- soporte de módem, llamadas o SMS;
- interfaz gráfica móvil;
- contenedor Arch construido;
- servicio Morimil ejecutándose;
- dispositivo físico seleccionado.

Estos elementos solo podrán declararse implementados cuando existan código, artefactos reproducibles y pruebas registradas.

## 3. Capas del sistema

```text
Hardware ARM64
    │
    ▼
Firmware y boot chain del dispositivo
    │
    ▼
Debian Host
    ├── kernel Linux y módulos
    ├── systemd y servicios críticos
    ├── almacenamiento, red y energía
    ├── recuperación y actualizaciones
    ├── compositor Wayland
    └── control de dispositivos
            │
            ▼
Morimil Core
    ├── política de capacidades
    ├── identidad local
    ├── memoria y auditoría
    ├── supervisor de procesos
    └── puente con el ejecutor
            │
            ▼
Arch Executor
    ├── herramientas de desarrollo
    ├── agentes y procesos de usuario
    ├── compiladores
    └── paquetes de actualización rápida
```

## 4. Debian Host

Debian será la única distribución autorizada para administrar el sistema base.

Responsabilidades:

- arrancar y recuperar el dispositivo;
- administrar kernel, módulos y firmware;
- montar y cifrar almacenamiento;
- controlar red, audio, pantalla, sensores y energía;
- iniciar y supervisar Morimil Core;
- iniciar, detener y restaurar Arch Executor;
- aplicar actualizaciones del sistema base;
- conservar registros de fallos.

Línea base propuesta: Debian 13 `trixie` para `arm64`. La versión puntual deberá fijarse en el sistema de construcción y actualizarse mediante cambios revisados, no mediante una referencia flotante silenciosa.

## 5. Morimil Core

Morimil Core será una capa de servicios nativos, no una aplicación Android ni un simple lanzador gráfico.

Responsabilidades previstas:

- definir qué proceso puede solicitar cada capacidad;
- mediar acceso a archivos privados y dispositivos;
- limitar CPU, memoria, almacenamiento y tiempo de ejecución;
- registrar decisiones sensibles;
- mantener el estado mínimo necesario para recuperación;
- detener el ejecutor si viola una política o queda inestable.

La implementación de estos servicios todavía no está decidida en detalle. Rust es el lenguaje preferido para los servicios críticos, sujeto a prototipos y revisión.

## 6. Arch Executor

Arch Linux ARM se utilizará únicamente como espacio de usuario aislado.

Reglas:

- no comparte la raíz de Debian;
- `pacman` no modifica paquetes administrados por `apt`;
- no controla el bootloader ni el kernel anfitrión;
- no carga módulos del kernel por decisión propia;
- no recibe acceso general a dispositivos;
- sus datos persistentes se almacenan en rutas explícitas;
- debe poder destruirse y reconstruirse;
- una actualización fallida no debe impedir el arranque de Debian.

El mecanismo inicial propuesto es `systemd-nspawn`, administrado por `machinectl`. Esta decisión deberá validarse con pruebas de aislamiento y consumo antes de considerarse definitiva.

## 7. Interfaz gráfica

La primera interfaz se evaluará sobre Wayland. Qt/QML es el candidato inicial para Morimil Shell.

No se construirá un compositor propio en la primera fase. Primero se demostrará una interfaz táctil sobre un compositor existente y mantenido. Un compositor propio solo tendría sentido después de estabilizar entrada, renderizado, suspensión, bloqueo y recuperación.

## 8. Exclusiones explícitas

Morimil OS no utilizará:

- Android como sistema base;
- Android Runtime;
- Waydroid;
- APK como formato de aplicación;
- Halium;
- una raíz híbrida donde `apt` y `pacman` administren los mismos archivos;
- dual boot Debian/Arch como arquitectura principal.

La ausencia de Android no garantiza por sí sola que todo el firmware del hardware sea libre. Ese punto dependerá del dispositivo seleccionado y deberá documentarse sin ocultar blobs o componentes propietarios.

## 9. Plataforma de validación inicial

La primera plataforma será QEMU `qemu-system-aarch64` con la máquina virtual genérica `virt`.

Motivo:

- permite probar ARM64 antes de depender de un teléfono específico;
- separa errores de arquitectura de errores de controladores físicos;
- permite automatizar arranque, consola serie y pruebas de fallo;
- no afirma compatibilidad con ningún teléfono real.

QEMU `virt` no representa un dispositivo comercial. Superar las pruebas en QEMU es un requisito previo, no una prueba de compatibilidad móvil.

## 10. Secuencia de arranque objetivo

```text
firmware virtual o del dispositivo
    → bootloader
    → kernel Linux
    → initramfs
    → Debian/systemd
    → servicios esenciales
    → Morimil Core
    → Morimil Shell
    → Arch Executor bajo demanda
```

## 11. Invariantes de seguridad y operación

1. Debian debe arrancar aunque Arch Executor no exista o esté dañado.
2. Arch Executor no debe modificar la raíz del anfitrión.
3. Los artefactos descargados deben verificarse antes de instalarse.
4. Las pruebas deben poder repetirse desde un entorno limpio.
5. Los fallos deben producir registros utilizables.
6. Las funciones no implementadas deben figurar como tales.
7. El soporte de un dispositivo físico exige evidencia por componente: arranque, pantalla, táctil, audio, red, suspensión, carga, sensores y módem.

## 12. Fuentes técnicas primarias

- Debian 13 estable y soporte ARM64: https://www.debian.org/releases/stable/arm64/
- Estado de las versiones Debian: https://www.debian.org/releases/
- Arch Linux ARM AArch64 genérico: https://archlinuxarm.org/platforms/armv8/generic
- Descargas firmadas de Arch Linux ARM: https://archlinuxarm.org/about/downloads
- Configuración de contenedores `systemd-nspawn`: https://www.freedesktop.org/software/systemd/man/systemd.nspawn.html
- Emulación ARM de QEMU: https://www.qemu.org/docs/master/system/target-arm.html
- Máquina virtual QEMU `virt`: https://www.qemu.org/docs/master/system/arm/virt.html

## 13. Decisiones pendientes

- formato reproducible de imagen del anfitrión;
- esquema de particiones y rollback;
- mecanismo exacto de actualización;
- modelo de capacidades de Morimil Core;
- compositor Wayland inicial;
- dispositivo físico de referencia;
- estrategia de telefonía y módem sin Android;
- licencia del proyecto.

Ninguna de estas decisiones debe cerrarse por intuición. Cada una requiere un ADR, fuentes y una prueba mínima.