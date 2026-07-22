# ADR-0006: Ciclo de vida operacional del Arch Executor

- Estado: aceptado para validación
- Fecha: 2026-07-21

## Contexto

La Fase 2D demostró que un rootfs Arch Linux ARM AArch64 autenticado puede arrancar dentro de `systemd-nspawn`, permanecer aislado, detenerse, fallar sin derribar Debian y reconstruirse desde el mismo pin.

Esa prueba era deliberadamente destructiva y estaba diseñada para CI. No constituía todavía una interfaz operacional estable para Morimil Core ni para administración local.

## Decisión

Se define una interfaz única:

```text
scripts/morimil-arch-executor.sh
```

con seis operaciones:

```text
create
start
status
stop
destroy
rebuild
```

### Semántica

- `create` descarga, autentica, publica y prepara el rootfs, pero no lo arranca.
- `start` inicia exclusivamente un executor ya preparado y exige la política `.nspawn` confiable.
- `status` produce pares `clave=valor` estables y no ejecuta órdenes dentro de Arch.
- `stop` solicita apagado limpio y conserva rootfs y metadata.
- `destroy` solo elimina un executor detenido y se niega a borrar una política instalada que haya sido modificada fuera del repositorio.
- `rebuild` ejecuta `stop`, `destroy` y `create`; el resultado queda detenido.

## Fronteras

Debian conserva control exclusivo de:

- `/var/lib/machines`;
- metadata bajo `/var/lib/morimil`;
- política bajo `/etc/systemd/nspawn`;
- la unidad transitoria que mantiene `systemd-nspawn`;
- operaciones destructivas y privilegiadas.

Arch no puede solicitar comandos arbitrarios al host. Esta interfaz no acepta argumentos de shell ni comandos de paquete.

## Aislamiento obligatorio

El ciclo operacional reutiliza la política validada:

- `PrivateUsers=pick`;
- `NoNewPrivileges=yes`;
- raíz de solo lectura;
- estado volátil;
- red privada;
- ninguna interfaz Ethernet virtual;
- ningún bind mount;
- ninguna capacidad adicional;
- ningún puerto ni dispositivo físico expuesto.

La preparación de propietarios ocurre antes del arranque mediante una ejecución no registrada, sin red y con `PrivateUsersOwnership=chown`. El runtime utiliza después `PrivateUsersOwnership=off` sobre el rootfs ya desplazado.

## Concurrencia y fallos

Las operaciones adquieren un bloqueo exclusivo. Una segunda operación simultánea debe fallar sin modificar el estado.

`create` realiza rollback si el bootstrap o la preparación fallan. `start` elimina la unidad transitoria si el target mínimo no queda listo. `destroy` exige ausencia de máquina y servicio activos.

## Consecuencias

### Positivas

- Morimil Core podrá invocar operaciones delimitadas en lugar de construir comandos de shell.
- El estado es inspeccionable y automatizable.
- Crear, iniciar y destruir dejan de ser una única prueba monolítica.
- La reconstrucción conserva el mismo pin criptográfico.

### Negativas

- `rebuild` vuelve a descargar el rootfs completo.
- Los límites definitivos de CPU, memoria y almacenamiento siguen pendientes.
- No se habilita red, actualización mediante `pacman`, GUI ni hardware.

## Validación exigida

Una ejecución AArch64 nativa deberá demostrar:

1. `create` deja el executor detenido;
2. `start` alcanza el target mínimo;
3. `status` refleja correctamente estados ausente, detenido y activo;
4. `stop` preserva el rootfs;
5. `/var` no persiste entre arranques;
6. `rebuild` produce el mismo SHA-256 fijado y queda detenido;
7. un segundo arranque funciona;
8. `destroy` elimina rootfs, metadata y política;
9. Debian conserva boot ID, red y archivo centinela.
