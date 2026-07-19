# Morimil OS

Repositorio del sistema operativo móvil Morimil.

> **Debian gobierna. Morimil decide. Arch ejecuta.**

## Estado

**Fase 1: base ARM64 de validación en desarrollo.**

La arquitectura fundacional está documentada. El repositorio contiene scripts iniciales para construir y arrancar una imagen Debian ARM64 en QEMU, pero todavía no existe evidencia registrada de un arranque completo hasta `multi-user.target`, ni soporte para un teléfono físico.

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

Construir una imagen Debian ARM64 reproducible que arranque en QEMU `virt`, alcance `multi-user.target` sin intervención manual y produzca evidencia conservable de construcción y arranque.

La validación en QEMU no implica compatibilidad con un teléfono físico. El hardware se seleccionará después mediante una matriz verificable de soporte.

## Desarrollo

Los cambios deben realizarse mediante ramas y pull requests. Las decisiones arquitectónicas se registran como ADR y las fuentes externas deben ser oficiales o primarias.

La validación automática actual solo comprueba estructura, sintaxis y políticas del repositorio. No debe interpretarse como prueba de arranque.

## Licencia

Todavía no se ha seleccionado una licencia. No debe asumirse que el contenido ya está autorizado para redistribución como software libre hasta que exista una decisión explícita.
