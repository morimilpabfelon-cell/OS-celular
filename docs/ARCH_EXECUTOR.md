# Arch Executor

## Estado

La Fase 2 está en desarrollo. La política de aislamiento y el bootstrap autenticado del rootfs tienen pruebas contractuales. Todavía no existe evidencia registrada de una descarga real ni de un arranque del Arch Executor.

No debe interpretarse una validación estática verde como evidencia de que el ejecutor funciona.

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

## Bootstrap autenticado

El rootfs oficial se procesa mediante:

```sh
sudo env \
  ARCH_ROOTFS_EXPECTED_SHA256='<64 hexadecimales>' \
  sh scripts/bootstrap-arch-rootfs.sh
```

El bootstrap:

- usa HTTPS para el tarball y la firma;
- fija la huella completa `68B3537F39A313B3E574D06777193F152BDBE6A6`;
- obtiene la clave mediante HKPS;
- verifica la firma GPG;
- exige el SHA-256 exacto;
- rechaza rutas absolutas o traversal dentro del archivo;
- extrae como root para preservar propietarios, ACLs y xattrs;
- publica dentro de `/var/lib/machines` mediante renombrado atómico;
- conserva metadata dentro y fuera del rootfs;
- no inicia el contenedor.

La documentación completa está en `docs/ARCH_ROOTFS_BOOTSTRAP.md` y ADR-0004.

## Rutas previstas

```text
/etc/systemd/nspawn/morimil-arch.nspawn
/var/lib/machines/morimil-arch/
/var/lib/morimil/executors/arch/
```

El rootfs se mantiene separado de su metadata y de la evidencia de descarga. Ninguna ruta de Arch podrá convertirse en raíz de Debian ni ser administrada por `apt`.

## Siguiente bloque verificable

El siguiente cambio deberá ejecutar una descarga real con SHA-256 fijado y conservar evidencia de:

1. URL y firma recibidas;
2. huella completa verificada;
3. SHA-256 esperado y observado;
4. versiones de curl, GnuPG y bsdtar;
5. publicación del rootfs;
6. identidad AArch64 del userspace;
7. inicio y parada mediante la política `.nspawn`;
8. fallo, destrucción y reconstrucción sin afectar Debian.

## Fuera de alcance actual

- acceso a GPU, módem, cámara, batería, sensores o audio;
- red del anfitrión;
- integración de aplicaciones gráficas;
- montajes de directorios personales;
- límites definitivos de recursos;
- actualización automática mediante `pacman`;
- compatibilidad con teléfono físico.
