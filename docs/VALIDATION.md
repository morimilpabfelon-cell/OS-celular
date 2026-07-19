# Validación del repositorio

## Alcance

La validación automática comprueba estructura, sintaxis y limpieza del repositorio. No demuestra que una imagen arranque, que el sistema funcione en un teléfono ni que el hardware sea compatible.

## Comprobación local

Ejecutar desde la raíz del repositorio:

```sh
sh scripts/check-repository.sh
```

El script realiza:

- verificación de archivos fundacionales obligatorios;
- análisis sintáctico POSIX con `sh -n` de todos los scripts `.sh`;
- ShellCheck cuando está instalado;
- comprobación de espacios y errores de parche mediante Git;
- rechazo de imágenes, discos virtuales, logs, checksums y metadata generados que hayan sido añadidos al índice.

## GitHub Actions

El workflow `.github/workflows/validate.yml` se ejecuta en pull requests y en cambios enviados a `main`.

Características:

- runner `ubuntu-24.04`;
- permisos de contenido en solo lectura;
- checkout sin persistir credenciales;
- límite de diez minutos;
- instalación explícita de ShellCheck desde los repositorios del runner.

## Límites

Una ejecución verde significa únicamente que las comprobaciones estáticas definidas terminaron correctamente. No valida:

- construcción completa de una imagen ARM64;
- arranque UEFI;
- kernel, initramfs o systemd;
- `multi-user.target`;
- apagado controlado;
- reproducibilidad bit a bit;
- soporte de pantalla, táctil, audio, batería, sensores, GPU o módem.

Las pruebas de construcción y arranque deberán implementarse y conservar evidencia separada antes de declarar completada la Fase 1.
