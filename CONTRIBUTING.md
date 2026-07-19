# Contribuir a Morimil OS

Morimil OS está en una fase temprana. La prioridad es producir evidencia reproducible, no aparentar avance mediante archivos vacíos o componentes declarados sin pruebas.

## Flujo de trabajo

1. No trabajar directamente sobre `main`, salvo la inicialización excepcional del repositorio.
2. Crear una rama con un nombre descriptivo:
   - `foundation/...`
   - `build/...`
   - `core/...`
   - `shell/...`
   - `executor/...`
   - `docs/...`
   - `fix/...`
3. Abrir un pull request con alcance limitado.
4. Documentar cómo se probó el cambio.
5. No fusionar con pruebas fallidas o riesgos importantes ocultos.

## Requisitos de un pull request

Cada PR debe indicar:

- problema concreto;
- solución aplicada;
- archivos y componentes afectados;
- comandos exactos de construcción o prueba;
- resultado observado;
- riesgos y limitaciones restantes;
- fuentes técnicas cuando la decisión depende de comportamiento externo.

## Decisiones arquitectónicas

Las decisiones estructurales deben documentarse en `docs/adr/`.

Un ADR debe incluir:

- contexto;
- decisión;
- alternativas consideradas;
- consecuencias positivas y negativas;
- criterios de validación;
- fuentes primarias.

No se reescribe silenciosamente un ADR aceptado. Si una decisión cambia, se crea otro ADR que la reemplaza.

## Reproducibilidad

Una construcción válida debe:

- partir de entradas identificables;
- fijar versiones o registrar exactamente qué se resolvió;
- verificar firmas o sumas de artefactos descargados;
- producir registros;
- fallar de forma explícita;
- poder repetirse desde un entorno limpio.

Evita descargar y ejecutar scripts remotos directamente mediante patrones como `curl ... | sh`.

## Seguridad

- No incluir claves, tokens, contraseñas ni credenciales.
- No conceder acceso general a dispositivos al Arch Executor.
- No ejecutar como `root` cuando no sea necesario.
- No aceptar paquetes del AUR como confiables por defecto.
- No desactivar verificaciones de firmas para resolver fallos de construcción.
- No ocultar firmware propietario o dependencias cerradas.

Los problemas de seguridad no deben publicarse con detalles explotables en un issue público. Hasta definir un canal privado formal, contacta directamente al propietario del repositorio.

## Calidad técnica

No se aceptarán como implementación:

- pseudocódigo presentado como código funcional;
- archivos vacíos usados para simular estructura;
- pruebas que siempre devuelven éxito;
- capturas sin comandos ni registros reproducibles;
- compatibilidad declarada sin probar el hardware;
- nombres de servicios sin contratos ni comportamiento definido.

## Idioma y estilo

La documentación principal puede escribirse en español. Código, identificadores, mensajes de error y contratos deben usar nombres técnicos consistentes y comprensibles internacionalmente.
