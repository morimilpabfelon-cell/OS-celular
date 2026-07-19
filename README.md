# Morimil OS

Repositorio del sistema operativo móvil Morimil.

> **Debian gobierna. Morimil decide. Arch ejecuta.**

## Estado

**Fase 0: definición técnica.**

El repositorio todavía no contiene una imagen arrancable, kernel adaptado a un teléfono, interfaz móvil funcional ni soporte de hardware. Esos componentes solo se declararán implementados cuando existan código, artefactos reproducibles y pruebas registradas.

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
- [ADR-0001: Debian Host y Arch Executor](docs/adr/0001-debian-host-arch-executor.md)
- [Reglas de contribución](CONTRIBUTING.md)

## Primer objetivo verificable

Construir una imagen Debian ARM64 reproducible que arranque en QEMU `virt`, alcance un estado operativo sin intervención manual y pueda iniciar un entorno Arch Linux ARM aislado. La prueba también deberá demostrar que un fallo del ejecutor Arch no impide que Debian continúe funcionando.

La validación en QEMU no implica compatibilidad con un teléfono físico. El hardware se seleccionará después mediante una matriz verificable de soporte.

## Desarrollo

Después del commit inicial, los cambios deben realizarse mediante ramas y pull requests. Las decisiones arquitectónicas se registran como ADR y las fuentes externas deben ser oficiales o primarias.

## Licencia

Todavía no se ha seleccionado una licencia. No debe asumirse que el contenido ya está autorizado para redistribución como software libre hasta que exista una decisión explícita.
