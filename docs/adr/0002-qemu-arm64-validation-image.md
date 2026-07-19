# ADR-0002: Imagen Debian ARM64 de validación para QEMU

- **Estado:** aceptado para Fase 1; ejecución real pendiente
- **Fecha:** 2026-07-19
- **Alcance:** laboratorio virtual; no es una imagen para teléfono físico

## Contexto

Morimil OS necesita validar el arranque de Debian ARM64 antes de seleccionar hardware móvil. QEMU ofrece la máquina genérica `virt`, diseñada para ejecutar Linux sin representar un dispositivo físico concreto.

Debian 13 `trixie` soporta `arm64`. `mmdebstrap-autopkgtest-build-qemu` puede crear imágenes raw, utiliza EFI y admite salida reproducible cuando se fijan un snapshot y `SOURCE_DATE_EPOCH`.

Las primeras ejecuciones reales demostraron que `setup-testbed` puede introducir una fuente de seguridad en vivo y que HTTPS puede fallar dentro del chroot antes de instalar certificados. Ambas condiciones invalidan una construcción que pretenda tener entradas completamente fijadas.

## Decisión

La Fase 1 utilizará:

- Debian 13 `trixie` para `arm64`;
- `mmdebstrap-autopkgtest-build-qemu`;
- snapshot fechado de `snapshot.debian.org`;
- `SOURCE_DATE_EPOCH` explícito;
- fuentes deb822 fijadas para `debian` y `debian-security`;
- HTTP como transporte hacia Snapshot, manteniendo validación de firmas Release mediante el keyring oficial;
- `Check-Valid-Until: no` exclusivamente para las entradas históricas;
- QEMU `qemu-system-aarch64` con máquina `virt`;
- CPU virtual `cortex-a57`;
- firmware AAVMF del paquete Debian `qemu-efi-aarch64`;
- disco VirtIO, TCG y consola serie;
- red desactivada;
- checksum obligatorio antes del arranque;
- instrumentación temporal mediante la opción `--script`.

Las fuentes del invitado se entregarán mediante `AUTOPKGTEST_APT_SOURCES`, se conservarán como artefacto y tendrán un SHA-256. No se aceptará `security.debian.org`, `deb.debian.org` ni otro repositorio vivo dentro de la imagen de validación.

La instrumentación instala un timer de systemd. Después de su activación, un servicio comprueba que `multi-user.target` esté realmente activo, imprime una marca estructurada en `/dev/console` y solicita el apagado.

## Entorno de CI

La primera ejecución automatizada real utilizará un contenedor oficial Debian fechado sobre un runner Linux de GitHub Actions.

El contenedor requiere modo privilegiado para habilitar `binfmt_misc` durante la construcción cruzada `amd64` → `arm64`. Esta excepción está limitada por las siguientes reglas:

- no se exponen secretos;
- el repositorio se monta de solo lectura;
- solo `build/` permite escritura;
- las herramientas se instalan desde el snapshot fijado;
- se registra el digest real del contenedor;
- se registran las fuentes APT del invitado y su hash;
- la VM no tiene red;
- la imagen raw no se publica.

La ejecución privilegiada es una decisión de laboratorio, no una arquitectura del producto.

## Criterio de aceptación

La Fase 1 no queda validada por crear un archivo raw. Debe existir evidencia de que:

1. la construcción termina correctamente;
2. ninguna fuente APT viva entra en la imagen;
3. el checksum de la imagen es válido;
4. UEFI encuentra el cargador;
5. el kernel ARM64 inicia;
6. systemd activa `multi-user.target`;
7. la consola contiene `MORIMIL_BOOT_PROOF target=multi-user.target state=active`;
8. la VM se apaga y QEMU termina con código 0;
9. versiones, fuentes APT, logs, metadata y checksums quedan archivados.

La reproducibilidad bit a bit requiere además dos construcciones independientes con SHA-256 idéntico.

## Consecuencias positivas

- separa fallos de arquitectura de problemas de hardware móvil;
- produce evidencia legible por máquina;
- evita confundir un login visible con una prueba formal del target;
- elimina repositorios flotantes del sistema invitado;
- conserva entradas y versiones del entorno;
- no almacena imágenes pesadas en GitHub.

## Riesgos y límites

- QEMU `virt` no prueba hardware telefónico;
- TCG no representa rendimiento real;
- el contenedor privilegiado amplía la superficie del runner de CI;
- HTTP protege integridad mediante firmas APT, pero no aporta confidencialidad de transporte;
- el constructor de autopkgtest es un artefacto de validación, no el formato final de Morimil OS;
- una construcción exitosa no demuestra reproducibilidad;
- la instrumentación de apagado debe eliminarse de cualquier imagen de producto.

## Alternativas descartadas

### Usar Ubuntu como entorno de referencia

Se descarta para la prueba de referencia porque las versiones de `mmdebstrap` y herramientas pueden diferir de Debian 13. Ubuntu puede servir para validación estática, no para afirmar una construcción Debian controlada.

### Mantener HTTPS dentro del chroot inicial

Se descarta para esta fase porque `setup-testbed` ejecuta APT antes de que la imagen garantice certificados funcionales. La autenticidad se conserva mediante firmas Release y `Signed-By`.

### Permitir el repositorio de seguridad en vivo

Se descarta porque una fuente flotante impide identificar exactamente las entradas de la construcción. Se utiliza el archivo `debian-security` del mismo timestamp solicitado.

### Subir la imagen raw como artefacto

Se descarta por tamaño y porque los logs, metadata y SHA-256 son suficientes para auditar la ejecución inicial. La imagen podrá almacenarse posteriormente en una infraestructura de releases con política explícita.

### Considerar el prompt de login como éxito

Se descarta porque no prueba de forma explícita el estado de `multi-user.target` ni un apagado controlado.

## Fuentes primarias

- https://www.debian.org/releases/stable/arm64/
- https://manpages.debian.org/trixie/mmdebstrap/mmdebstrap-autopkgtest-build-qemu.1.en.html
- https://manpages.debian.org/trixie/autopkgtest/autopkgtest-build-qemu.1.en.html
- https://manpages.debian.org/trixie/apt/sources.list.5.en.html
- https://snapshot.debian.org/
- https://packages.debian.org/trixie/uuid-runtime
- https://www.qemu.org/docs/master/system/arm/virt.html
- https://packages.debian.org/trixie/qemu-efi-aarch64
- https://docs.github.com/en/actions/tutorials/store-and-share-data
