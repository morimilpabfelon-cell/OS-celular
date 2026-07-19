# Validación y evidencia

## Propósito

Este documento separa las comprobaciones automáticas de las afirmaciones técnicas que todavía requieren una ejecución real. Un resultado verde de CI no convierte una imagen en arrancable ni demuestra compatibilidad con un teléfono.

## Estado actual

| Capacidad | Estado | Evidencia exigida |
|---|---|---|
| Estructura del repositorio | Automatizada | workflow `Repository validation` |
| Sintaxis POSIX de scripts | Automatizada | `sh -n` y ShellCheck |
| Contratos del constructor y QEMU | Automatizados con mocks | `tests/shell/test-scripts.sh` |
| Ausencia de imágenes generadas en Git | Automatizada | revisión de archivos rastreados |
| Construcción Debian ARM64 real | No validada | log completo y artefactos |
| Arranque UEFI real | No validado | consola serie |
| Carga del kernel ARM64 | No validada | consola serie |
| Llegada a `multi-user.target` | No validada | consola y estado de systemd |
| Reproducibilidad bit a bit | No validada | dos SHA-256 idénticos |
| Soporte de teléfono físico | No iniciado | matriz por componente |

## Validación local del repositorio

```sh
sudo apt install shellcheck
sh scripts/check-repository.sh
sh tests/shell/test-scripts.sh
```

La comprobación local valida archivos, sintaxis, ShellCheck cuando está disponible, diferencias inválidas y que no se hayan añadido imágenes o registros generados.

Las pruebas contractuales sustituyen `mmdebstrap-autopkgtest-build-qemu` y `qemu-system-aarch64` por ejecutables controlados. Comprueban que los scripts:

- transmiten las opciones ARM64, EFI, snapshot y TCG esperadas;
- crean checksum y metadata;
- usan un directorio temporal atravesable;
- rechazan snapshots mal formados y sobrescrituras accidentales;
- exigen checksum antes del arranque;
- conservan la red desactivada y el modo snapshot;
- rechazan recursos inválidos y protegen la plantilla de variables UEFI.

Estas pruebas no descargan Debian, no producen una imagen válida y no ejecutan QEMU real.

## Evidencia de construcción

Cada ejecución real debe conservar como mínimo:

```text
build/
├── morimil-trixie-arm64.raw
├── morimil-trixie-arm64.raw.sha256
├── morimil-trixie-arm64.raw.metadata
├── build.log
└── boot.log
```

La imagen no debe subirse al repositorio Git. Los logs y artefactos se conservarán como artefactos de CI o en almacenamiento de pruebas cuando esa infraestructura esté definida.

## Criterio de arranque aprobado

Una prueba solo se aprueba cuando el registro permite verificar, en orden:

1. ejecución del firmware UEFI;
2. selección del cargador;
3. inicio del kernel ARM64;
4. montaje del sistema raíz;
5. inicio de systemd;
6. llegada a `multi-user.target`;
7. apagado controlado.

Una captura aislada, un archivo de imagen existente o un proceso QEMU en ejecución no son evidencia suficiente.

## Reproducibilidad

Dos construcciones se compararán únicamente cuando utilicen:

- el mismo snapshot efectivo;
- el mismo `SOURCE_DATE_EPOCH`;
- las mismas versiones de herramientas;
- las mismas opciones;
- un entorno limpio equivalente.

El criterio es igualdad exacta del SHA-256 de la imagen raw. Si los hashes difieren, se registra el resultado como no reproducible y se investiga antes de afirmar lo contrario.

## Límites de CI

El workflow actual no construye la imagen de 8 GiB ni arranca QEMU real. Su función es impedir errores estructurales, de shell y de contrato mientras se prepara un entorno de construcción Debian controlado.
