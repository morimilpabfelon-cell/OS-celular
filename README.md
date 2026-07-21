# Morimil OS

Repositorio del sistema operativo móvil Morimil.

> **Debian gobierna. Morimil decide. Arch ejecuta.**

## Estado

**Fase 1: base Debian ARM64 reproducible validada en QEMU.**

La arquitectura fundacional está documentada. El repositorio contiene un proceso reproducible para construir y arrancar una imagen Debian 13 ARM64 en QEMU `virt`. La validación registrada demuestra arranque UEFI, kernel y systemd, activación de `multi-user.target`, apagado controlado e inspección de la imagen. Todavía no existe soporte para un teléfono físico.

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

## Primer objetivo verificable

La Fase 1 validó una imagen Debian ARM64 reproducible que arranca en QEMU `virt`, alcanza `multi-user.target` sin intervención manual y produce evidencia conservable de construcción, arranque e inspección.

La validación en QEMU no implica compatibilidad con un teléfono físico. El hardware se seleccionará después mediante una matriz verificable de soporte.

## Desarrollo

Los cambios deben realizarse mediante ramas y pull requests. Las decisiones arquitectónicas se registran como ADR y las fuentes externas deben ser oficiales o primarias.

El workflow distingue las comprobaciones estáticas de la construcción y el arranque ARM64 reales. Las capacidades solo se consideran validadas cuando existe evidencia registrada.

## Licencia

Todavía no se ha seleccionado una licencia. No debe asumirse que el contenido ya está autorizado para redistribución como software libre hasta que exista una decisión explícita.
