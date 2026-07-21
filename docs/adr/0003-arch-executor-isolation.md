# ADR-0003: Arch Executor aislado con systemd-nspawn

- **Estado:** aceptado para la base contractual de la Fase 2; rootfs real pendiente
- **Fecha:** 2026-07-21
- **Alcance:** laboratorio ARM64 en QEMU; no concede acceso a hardware móvil

## Contexto

Morimil OS necesita ejecutar software reciente sin permitir que Arch Linux ARM administre el sistema base Debian. Ambos entornos compartirán el kernel del anfitrión, pero no compartirán raíz, gestor de paquetes, autoridad de arranque ni acceso general a dispositivos.

El ejecutor debe considerarse reemplazable y potencialmente defectuoso. Su corrupción, destrucción o fallo de arranque no puede impedir que Debian siga operativo.

Arch Linux ARM publica un rootfs AArch64 multi-plataforma y firmas separadas. La página oficial indica que las versiones se firman con la clave `68B3537F39A313B3E574D06777193F152BDBE6A6`. El MD5 publicado puede conservarse como dato de transporte, pero no se utilizará como control de autenticidad.

## Decisión

La Fase 2 utilizará `systemd-nspawn` como frontera inicial de ejecución.

La política versionada comienza con:

- `Boot=yes` para iniciar el sistema del contenedor mediante su init;
- `PrivateUsers=pick` para separar UID y GID del anfitrión;
- `NoNewPrivileges=yes`;
- raíz de solo lectura;
- estado volátil para las escrituras necesarias durante la ejecución;
- espacio de red privado;
- ausencia de interfaz virtual por defecto;
- ningún bind mount del anfitrión;
- ninguna capacidad adicional;
- ningún dispositivo, interfaz, puente, zona o puerto concedido.

La definición canónica se mantiene en:

```text
config/nspawn/morimil-arch.nspawn
```

La configuración instalada por un futuro constructor deberá residir en `/etc/systemd/nspawn/morimil-arch.nspawn`. El rootfs se almacenará bajo `/var/lib/machines/morimil-arch`; la metadata, las fuentes verificadas y el estado de reconstrucción se mantendrán fuera del rootfs bajo `/var/lib/morimil/executors/arch`.

## Fuente y verificación del rootfs

El bloque de descarga real deberá:

1. utilizar exclusivamente el rootfs oficial `ArchLinuxARM-aarch64-latest.tar.gz`;
2. descargar también su firma separada;
3. importar la clave mediante un material fijado y auditado, no mediante una búsqueda dinámica por ID corto;
4. comprobar la huella completa esperada;
5. verificar la firma antes de extraer;
6. calcular y conservar SHA-256 local del archivo exacto recibido;
7. registrar URL final, fecha, tamaño, firma, huella y SHA-256;
8. extraer en un directorio temporal y promover el rootfs de forma atómica;
9. rechazar sobrescrituras parciales y estados incompletos.

La palabra `latest` no se considerará una entrada reproducible. La primera prueba funcional puede consumirla para descubrir el formato, pero una declaración reproducible exigirá archivar o fijar el artefacto exacto por SHA-256 y conservar evidencia suficiente para recuperarlo.

## Frontera de autoridad

Debian conserva autoridad exclusiva sobre:

- kernel y módulos;
- arranque y recuperación;
- dispositivos físicos;
- red del anfitrión;
- almacenamiento persistente;
- límites de recursos;
- inicio, detención, destrucción y reconstrucción del ejecutor.

Arch no podrá:

- ejecutar `pacman` contra la raíz Debian;
- montar `/dev`, `/sys`, `/proc` o `/run` del anfitrión fuera de lo que `systemd-nspawn` prepare internamente;
- cargar módulos;
- modificar el reloj del anfitrión;
- acceder al módem, GPU, batería, cámara, sensores o almacenamiento físico;
- solicitar comandos privilegiados arbitrarios al anfitrión.

## Criterio de aceptación

La Fase 2 requerirá evidencia de que:

1. Debian inicia y permanece operativo sin el ejecutor;
2. el rootfs Arch se obtiene y autentica;
3. el contenedor alcanza un estado operativo verificable;
4. la red permanece ausente por defecto;
5. no existen montajes del anfitrión fuera de una lista permitida explícita;
6. los límites de CPU, memoria, procesos y almacenamiento se aplican desde una unidad controlada por Debian;
7. el ejecutor puede detenerse y destruirse;
8. un rootfs corrompido falla sin afectar Debian;
9. el ejecutor puede reconstruirse desde entradas verificadas;
10. las pruebas y la evidencia quedan registradas en CI.

## Consecuencias

### Positivas

- mantiene separados `apt` y `pacman`;
- convierte Arch en un componente descartable;
- reduce el radio de impacto de paquetes recientes;
- permite validar la arquitectura antes del hardware físico;
- establece reglas automáticas antes de incorporar descargas y privilegios.

### Negativas y riesgos

- `systemd-nspawn` comparte el kernel y no es una frontera equivalente a una máquina virtual;
- el arranque de un rootfs con raíz de solo lectura puede requerir ajustes explícitos y medidos;
- `PrivateUsers=pick` modifica la representación de propietarios en disco;
- la distribución rolling dificulta reproducibilidad histórica;
- una política demasiado estricta puede impedir el arranque y deberá relajarse únicamente con evidencia y pruebas de regresión.

## Alternativas descartadas

### Distrobox como base

Se descarta para esta fase porque prioriza integración y comodidad de usuario. La primera obligación es demostrar control, aislamiento, destrucción y reconstrucción.

### Podman como autoridad del sistema

No se adopta todavía. Puede evaluarse para aplicaciones sin privilegios, pero no sustituye la definición del ejecutor de sistema ni la futura autoridad de Morimil Core.

### Arch como raíz principal

Se descarta porque ampliaría la variación del sistema base y entregaría a `pacman` control sobre componentes críticos del teléfono.

### Compartir dispositivos desde el inicio

Se descarta. Cualquier dispositivo se habilitará individualmente después de una amenaza documentada, una necesidad concreta y una prueba negativa.

## Fuentes primarias

- https://archlinuxarm.org/about/downloads
- https://man.archlinux.org/man/systemd-nspawn.1.en
- https://man.archlinux.org/man/systemd.nspawn.5.en
- https://www.freedesktop.org/software/systemd/man/systemd.nspawn.html
