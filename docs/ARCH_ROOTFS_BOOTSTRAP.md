# Bootstrap del rootfs Arch Linux ARM

## Estado

Este bloque implementa adquisición autenticada, validación del archivo y publicación atómica. No inicia `systemd-nspawn` ni demuestra todavía aislamiento en tiempo de ejecución.

## Fuente y clave fijadas

El valor predeterminado es el rootfs AArch64 multi-plataforma oficial:

```text
https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
```

La firma se obtiene añadiendo `.sig`. La huella fijada de la clave de construcción de Arch Linux ARM es:

```text
68B3537F39A313B3E574D06777193F152BDBE6A6
```

El alias `latest` es mutable. Cada ejecución debe aportar el SHA-256 exacto esperado:

```sh
sudo env \
  ARCH_ROOTFS_EXPECTED_SHA256='<64 hexadecimales>' \
  sh scripts/bootstrap-arch-rootfs.sh
```

No se acepta un checksum vacío. MD5 no se utiliza.

## Flujo de seguridad

El script realiza, en orden:

1. validación de URLs, digest y rutas;
2. comprobación de dependencias y privilegios;
3. descarga del tarball y su firma mediante HTTPS;
4. obtención de la clave mediante HKPS;
5. comparación exacta de la huella completa;
6. verificación GPG de la firma;
7. comparación del SHA-256;
8. validación de nombres de miembros del archivo;
9. extracción en un directorio temporal del mismo filesystem;
10. comprobación mínima de identidad y presencia de `pacman`;
11. escritura de metadata de procedencia;
12. publicación mediante renombrado atómico.

La ruta predeterminada publicada es:

```text
/var/lib/machines/morimil-arch
```

El estado externo queda en:

```text
/var/lib/morimil/executors/arch/rootfs-source.env
```

## Sobrescritura y reconstrucción

El script rechaza un destino o metadata ya existentes. No actualiza ni destruye automáticamente un ejecutor previo. La destrucción y reconstrucción serán operaciones explícitas y separadas para evitar pérdidas silenciosas.

## Validación contractual

```sh
sh tests/shell/test-arch-rootfs-bootstrap.sh
python3 -m unittest tests/python/test_validate_rootfs_archive.py -v
```

Las pruebas utilizan herramientas simuladas. Demuestran control de flujo y rechazo de entradas inseguras, no una descarga real ni un arranque Arch.

## Límites

- no configura contraseñas ni usuarios;
- no ejecuta `pacman`;
- no habilita red dentro del ejecutor;
- no instala la definición `.nspawn` en el anfitrión;
- no inicia el contenedor;
- no expone GPU, audio, módem, cámara, sensores ni almacenamiento personal;
- no demuestra compatibilidad con un teléfono físico.
