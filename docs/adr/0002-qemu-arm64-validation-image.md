# ADR-0002: Imagen de validación Debian ARM64 para QEMU

- **Estado:** aceptado para Fase 1; implementación aún no validada
- **Fecha:** 2026-07-19
- **Alcance:** laboratorio virtual; no es una imagen para teléfono físico

## Contexto

Morimil OS necesita una primera plataforma reproducible donde validar el arranque de Debian ARM64 antes de seleccionar hardware móvil. QEMU ofrece la máquina genérica `virt`, diseñada para ejecutar sistemas invitados como Linux sin representar un dispositivo físico concreto.

Debian 13 `trixie` soporta oficialmente `arm64`. El paquete Debian `mmdebstrap` incluye `mmdebstrap-autopkgtest-build-qemu`, que construye imágenes raw para QEMU mediante `mmdebstrap`, usa arranque EFI y puede producir resultados bit a bit reproducibles cuando se fija `SOURCE_DATE_EPOCH` y se usa un archivo Debian inmutable.

## Decisión

Para la Fase 1 se utilizará:

- Debian 13 `trixie` para arquitectura `arm64`;
- `mmdebstrap-autopkgtest-build-qemu` como constructor inicial de la imagen raw;
- un snapshot fechado de `snapshot.debian.org`, nunca un espejo flotante en una construcción declarada reproducible;
- una ruta temporal cuyos directorios sean atravesables por el usuario aislado empleado por `mmdebstrap`;
- QEMU `qemu-system-aarch64` con máquina `virt`;
- CPU virtual explícita `cortex-a57`;
- firmware UEFI AArch64 suministrado por el paquete Debian `qemu-efi-aarch64`;
- disco VirtIO y consola serie sin interfaz gráfica para la primera validación;
- aceleración TCG fija durante la primera prueba;
- red desactivada durante la prueba básica de arranque;
- checksum obligatorio antes del arranque, salvo una excepción explícita y visible.

KVM se excluye de la Fase 1 inicial porque depende de un anfitrión ARM64 compatible y requiere una ruta de CPU distinta. Se evaluará en una decisión posterior después de demostrar el arranque con TCG.

La imagen generada por esta fase es únicamente un **artefacto de validación de plataforma**. No define el formato final de actualización, particionado, recuperación ni seguridad de Morimil OS.

## Reproducibilidad

Una construcción solo podrá denominarse reproducible cuando registre como mínimo:

1. marca temporal solicitada y marca efectiva del snapshot Debian;
2. `SOURCE_DATE_EPOCH`;
3. versión de `mmdebstrap`;
4. versión de QEMU;
5. versión del firmware `qemu-efi-aarch64`;
6. SHA-256 de la imagen resultante;
7. registro completo de construcción y arranque.

El script fallará si no se entrega una marca temporal de snapshot. No se usará silenciosamente `stable`, `latest` ni un espejo flotante.

## Criterio de aceptación

La Fase 1 no queda validada por crear un archivo de imagen. Debe existir evidencia de que:

- UEFI encuentra el cargador;
- el kernel ARM64 inicia;
- systemd alcanza `multi-user.target`;
- la consola serie permanece operativa;
- la máquina se apaga de manera controlada;
- el SHA-256 y el registro de la ejecución quedan archivados;
- dos construcciones equivalentes producen el mismo SHA-256 antes de afirmar reproducibilidad bit a bit.

## Consecuencias

### Positivas

- separa el desarrollo del sistema base de los problemas específicos de un teléfono;
- evita depender inicialmente de bootloaders o controladores propietarios;
- permite automatizar pruebas de arranque;
- obliga a distinguir una VM funcional de un sistema móvil funcional;
- evita arrancar silenciosamente una imagen sin verificar;
- elimina una ruta KVM no probada durante la primera validación.

### Limitaciones

- QEMU `virt` no prueba pantalla táctil, batería, suspensión móvil, módem, cámara, sensores ni GPU de un teléfono;
- la imagen de autopkgtest contiene decisiones orientadas a pruebas y deberá sustituirse por un constructor propio antes de una imagen de producto;
- el rendimiento bajo emulación TCG no representa el rendimiento de hardware ARM64 real;
- la validación estática de CI no demuestra construcción ni arranque.

## Fuentes primarias

- Debian 13 `trixie`: https://www.debian.org/releases/trixie/
- Guía Debian para ARM64: https://www.debian.org/releases/stable/arm64/
- Paquete `mmdebstrap`: https://packages.debian.org/trixie/mmdebstrap
- Manual `mmdebstrap-autopkgtest-build-qemu`: https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap-autopkgtest-build-qemu.1.en.html
- QEMU `virt`: https://www.qemu.org/docs/master/system/arm/virt.html
- Firmware UEFI AArch64 de Debian: https://packages.debian.org/trixie/qemu-efi-aarch64
- Archivo histórico Debian: https://snapshot.debian.org/
