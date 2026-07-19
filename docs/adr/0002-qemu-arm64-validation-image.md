# ADR-0002: Imagen Debian ARM64 de validación para QEMU

- **Estado:** aceptado para Fase 1; ejecución real pendiente
- **Fecha:** 2026-07-19
- **Alcance:** laboratorio virtual; no es una imagen para teléfono físico

## Contexto

Morimil OS necesita validar el arranque de Debian ARM64 antes de seleccionar hardware móvil. QEMU ofrece la máquina genérica `virt`, diseñada para ejecutar Linux sin representar un dispositivo físico concreto.

Debian 13 `trixie` soporta `arm64`. `mmdebstrap-autopkgtest-build-qemu` puede crear imágenes raw, utiliza EFI y admite salida reproducible cuando se fijan un snapshot y `SOURCE_DATE_EPOCH`.

## Decisión

La Fase 1 utilizará:

- Debian 13 `trixie` para `arm64`;
- `mmdebstrap-autopkgtest-build-qemu`;
- snapshot fechado de `snapshot.debian.org`;
- `SOURCE_DATE_EPOCH` explícito;
- QEMU `qemu-system-aarch64` con máquina `virt`;
- CPU virtual `cortex-a57`;
- firmware AAVMF del paquete Debian `qemu-efi-aarch64`;
- disco VirtIO, TCG y consola serie;
- red desactivada;
- checksum obligatorio antes del arranque;
- instrumentación temporal mediante la opción `--script`.

La instrumentación instala un timer de systemd. Después de su activación, un servicio comprueba que `multi-user.target` esté realmente activo, imprime una marca estructurada en `/dev/console` y solicita el apagado.

## Entorno de CI

La primera ejecución automatizada real utilizará un contenedor oficial Debian fechado sobre un runner Linux de GitHub Actions.

El contenedor requiere modo privilegiado para habilitar `binfmt_misc` durante la construcción cruzada `amd64` → `arm64`. Esta excepción está limitada por las siguientes reglas:

- no se exponen secretos;
- el repositorio se monta de solo lectura;
- solo `build/` permite escritura;
- las herramientas se instalan desde el snapshot fijado;
- se registra el digest real del contenedor;
- la VM no tiene red;
- la imagen raw no se publica.

La ejecución privilegiada es una decisión de laboratorio, no una arquitectura del producto.

## Criterio de aceptación

La Fase 1 no queda validada por crear un archivo raw. Debe existir evidencia de que:

1. la construcción termina correctamente;
2. el checksum de la imagen es válido;
3. UEFI encuentra el cargador;
4. el kernel ARM64 inicia;
5. systemd activa `multi-user.target`;
6. la consola contiene `MORIMIL_BOOT_PROOF target=multi-user.target state=active`;
7. la VM se apaga y QEMU termina con código 0;
8. versiones, logs, metadata y checksum quedan archivados.

La reproducibilidad bit a bit requiere además dos construcciones independientes con SHA-256 idéntico.

## Consecuencias positivas

- separa fallos de arquitectura de problemas de hardware móvil;
- produce evidencia legible por máquina;
- evita confundir un login visible con una prueba formal del target;
- conserva entradas y versiones del entorno;
- no almacena imágenes pesadas en GitHub.

## Riesgos y límites

- QEMU `virt` no prueba hardware telefónico;
- TCG no representa rendimiento real;
- el contenedor privilegiado amplía la superficie del runner de CI;
- el constructor de autopkgtest es un artefacto de validación, no el formato final de Morimil OS;
- una construcción exitosa no demuestra reproducibilidad;
- la instrumentación de apagado debe eliminarse de cualquier imagen de producto.

## Alternativas descartadas

### Usar Ubuntu como entorno de referencia

Se descarta para la prueba de referencia porque las versiones de `mmdebstrap` y herramientas pueden diferir de Debian 13. Ubuntu puede servir para validación estática, no para afirmar una construcción Debian controlada.

### Subir la imagen raw como artefacto

Se descarta por tamaño y porque los logs, metadata y SHA-256 son suficientes para auditar la ejecución inicial. La imagen podrá almacenarse posteriormente en una infraestructura de releases con política explícita.

### Considerar el prompt de login como éxito

Se descarta porque no prueba de forma explícita el estado de `multi-user.target` ni un apagado controlado.

## Fuentes primarias

- https://www.debian.org/releases/stable/arm64/
- https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap-autopkgtest-build-qemu.1.en.html
- https://snapshot.debian.org/
- https://www.qemu.org/docs/master/system/arm/virt.html
- https://packages.debian.org/trixie/qemu-efi-aarch64
- https://docs.github.com/en/actions/tutorials/store-and-share-data
