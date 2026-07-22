# Arch Executor

## Estado

La Fase 2 está en desarrollo. La política de aislamiento, el pin de autoridad y artefacto, y el bootstrap real del rootfs AArch64 están validados. Todavía no existe evidencia de un arranque del Arch Executor mediante `systemd-nspawn`.

No debe interpretarse una descarga y extracción verde como evidencia de aislamiento en tiempo de ejecución.

## Frontera inicial

La configuración canónica es:

```text
config/nspawn/morimil-arch.nspawn
```

La política exige:

- arranque mediante el init del contenedor;
- espacio privado de UID y GID;
- prohibición de adquirir nuevos privilegios;
- raíz de solo lectura;
- estado temporal para las escrituras de ejecución;
- espacio de red privado;
- ninguna interfaz virtual por defecto;
- ningún bind mount del anfitrión;
- ninguna capacidad adicional;
- ningún puerto ni interfaz física expuestos.

La política se comprueba con:

```sh
sh scripts/check-arch-executor-policy.sh
```

Las pruebas negativas se ejecutan con:

```sh
sh tests/shell/test-arch-executor-policy.sh
```

## Rootfs autenticado y fijado

Los valores aprobados están en:

```text
config/arch-rootfs-release.env
config/keys/archlinuxarm-build-system.asc
```

El bootstrap se ejecuta mediante:

```sh
sudo sh scripts/bootstrap-arch-rootfs.sh
```

El bootstrap:

- usa HTTPS para el tarball y la firma;
- fija la huella completa `68B3537F39A313B3E574D06777193F152BDBE6A6`;
- verifica el SHA-256 de la clave local;
- verifica la firma con `gpgv`, sin keyserver ni agente;
- exige SHA-256, SHA-512, tamaño y estructura exactos;
- rechaza rutas absolutas o traversal dentro del archivo;
- extrae como root para preservar propietarios, ACL y xattrs;
- publica dentro de `/var/lib/machines` mediante renombrado atómico;
- conserva metadata dentro y fuera del rootfs;
- no inicia el contenedor.

La ejecución real `29880817129` publicó e inspeccionó el rootfs, confirmó `ID=archarm` y un `pacman` ELF64 AArch64, y después eliminó tanto rootfs como estado.

La documentación completa está en `docs/ARCH_ROOTFS_BOOTSTRAP.md`, ADR-0004 y ADR-0005.

## Rutas previstas

```text
/etc/systemd/nspawn/morimil-arch.nspawn
/var/lib/machines/morimil-arch/
/var/lib/morimil/executors/arch/
```

El rootfs se mantiene separado de su metadata y de la evidencia de descarga. Ninguna ruta de Arch podrá convertirse en raíz de Debian ni ser administrada por `apt`.

## Siguiente bloque verificable

El siguiente cambio deberá iniciar el rootfs validado mediante `systemd-nspawn` y conservar evidencia de:

1. aplicación de la política `.nspawn`;
2. inicio del init del contenedor;
3. userspace AArch64 operativo;
4. red sin interfaz utilizable;
5. raíz no modificable fuera del estado permitido;
6. ausencia de bind mounts y dispositivos no autorizados;
7. parada controlada;
8. fallo forzado sin afectar Debian;
9. destrucción y reconstrucción desde el mismo pin.

## Fuera de alcance actual

- acceso a GPU, módem, cámara, batería, sensores o audio;
- red del anfitrión;
- integración de aplicaciones gráficas;
- montajes de directorios personales;
- límites definitivos de recursos;
- actualización automática mediante `pacman`;
- compatibilidad con teléfono físico.
