# Morimil OS

Repositorio del sistema operativo móvil Morimil.

> **Debian gobierna. Morimil decide. Arch ejecuta.**

## Estado

**Fase 2: rootfs Arch Linux ARM autenticado y validado; arranque aislado pendiente.**

La Fase 1 validó un proceso reproducible para construir y arrancar Debian 13 ARM64 en QEMU `virt`, alcanzar `multi-user.target`, apagar de forma controlada e inspeccionar la imagen. La Fase 2 ya contiene una política `systemd-nspawn` restrictiva y un bootstrap real que verifica una clave local fijada, firma, SHA-256, SHA-512, tamaño y estructura exacta antes de publicar un rootfs Arch Linux ARM.

La ejecución real descargó, verificó, extrajo, inspeccionó y eliminó el rootfs sin ejecutar `pacman` ni iniciar el contenedor. Todavía no existe evidencia de un arranque del Arch Executor ni soporte para un teléfono físico.

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
- [Arch Executor](docs/ARCH_EXECUTOR.md)
- [Bootstrap del rootfs Arch](docs/ARCH_ROOTFS_BOOTSTRAP.md)
- [Estado y criterios de validación](docs/VALIDATION.md)
- [ADR-0001: Debian Host y Arch Executor](docs/adr/0001-debian-host-arch-executor.md)
- [ADR-0002: imagen Debian ARM64 para QEMU](docs/adr/0002-qemu-arm64-validation-image.md)
- [ADR-0003: aislamiento del Arch Executor](docs/adr/0003-arch-executor-isolation.md)
- [ADR-0004: bootstrap autenticado del rootfs Arch](docs/adr/0004-authenticated-arch-rootfs-bootstrap.md)
- [ADR-0005: release fijada y validación real del rootfs Arch](docs/adr/0005-pinned-arch-rootfs-release.md)
- [Reglas de contribución](CONTRIBUTING.md)

## Objetivo verificable actual

Iniciar el rootfs validado mediante la política `systemd-nspawn`, sin red ni acceso general al anfitrión, detenerlo de forma controlada y demostrar fallo, destrucción y reconstrucción sin afectar Debian.

La validación en QEMU no implica compatibilidad con un teléfono físico. El hardware se seleccionará después mediante una matriz verificable de soporte.

## Desarrollo

Los cambios deben realizarse mediante ramas y pull requests. Las decisiones arquitectónicas se registran como ADR y las fuentes externas deben ser oficiales o primarias.

El workflow distingue pruebas estáticas, contratos simulados y ejecución real. Una descarga y extracción verdes no prueban que el contenedor arranque ni que el aislamiento sea suficiente en tiempo de ejecución.

## Licencia

Todavía no se ha seleccionado una licencia. No debe asumirse que el contenido ya está autorizado para redistribución como software libre hasta que exista una decisión explícita.
