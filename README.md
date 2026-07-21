# Morimil OS

Repositorio del sistema operativo móvil Morimil.

> **Debian gobierna. Morimil decide. Arch ejecuta.**

## Estado

**Fase 1: base Debian ARM64 reproducible validada en QEMU.**

La arquitectura fundacional está documentada. El repositorio contiene un proceso verificable para construir una imagen Debian 13 ARM64, arrancarla mediante UEFI en QEMU `virt`, alcanzar `multi-user.target` sin intervención manual y apagarla de forma controlada.

Dos ejecuciones independientes sobre el mismo commit de construcción produjeron imágenes raw idénticas bit a bit. La evidencia, los criterios y los límites de esta validación están registrados en [docs/VALIDATION.md](docs/VALIDATION.md).

Esta validación no implica soporte para un teléfono físico.

## Alcance

- Debian será el sistema anfitrión estable y controlará el sistema base.
- Morimil coordinará políticas, capacidades y servicios.
- Arch Linux ARM funcionará como entorno aislado de ejecución.
- La arquitectura objetivo inicial es ARM64/AArch64.
- El proyecto será GNU/Linux nativo y no utilizará Android, Waydroid, APK ni Halium.
- `apt` y `pacman` nunca administrarán la misma raíz.

## Documentación

- [Arquitectura](docs/ARCHITECTURE.md)
- [Hoja de ruta](docs/ROADMAP.md)
- [Construcción ARM64 en QEMU](docs/BUILDING.md)
- [Estado y criterios de validación](docs/VALIDATION.md)
- [ADR-0001: Debian Host y Arch Executor](docs/adr/0001-debian-host-arch-executor.md)
- [ADR-0002: imagen Debian ARM64 para QEMU](docs/adr/0002-qemu-arm64-validation-image.md)
- [Reglas de contribución](CONTRIBUTING.md)

## Resultado de la Fase 1

La Fase 1 establece una base Debian ARM64 reproducible que arranca en QEMU `virt`, alcanza `multi-user.target` y produce evidencia conservable de construcción, arranque e inspección.

La validación en QEMU no implica compatibilidad con un teléfono físico. El hardware se seleccionará después mediante una matriz verificable de soporte Linux, sin depender de Android, Halium ni libhybris.

## Desarrollo

Los cambios deben realizarse mediante ramas y pull requests. Las decisiones arquitectónicas se registran como ADR y las fuentes externas deben ser oficiales o primarias.

El workflow ejecuta siempre validaciones estáticas y contractuales. La construcción y el arranque ARM64 reales se ejecutan mediante un disparador controlado y conservan evidencia separada. Una ejecución estática verde no debe interpretarse por sí sola como prueba de arranque.

## Licencia

Todavía no se ha seleccionado una licencia. No debe asumirse que el contenido ya está autorizado para redistribución como software libre hasta que exista una decisión explícita.
