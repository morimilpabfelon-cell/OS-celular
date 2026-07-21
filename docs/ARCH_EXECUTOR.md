# Arch Executor

## Estado

La Fase 2 está en desarrollo. Este bloque establece únicamente la política de aislamiento y sus pruebas contractuales. Todavía no descarga, extrae ni arranca un rootfs Arch Linux ARM real.

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

## Rutas previstas

```text
/etc/systemd/nspawn/morimil-arch.nspawn
/var/lib/machines/morimil-arch/
/var/lib/morimil/executors/arch/
```

El rootfs se mantendrá separado de su metadata y de la evidencia de descarga. Ninguna ruta de Arch podrá convertirse en raíz de Debian ni ser administrada por `apt`.

## Siguiente bloque verificable

El siguiente cambio deberá implementar un descargador separado que:

1. obtenga el rootfs AArch64 desde la fuente oficial;
2. verifique la firma con una huella completa fijada;
3. calcule SHA-256 del archivo recibido;
4. extraiga en un directorio temporal;
5. publique el rootfs mediante una operación atómica;
6. conserve metadata suficiente para destruirlo y reconstruirlo;
7. no inicie todavía el contenedor si la autenticidad no está demostrada.

## Fuera de alcance actual

- acceso a GPU, módem, cámara, batería, sensores o audio;
- red del anfitrión;
- integración de aplicaciones gráficas;
- montajes de directorios personales;
- límites definitivos de recursos;
- actualización automática mediante `pacman`;
- compatibilidad con teléfono físico.
