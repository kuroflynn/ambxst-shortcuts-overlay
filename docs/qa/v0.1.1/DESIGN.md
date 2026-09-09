# Decisiones de hardening v0.1.1

Baseline: v0.1.0 / 6ec3870. Diseño previo a modificar las transacciones.

## QA-001: comparación de alternativas

| Alternativa | Garantía real y carreras | Limpieza / idempotencia | Complejidad, recuperación y UX |
|---|---|---|---|
| Cuarentena duradera del inode retirado | Conserva escrituras posteriores por FD abierto. No congela el contenido ni protege frente a alguien que borre la propia recuperación. | No puede purgarse automáticamente usando solo cmp o tiempo. El usuario debe detener escritores y revisar antes de eliminar. Un segundo uninstall no crea otra entrada. | Sencilla en GNU/Linux, recuperación por ruta explícita; retiene archivos deliberadamente. |
| Hardlink duradero | Conserva el mismo inode incluso si cambia el nombre publicado. Se mantiene al hacer rollback; no es un snapshot inmutable. Requiere mismo filesystem. | Igual limitación de purga; un install idempotente no crea otro link. | Útil durante publicación y restauración para evitar retirar la última referencia. |
| Copia independiente | Conserva lo copiado, pero no recoge escrituras posteriores al inode original. | Puede limpiarse según política de backups; no resuelve la reproducción del FD. | No elegida como protección única. |
| Debilitar la garantía a “nadie escribe durante uninstall” | Hace desaparecer el incumplimiento del contrato, pero no protege al usuario cuando ocurre el fallo ya demostrado. | No deja recuperación; UX simple a costa de pérdida potencial. | No elegida como solución principal. Sí es necesario precisar el límite frente a actores arbitrarios. |
| Locks / más cmp / chmod | flock coordina scripts que usan el mismo lock; no bloquea editores ajenos. Más cmp mueve la carrera; chmod no revoca FDs ya abiertos. | Ninguna de estas técnicas autoriza una purga segura. | flock complementa la solución para serializar deployments cooperantes. |

Elección: recuperación duradera de inodes y publicaciones/restauraciones mediante
hardlinks de destino exacto. Nunca purgar automáticamente archivos de recuperación,
ni al tener éxito ni en rollback. La recuperación queda dentro del source target,
se identifica en salida y se documenta. No es un backup inmutable ni una garantía
de persistencia ante corte eléctrico. La limpieza es una decisión manual después
de detener escritores, revisar contenido y disponer de un checkpoint si procede.

## QA-002: rutas exactas

Usar `ln -PT` para publicar/restaurar y `mv --no-copy -T --update=none-fail`
para retirar: sin sobrescribir, interpretar destinos como directorios ni convertir
un rename en copy+unlink entre filesystems. Comprobar tipo, identidad y contenido
después de las operaciones. Si el contenido cambia, conservar ambas referencias
y diagnosticar; no “reparar” sobrescribiendo el destino concurrente.

## QA-003: anclar las operaciones a directorios abiertos

Rechazar enlaces, incluidos colgantes, en los componentes del despliegue. Abrir
los directorios relevantes y utilizar `/proc/<pid>/fd/<fd>/nombre` para las
operaciones sobre archivos: reemplazar después un ancestro por un symlink no
redirige estas operaciones al destino del enlace. Revalidar la ubicación física y
la identidad de los directorios antes/después de etapas; abortar al detectar cambios.
Serializar install/uninstall cooperantes con flock sobre el descriptor de la raíz,
sin archivo de lock permanente. Verify conserva su responsabilidad de lectura.

Límite explícito: Bash no ofrece openat2/rename condicional por inode como una
transacción única. Un actor con los mismos permisos puede mover un directorio
abierto entero fuera de la raíz entre dos syscalls, cambiar montajes, destruir
recuperaciones o reemplazar la herramienta ejecutada. No se promete aislamiento
frente a ese actor. Se protege contra enlaces preexistentes y sustituciones de
ancestros por symlinks; si un directorio cambia de ubicación, se detiene el trabajo
y se identifica la recuperación sin seguir la ruta sustituta. Los archivos del
patch siguen sujetos a los checks de Git y revisión de ancestros: no se promete
transacción atómica de todo el árbol ante escritores arbitrarios o SIGKILL.

Todo ello usa herramientas presentes en el entorno Arch objetivo: Bash, GNU
coreutils, Git y flock (util-linux). No hay servicio ni dependencia nueva en el
runtime del overlay. Las pruebas de instalación solo operan sobre temporales.

## CR-001: etapa por descriptor abierto de creación exclusiva (adenda post-revisión, ronda 2)

`install -T` reabría la ruta del candidato (leaf TOCTOU). Solución Bash-only
definitiva en `stage_file()` de `common.sh`, que **reemplaza** el flujo anterior
`mktemp` + reapertura por nombre (instalado en la ronda 1) y se valida por
corrección de producto con la regresión `staging-regular-replacement`:

1. `scripts/gen_candidate` imprime `DIR/.NOMBRE.install.TOKEN` **sin crear**; el
   token se forma con `$RANDOM`/`$SRANDOM`/`$BASHPID`.
2. La creación es una única apertura atómica `set -o noclobber` + `exec {fd}>`
   (`O_WRONLY|O_CREAT|O_EXCL`, confirmada contra `redir.c` de bash 5.3.15). Un
   nombre ya ocupado (regular, symlink, dir) devuelve `EEXIST` y **se abandona y
   se reintenta** (≤ 8); nunca se borra, trunca ni sigue el nodo que ganó. Un
   chequeo `-e`/`-L` previo evita abrir un FIFO/device preexistente que
   bloquearía; `O_EXCL` cierra la ventana create→open.
3. Preparación única verificada **solo por FD** (`/proc/<pid>/fd/<fd>`): `cat
   source >&fd`, `cmp -s`, `chmod 0644`; `umask 077` deja el pre-chmod en 0600.
   Cualquier fallo cierra el FD y aborta sin publicar staging parcial.
4. `device+inode` se verifican **después** del create (el nombre debe seguir
   resolviendo al objeto abierto) como chequeo extra, no como identidad
   primaria.
5. `set -C` y `umask 077` viven en un subshell de sustitución de comando; no se
   filtran a `install.sh`. El silenciamiento del error del open se hace con una
   agrupación (`{ exec {fd}>...; } 2>/dev/null`) para no dejar un `2` redirigido
   permanentemente en el subshell.

El retry está acotado (8 intentos); el prefijo `.NOMBRE.install.` conserva el glob
usado por los tests. No se tocan otros pasos de `install.sh`. Límite de frontera: un actor **same-UID/root** con acceso
al dir privado `0700` plantando objetos especiales deliberadamente, o un mount,
SIGKILL/pérdida de energía o manipulación continua del FS queda fuera de
alcance; no se añadieron más rondas de hardening.

## CR-002: rechazo fail-closed de LF/CR en el target (adenda post-revisión)

`reject_control_target()` rechaza únicamente `\n` y `\r` en el candidato, con
`printf '%q'` en el diagnóstico, en un único punto de estrangulamiento en
`resolve_ambxst_target()` que cubre argumento, `AMBXST_SOURCE_DIR`, registro
`shell_repo` y fallback. Espacios, tabulaciones y UTF-8 siguen siendo válidos;
no se amplía a «solo ASCII imprimible», que descartaría destinos legítimos.
