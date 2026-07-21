# Morimil OS

Repositorio del sistema operativo móvil Morimil.

> **Debian gobierna. Morimil decide. Arch ejecuta.**

## Estado

**Fase 2: Arch Executor aislado en desarrollo.**

La Fase 1 validó un proceso reproducible para construir y arrancar Debian 13 ARM64 en QEMU `virt`, alcanzar `multi-user.target`, apagar de forma controlada e inspeccionar la imagen. La Fase 2 inicia con una política `systemd-nspawn` restrictiva y pruebas negativas que impiden habilitar red compartida, capacidades o montajes del anfitrión sin una decisión explícita.

Todavía no existe un rootfs Arch funcional ni soporte para un teléfono físico.

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
- [Estado y criterios de validación](docs/VALIDATION.md)
- [ADR-0001: Debian Host y Arch Executor](docs/adr/0001-debian-host-arch-executor.md)
- [ADR-0002: imagen Debian ARM64 para QEMU](docs/adr/0002-qemu-arm64-validation-image.md)
- [ADR-0003: aislamiento del Arch Executor](docs/adr/0003-arch-executor-isolation.md)
- [Reglas de contribución](CONTRIBUTING.md)

## Objetivo verificable actual

Construir un rootfs Arch Linux ARM AArch64 autenticado, iniciar el ejecutor sin red ni acceso general al anfitrión y demostrar que puede destruirse, fallar y reconstruirse sin afectar Debian.

La validación en QEMU no implica compatibilidad con un teléfono físico. El hardware se seleccionará después mediante una matriz verificable de soporte.

## Desarrollo

Los cambios deben realizarse mediante ramas y pull requests. Las decisiones arquitectónicas se registran como ADR y las fuentes externas deben ser oficiales o primarias.

El workflow distingue pruebas estáticas, contratos simulados y ejecución real. Una política verde no prueba que el rootfs Arch arranque.

## Licencia

Todavía no se ha seleccionado una licencia. No debe asumirse que el contenido ya está autorizado para redistribución como software libre hasta que exista una decisión explícita.
