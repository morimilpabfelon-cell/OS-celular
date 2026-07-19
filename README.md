# Morimil OS

Repositorio del sistema operativo móvil Morimil.

## Estado

Fase 0: definición técnica. El repositorio todavía no contiene una imagen arrancable ni soporte de hardware.

## Principio de arquitectura

**Debian gobierna. Morimil decide. Arch ejecuta.**

- Debian será el sistema anfitrión estable.
- Morimil coordinará políticas y servicios.
- Arch Linux ARM funcionará como entorno aislado de ejecución.
- El objetivo es una plataforma GNU/Linux nativa para ARM64.
- El proyecto no utilizará Android ni capas de compatibilidad Android.

## Primer objetivo

Validar en una máquina virtual AArch64 una base Debian capaz de iniciar servicios de Morimil y un entorno Arch Linux ARM aislado, con pruebas reproducibles.

## Desarrollo

Las decisiones técnicas se documentarán antes de afirmar que una función está implementada. Después de este commit inicial, los cambios deben realizarse mediante ramas y pull requests.
