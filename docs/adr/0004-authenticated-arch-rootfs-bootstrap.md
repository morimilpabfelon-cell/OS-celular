# ADR-0004: Bootstrap autenticado y atómico del rootfs Arch Linux ARM

- **Estado:** aceptado para implementación contractual de Fase 2
- **Fecha:** 2026-07-21
- **Alcance:** adquisición y publicación del userspace AArch64; no arranque del contenedor

## Contexto

El Arch Executor necesita un rootfs AArch64 separado de Debian. El artefacto oficial de Arch Linux ARM se publica bajo un nombre `latest`, por lo que su nombre no identifica de forma permanente el contenido descargado.

La página oficial publica una firma separada y declara que todas las versiones usan la clave de firma del sistema de construcción con huella completa:

```text
68B3537F39A313B3E574D06777193F152BDBE6A6
```

La firma demuestra procedencia respecto de esa clave. No sustituye el bloqueo del contenido exacto. Por ello, el bootstrap exige también un SHA-256 completo proporcionado explícitamente para cada ejecución.

## Decisión

El bootstrap:

1. acepta únicamente URLs HTTPS para el tarball;
2. obtiene la firma desde la misma URL con sufijo `.sig`;
3. obtiene la clave mediante HKPS usando la huella completa fijada;
4. verifica que la huella importada coincide exactamente;
5. verifica la firma separada antes de extraer;
6. compara el SHA-256 recibido con un valor obligatorio de 64 caracteres;
7. rechaza nombres de archivo absolutos o con componentes `..`;
8. extrae con `bsdtar` como root para conservar propietarios, ACLs y atributos extendidos;
9. exige `/etc/os-release` y un `/usr/bin/pacman` ejecutable;
10. publica el rootfs mediante `rename` dentro del mismo sistema de archivos;
11. conserva metadata dentro del rootfs y en el estado externo del ejecutor;
12. no inicia el contenedor.

La ruta predeterminada es:

```text
/var/lib/machines/morimil-arch
```

La metadata externa se publica en:

```text
/var/lib/morimil/executors/arch/rootfs-source.env
```

## Invariantes

- el destino debe estar ausente antes de comenzar;
- la metadata previa no puede sobrescribirse silenciosamente;
- un fallo de red, firma, huella, SHA-256, listado o extracción no publica el destino;
- el tarball y la firma permanecen en un directorio temporal privado;
- la raíz Debian nunca es un destino válido;
- `pacman` nunca administra la raíz Debian;
- el nombre `latest` no se considera una versión fijada;
- MD5 no se utiliza como evidencia de integridad.

## Criterio de aceptación de este bloque

La implementación contractual debe demostrar mediante mocks y pruebas unitarias:

- rechazo de SHA-256 ausente o mal formado;
- rechazo de HTTP y keyservers sin HKPS;
- rechazo de destinos fuera de las raíces permitidas;
- rechazo de destinos ya existentes;
- rechazo de rutas absolutas o con traversal en el archivo;
- comprobación de la huella completa;
- comprobación de la firma;
- comprobación del SHA-256;
- creación de metadata;
- publicación atómica sin arrancar el contenedor.

## Evidencia pendiente

Este ADR no afirma que el rootfs oficial haya sido descargado o arrancado. La siguiente ejecución real deberá conservar:

- URL efectiva;
- firma recibida;
- huella verificada;
- SHA-256 fijado y observado;
- versión de GnuPG, curl y bsdtar;
- listado de validación;
- metadata publicada;
- resultado de arranque aislado en un bloque posterior.

## Consecuencias

### Positivas

- separa autenticidad de reproducibilidad;
- evita confiar en un alias mutable;
- impide publicación parcial del rootfs;
- conserva procedencia suficiente para destruir y reconstruir;
- mantiene el arranque fuera del alcance hasta validar la adquisición.

### Costes y límites

- requiere privilegios root para preservar correctamente el rootfs;
- depende de disponibilidad de HTTPS, HKPS y la fuente oficial;
- el keyserver es transporte, no autoridad: la autoridad es la huella fijada;
- un SHA-256 correcto no prueba que el rootfs pueda arrancar;
- la publicación del rootfs y la copia externa de metadata no constituyen una transacción única entre directorios, por lo que la metadata canónica también se incrusta dentro del rootfs.

## Fuentes primarias

- https://archlinuxarm.org/about/downloads
- https://archlinuxarm.org/about/package-signing
- https://archlinuxarm.org/platforms/armv8/generic
