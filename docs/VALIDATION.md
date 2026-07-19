# Validación y evidencia

## Propósito

Este documento separa pruebas estáticas, contratos simulados y ejecución real. Ninguna prueba debe presentarse como más fuerte de lo que demuestra.

## Matriz de estado

| Capacidad | Estado | Evidencia exigida |
|---|---|---|
| Estructura del repositorio | Automatizada | workflow `Repository validation` |
| Sintaxis POSIX | Automatizada | `sh -n` |
| Análisis de shell | Automatizado | ShellCheck |
| Contratos del constructor y QEMU | Automatizados con mocks | `tests/shell/*.sh` |
| Construcción Debian ARM64 real | En integración | `build.log`, checksum y metadata |
| Arranque UEFI real | En integración | `boot.log` |
| Kernel y systemd | En integración | consola serie |
| `multi-user.target` activo | En integración | marca `MORIMIL_BOOT_PROOF` |
| Apagado controlado | En integración | salida 0 de QEMU |
| Reproducibilidad bit a bit | No validada | dos SHA-256 idénticos |
| Soporte de teléfono físico | No iniciado | matriz por componente |

## Pruebas estáticas

```sh
sh scripts/check-repository.sh
```

Comprueban:

- archivos obligatorios;
- sintaxis POSIX;
- ShellCheck cuando está disponible;
- ausencia de imágenes y logs rastreados por Git;
- whitespace y parche del commit.

## Pruebas contractuales

```sh
for test_script in tests/shell/*.sh; do
    sh "$test_script"
done
```

Usan ejecutables simulados para verificar:

- opciones EFI, ARM64, snapshot y script de personalización;
- permisos `0755` del directorio temporal;
- checksum y metadata;
- rechazo de sobrescritura accidental;
- aislamiento de QEMU y red desactivada;
- validación de recursos y firmware;
- instalación segura de la instrumentación de arranque;
- aceptación y rechazo correctos del verificador de logs.

No descargan paquetes ni prueban un kernel.

## Prueba real de arranque

La imagen de validación instala un timer de systemd. Cuando se activa, el servicio comprueba:

```sh
systemctl is-active --quiet multi-user.target
```

Solo después imprime en `/dev/console`:

```text
MORIMIL_BOOT_PROOF target=multi-user.target state=active
```

El verificador exige esa marca exacta y rechaza tanto su ausencia como `MORIMIL_BOOT_PROOF_FAILED`.

## Evidencia conservada

Una ejecución real debe conservar:

```text
build/
├── build.log
├── boot.log
├── container-image.txt
├── environment.txt
├── morimil-trixie-arm64.raw.sha256
├── morimil-trixie-arm64.raw.metadata
└── validation-status.txt
```

La imagen raw no se sube a Git ni a los artefactos de CI. El checksum permite identificarla sin consumir almacenamiento innecesario.

## Reproducibilidad

Solo se compararán dos construcciones cuando coincidan:

- snapshot solicitado;
- `SOURCE_DATE_EPOCH`;
- digest del contenedor;
- versiones de herramientas;
- script de personalización y su SHA-256;
- tamaño y opciones de imagen.

La igualdad exacta de SHA-256 es obligatoria. Un solo build exitoso demuestra construcción y arranque, no reproducibilidad bit a bit.

## Límites

QEMU `virt` no representa un teléfono. Incluso una ejecución completamente verde no demuestra pantalla táctil, batería, suspensión móvil, módem, cámara, sensores, GPU ni consumo energético.
