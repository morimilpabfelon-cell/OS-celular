# ADR-0005: Release fijada y validación real del rootfs Arch Linux ARM

- **Estado:** aceptado para Fase 2
- **Fecha:** 2026-07-22
- **Alcance:** adquisición y publicación temporal del userspace AArch64; no incluye arranque del contenedor

## Contexto

Arch Linux ARM publica un rootfs genérico AArch64 mediante un nombre mutable `latest`. La firma separada demuestra autenticidad respecto de la clave de construcción, pero el nombre por sí solo no fija los bytes que Morimil debe aceptar.

El bootstrap contractual de ADR-0004 exigía un SHA-256 aportado por el operador. Antes de iniciar `systemd-nspawn`, era necesario ejecutar una adquisición real, identificar un artefacto firmado, fijar todas las propiedades relevantes y repetir la descarga de forma independiente.

Las primeras pruebas también demostraron que el bootstrap privilegiado no debe depender de un keyserver. `dirmngr` y `gpg-agent` introducen procesos auxiliares y fallos de entorno que no son necesarios para verificar una firma pública cuando la autoridad ya fue inspeccionada y fijada.

## Decisión

Morimil fija en `config/arch-rootfs-release.env`:

- URL HTTPS del mirror observado;
- URL de la firma separada;
- huella primaria completa de la autoridad;
- SHA-256 de la clave pública exportada;
- SHA-256 y SHA-512 del tarball;
- tamaño exacto;
- SHA-256 de la firma;
- número de entradas del archivo;
- SHA-256 de la lista ordenada por el tarball;
- ejecución y commit de descubrimiento.

La clave pública verificada se conserva en:

```text
config/keys/archlinuxarm-build-system.asc
```

El bootstrap privilegiado:

1. valida el archivo de pin;
2. compara el SHA-256 de la clave local;
3. lee su huella sin importarla a un keyring persistente;
4. crea un keyring temporal;
5. verifica la firma mediante `gpgv`;
6. compara firma, SHA-256, SHA-512, tamaño y estructura exacta;
7. extrae en el mismo filesystem que el destino;
8. publica mediante renombrado atómico;
9. registra metadata interna y externa;
10. permite destruir completamente la publicación después de inspeccionarla.

No se permite obtener la autoridad desde un keyserver durante el bootstrap privilegiado.

## Artefacto aceptado

```text
rootfs_sha256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
rootfs_size=818293654
signing_key_sha256=6ce771e853f04a38a5b533cb33e61f877b9b06b58b6db051eb8a15d737a2332f
signature_sha256=17aca89a9de049651310f2a1ac730aea6d886ffe9c8de8c3009986938d145367
archive_entries=48789
archive_list_sha256=09534cd0ae6c2c808a2cb2586de692dce92a0e3c20072bdf0af062d846a42f7d
```

La huella primaria es:

```text
68B3537F39A313B3E574D06777193F152BDBE6A6
```

## Evidencia

La ejecución de descubrimiento `29880034099` exportó la clave después de comprobar su huella y la firma del mismo artefacto.

La ejecución independiente `29880817129`, sobre el commit `864cd5b97869b6da924b17f71dce564140eb24fe`, completó:

- nueva descarga del rootfs y la firma;
- verificación con la clave local y `gpgv`;
- coincidencia de todos los valores fijados;
- extracción de `48792` entradas de filesystem;
- tamaño extraído de `2098553789` bytes;
- identidad `ID=archarm`;
- `pacman` identificado como ELF64 AArch64;
- publicación atómica;
- metadata interna y externa;
- eliminación final del rootfs y del estado.

La ejecución no inició el contenedor ni ejecutó `pacman`.

## Consecuencias positivas

- elimina una fuente mutable de autoridad durante instalaciones privilegiadas;
- separa descubrimiento de autoridad y consumo del artefacto;
- permite auditar exactamente qué bytes fueron aceptados;
- evita dependencia de `dirmngr`, `gpg-agent` o disponibilidad de un keyserver;
- prueba publicación y destrucción sin dejar un rootfs permanente en CI;
- conserva una puerta clara antes del primer arranque de `systemd-nspawn`.

## Riesgos y límites

- la URL contiene `latest`; el pin protege contra cambios silenciosos, pero una actualización legítima requiere un nuevo ADR o actualización explícita de evidencia;
- versionar una clave no sustituye la revisión humana de su procedencia y huella;
- la validación ocurrió en un runner Ubuntu, no dentro de la imagen Debian ARM64 de producto;
- la extracción real no demuestra que systemd arranque dentro de `systemd-nspawn`;
- no se han validado límites de CPU, memoria, almacenamiento o comportamiento de fallo en ejecución;
- no se ha ejecutado software Arch ni se ha concedido red al contenedor.

## Fuentes primarias

- https://archlinuxarm.org/about/downloads
- https://archlinuxarm.org/about/package-signing
- https://www.gnupg.org/documentation/manuals/gnupg/gpgv.html
- https://www.freedesktop.org/software/systemd/man/latest/systemd-nspawn.html
