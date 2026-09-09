# QA de hardening — candidato v0.1.1

Fecha de cierre: 2026-09-07. Baseline: `v0.1.0`, commit `6ec3870e23160a799feac7e64deaa8b47d26ce52`, rama `main`.

**Resultado: preparado para revisión y una nueva ronda QA; validación aislada PASS.** No se creó la release ni un tag. T018–T021 de la sesión real **NO EJECUTADOS**. La validación runtime inicial de v0.1.0 no sustituye esa validación para este candidato.

## A. Resumen

| Hallazgo | Estado | Resultado y alcance |
|---|---|---|
| QA-001 | FIXED | Se conservan inodes retirados y hardlinks preparados después del commit/rollback. Escrituras mediante FD después del último cmp y después de terminar el proceso siguen accesibles. Limpieza manual. |
| QA-002 | FIXED | `ln -PT`, comprobación de archivo regular, mismo inode/contenido y directorios anclados. Directorios, symlinks y archivos concurrentes se conservan y provocan rechazo. |
| QA-003 | FIXED | Se rechazan ancestros simbólicos y se anclan operaciones del overlay con FDs de directorio. Pasan sustituciones de widgets, shortcuts, modules y services, con preimágenes válidas fuera para los dos últimos. Limitaciones de mismo usuario detalladas abajo. |
| QA-004 | FIXED | Listas reales/Qt, límites de consumo, normalización de nombres y contención de excepciones en build y refreshData. |
| QA-005 | FIXED | Clasificación por key/evento real; los nombres humanos no descartan combinaciones válidas. |
| QA-006 | FIXED | `Text.Wrap` para etiquetas; sonda del delegate real en 1/2/3 columnas, textos normales/largos, alturas y pills. |
| QA-007 | FIXED | Bash analiza cada script por separado; regresión roja con el método antiguo y verde con el actual. |
| QA-008 | FIXED | Clasificación común para verify/install/uninstall: regular, enlace válido/colgante, directorio, ausente y parcial. |
| QA-009 | FIXED | `total` conserva su significado de filas después de compactar; UI: «1 fila de atajos» / «N filas de atajos». |
| QA-010 | FIXED | Maps sin prototipo y consultas de propiedades propias; constructor, toString y __proto__ permanecen visibles. |
| QA-011 | FIXED | Contrato corregido: estructura esperada y raíz Git, sin afirmar identidad/procedencia inequívoca. No se restringen forks por origen remoto. |

QA-012/013 siguen siendo INFO: selección/versionado del linter documentados; **v0.1.1 probado contra Ambxst 1.2.6**, exclusivamente en validación aislada. Aplicabilidad textual no significa compatibilidad semántica con otra versión.

## B. Decisiones de diseño

La comparación previa está en [DESIGN.md](DESIGN.md).

**QA-001.** Una copia independiente no captura escrituras posteriores al inode original; más cmp desplaza la carrera y chmod no revoca FDs abiertos. Debilitar el contrato a «nadie escribe» no protege del fallo reproducido. Se eligieron recuperación duradera y hardlinks: ningún camino exitoso ni de rollback borra automáticamente los archivos retenidos. `flock` coordina exclusivamente los scripts cooperantes.

Cada instalación efectiva mantiene `TARGET_ROOT/.ambxst-shortcuts-recovery/install.XXXXXX/`. La desinstalación mueve los nombres runtime a `uninstall.XXXXXX/`. Las restauraciones crean un enlace exacto y conservan también la recuperación. Un segundo install/uninstall idempotente no crea otra entrada. Un fallo puede dejar preparación parcial o `retired-NAME` en la ruta indicada. La eliminación solo se considera manualmente después de detener escritores y revisar/respaldar el contenido. Son referencias mutables, no snapshots inmutables ni persistencia garantizada frente a corte eléctrico.

**QA-002.** `ln -PT` impide tratar el destino aparecido como directorio y no sobrescribe un archivo existente. Se comprueban tipo, identidad, contenido y ubicación anclada. `mv --no-copy -T --update=none-fail` rechaza colisiones y evita convertir un movimiento entre filesystems en copy+unlink. Se preserva material ambiguo y se identifica la recuperación. Los tests ejecutan las primitivas GNU reales tras crear el destino concurrente; no simulan simplemente un código de error.

**QA-003.** Los scripts rechazan enlaces en modules/services/widgets/shortcuts y recuperación, y exigen archivos compartidos regulares. Abren directorios y operan mediante `/proc/<pid>/fd/<fd>/nombre`; sustituir el nombre de un ancestro no cambia el directorio utilizado por esas operaciones. Se verifica ubicación física e identidad antes/después de etapas y se aborta ante cambios. Git sigue aplicando el parche acotado con sus checks; las sustituciones de modules/services ensayadas son rechazadas sin cambiar las preimágenes externas.

No se eligió afirmar aislamiento absoluto: un proceso con iguales permisos puede mover un directorio abierto fuera de la raíz entre syscalls, alterar mounts, destruir la recuperación o escribir archivos compartidos mientras Git actúa. Bash/Git no ofrecen una transacción atómica de todo el árbol ni comparación-condición-rename por inode en un solo paso. Estas limitaciones están reflejadas en README, REQUIREMENTS y AGENTS. No se afirma «cero escrituras externas» frente a esos actores; sí se comprobó ausencia de escrituras externas en los escenarios que cubre el contrato.

Se mantuvieron los cinco archivos de despliegue existentes y el patch original. Sin features nuevas, servicio, dependencia runtime del overlay, CI ni LICENSE.

## C. Archivos modificados

El inventario exacto del candidato aparece al final de este apartado. `docs/qa/v0.1.0/` ya estaba sin seguimiento al retomar el trabajo y se preservó completo; no es una modificación de este candidato. El workspace, la imagen y el patch no cambiaron.

Archivos seguidos modificados:

```text
AGENTS.md
CHANGELOG.md
README.md
REQUIREMENTS.md
scripts/common.sh
scripts/install.sh
scripts/uninstall.sh
scripts/verify.sh
src/modules/widgets/shortcuts/ShortcutData.js
src/modules/widgets/shortcuts/ShortcutsOverlay.qml
tests/fixtures/fs-wrapper.sh
tests/transactional-scripts.test.sh
```

Archivos nuevos del candidato:

```text
docs/qa/v0.1.1/DESIGN.md
docs/qa/v0.1.1/REPORT.md
docs/qa/v0.1.1/evidence/bash-red-green.log
docs/qa/v0.1.1/evidence/compatibility-historical.log
docs/qa/v0.1.1/evidence/deployment.log
docs/qa/v0.1.1/evidence/final-checks.json
docs/qa/v0.1.1/evidence/full-tree-cycle.json
docs/qa/v0.1.1/evidence/hardening.log
docs/qa/v0.1.1/evidence/historical-replay.json
docs/qa/v0.1.1/evidence/parser-historical.json
docs/qa/v0.1.1/evidence/preservation.json
docs/qa/v0.1.1/evidence/qml-historical.log
docs/qa/v0.1.1/evidence/qml-lists.log
docs/qa/v0.1.1/evidence/qml.log
docs/qa/v0.1.1/evidence/shell-historical.log
docs/qa/v0.1.1/evidence/suite.log
docs/qa/v0.1.1/evidence/transactional.log
docs/qa/v0.1.1/replay-historical.py
tests/deployment.test.py
tests/fixtures/race-wrapper.py
tests/full-tree-cycle.test.py
tests/hardening.test.js
tests/qml.test.py
tests/run.sh
tests/verify.test.sh
```

## D. Comandos y resultados

Se ejecutaron todos los tests originales y las nuevas regresiones. Los logs muestran los casos individuales; los conteos distinguen aserciones de casos Qt.

| Comando ejecutado desde la raíz | Resultado | Casos / evidencia |
|---|---|---|
| `node tests/shortcut-data.test.js` | PASS | 15 comprobaciones originales; también ejecutadas por verify y la suite. |
| `node tests/hardening.test.js` | PASS | 29 regresiones: listas falsas/excesivas, presupuesto, profundidad/ciclos, nombres, hardware, prototypes, métrica y refresh. [Log](evidence/hardening.log). |
| `bash tests/verify.test.sh` | PASS | 3: control positivo y sintaxis inválida en uninstall y fixture distintos de common, siempre en copias. [Rojo/verde](evidence/bash-red-green.log). |
| `bash tests/transactional-scripts.test.sh` | PASS | 25 casos originales. Se adaptó únicamente la localización de cuarentena y el reconocimiento de alias `/proc` en fixtures. [Log](evidence/transactional.log). |
| `python3 tests/deployment.test.py` | PASS | 30: lock cooperante, ciclo, 4 escrituras FD, 6 destinos concurrentes, 4 sustituciones de ancestros, 10 enlaces estáticos y 4 estados de archivo. [Log final](evidence/deployment.log). |
| `python3 tests/qml.test.py` | PASS | 7 pruebas funcionales (secuencias Qt + 6 variantes de filas), más init/cleanup: Qt informa 9 PASS, 0 FAIL. Extrae el delegate canónico y sustituye solo dependencias visuales externas. [Log](evidence/qml.log). |
| `bash tests/run.sh` | PASS | Ejecutó parser, hardening, mutaciones, 25 transaccionales, 29 deployment y Qt. Luego se añadió el caso de lock y se repitió deployment completo: 30 PASS. [Log de suite](evidence/suite.log). |
| `python3 tests/full-tree-cycle.test.py /home/kuroflynn/.local/src/ambxst` | PASS | Lee únicamente el tag y crea su destino en /tmp. 7 pasos, 1.271 archivos originales idénticos byte a byte. [Evidencia completa](evidence/full-tree-cycle.json). |
| `node docs/qa/v0.1.0/parser-audit.js` | 135 PASS, 2 expectativas históricas obsoletas, 14 observaciones | Incluye 1.000 configuraciones de preservación de familias. Los 2 FAIL esperaban descartar teclas normales por su nombre: conducta corregida por QA-005. [JSON](evidence/parser-historical.json). |
| `python3 docs/qa/v0.1.0/shell-audit.py` | Interrupción esperada del harness antiguo | Su primer ciclo termina pero la aserción de árbol exactamente vacío de recuperaciones contradice la retención nueva. No se declara la auditoría histórica completa como PASS. [Log](evidence/shell-historical.log). |
| `python3 docs/qa/v0.1.0/compatibility-audit.py /home/kuroflynn/.local/src/ambxst 1.2.6` | Interrupción esperada del harness antiguo | Los 7 comandos terminan con éxito; su igualdad global de hashes incluye recuperaciones nuevas. El nuevo full-tree test comprueba bytes originales y footprint documentado. [Log](evidence/compatibility-historical.log). |
| `python3 docs/qa/v0.1.1/replay-historical.py` | PASS | 6 ataques originales con sus primitivas reales. Adaptaciones explícitas: aliases físicos /proc, nuevas rutas de recuperación y copia del nuevo test puro en fixture completo. [JSON](evidence/historical-replay.json). |
| `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input docs/qa/v0.1.0/tst_text.qml` | PASS de la observación antigua | 2 pruebas + init/cleanup = 4. Confirma que el WordWrap fijo del probe histórico desborda; no prueba el código corregido. El probe nuevo sí lo hace. [Log](evidence/qml-historical.log). |
| `git diff --check` | PASS | Sin errores de whitespace. [Checks](evidence/final-checks.json). |

Además, una sonda temporal Qt ejecutada con `qmltestrunner -input /tmp/ambxst-qml-list-probe` refutó el supuesto `Array.isArray(list)` (1 FAIL deliberado de investigación): Qt 6 devuelve `[object V4Sequence]`. Se usó ese resultado para la implementación y el test Qt permanente posterior pasa. [Evidencia](evidence/qml-lists.log).

Para reproducir el rojo de QA-007 se copió el proyecto a un temporal y se sustituyó únicamente allí el loop actual por el antiguo `bash -n` multioperando; `bash tests/verify.test.sh` detectó que ese verify aceptaba sintaxis inválida. El mismo comando sobre el proyecto actual dio las 3 comprobaciones verdes. Ningún script original se corrompió para estas mutaciones.

### Verificación y ciclo completo

El full-tree test leyó Ambxst `1.2.6`, commit `54f90d63d139e410d8987d21805fac4659c1ba77`, mediante `git archive`; inicializó Git solo en el temporal, sin commit. Ejecutó:

```text
scripts/verify.sh TEMP       exit 0
scripts/install.sh TEMP      exit 0
scripts/verify.sh TEMP       exit 0
scripts/install.sh TEMP      exit 0
scripts/uninstall.sh TEMP    exit 0
scripts/verify.sh TEMP       exit 0
scripts/uninstall.sh TEMP    exit 0
```

El test comparó los bytes y tipos de todos los originales, no solo el diff Git: **1.271 archivos idénticos**. Después había únicamente la raíz de recuperación, dos subdirectorios (install/uninstall) y cuatro rutas de archivos documentadas. No quedaron preparaciones ocultas, directorios huérfanos, symlinks añadidos ni archivos externos al destino temporal. Los nombres aleatorios exactos y salidas de los siete comandos están en el JSON.

`verify.sh` ejecutó `/usr/lib/qt6/bin/qmllint` **6.11.2**, con exit 0 y advertencias por el contexto `qs.*`/Quickshell no resuelto estáticamente. Esto no se contó como runtime PASS ni como ausencia de warnings. Preferencia implementada: qmllint6 → ruta Qt 6 de Arch → qmllint de PATH (aquí Qt 5, versión reportada 1.0). Bash 5.3.15, Node 24.12, Git 2.55, coreutils 9.11 y util-linux 2.42.3; no se instaló ningún paquete.

## E. Reproducciones QA y regresión

- **real-verify-fd-write-uninstall-final:** se dispara el ataque original después del último cmp del archivo; uninstall termina y el contenido editado mantiene un inode alcanzable. Las regresiones permanentes amplían a ambos archivos y a escrituras después de salir el proceso.
- **publish-directory / publish-link:** el destino concurrente permanece intacto, no se crea `Nombre.qml/Nombre.qml` ni contenido fuera de la raíz; ln real falla. Variante nueva: destino regular.
- **restore-directory / restore-link:** rollback no pisa ni interpreta el destino como carpeta; mantiene también la recuperación y reporta rollback incompleto. Variante nueva: archivo regular y verificación final real antes de inyectar fallo.
- **modify-before-move:** se conserva y restaura el contenido concurrente; no se elimina por tratarse de una copia inicialmente canónica.
- **Ancestros:** verify/install/uninstall rechazan symlinks válidos/colgantes en cinco componentes; sustituciones concurrentes de cuatro ancestros abortan. Para Git se colocan preimágenes válidas fuera, de modo que el rechazo no depende de que falten archivos.
- **Parser histórico:** los objetos length ya devuelven error sin agotar el timeout; nombres numéricos no provocan localeCompare inválido; ids con nombres de prototype permanecen; las 1.000 familias generadas conservan sus alternativas. El cambio de expectativas de nombres hardware está señalado, no ocultado.
- **QML:** el probe antiguo sigue mostrando el defecto de WordWrap. El nuevo probe toma el delegate canónico corregido y comprueba anchura de texto, altura de fila y pills en las tres distribuciones. Modelos con list<string>, list<var> y QtObject son consumidos correctamente.
- **Métrica:** diez workspaces compactados dan una fila, cuyo rótulo es singular; el plural usa filas y no acciones.

## F. Riesgos y validaciones pendientes

1. T018–T021 reales (toggle/Esc, navegación/scroll, foco/multimonitor y convivencia de overlays) no se ejecutaron. La sesión, Ambxst, Quickshell y Hyprland no se recargaron. La sonda Qt aislada no reemplaza esos checks.
2. Recuperaciones se acumulan intencionalmente. Son inodes mutables compartidos mediante hardlinks; borrar o editar esa recuperación requiere revisión humana. No hay purga automática ni garantía ante procesos que destruyan las referencias retenidas.
3. Un proceso con iguales permisos puede trasladar un directorio anclado fuera de la raíz, alterar mounts o escribir archivos compartidos en ventanas no atómicas de Git. Los checks y flock no son sandbox ni bloqueo universal de escritores. Tampoco hay garantía frente a SIGKILL, crash o pérdida eléctrica.
4. Herramientas y filesystem deben ofrecer las primitivas Linux/GNU indicadas. No se incorporó soporte para sistemas no probados ni un fallback que copie/desenlace silenciosamente entre filesystems.
5. Los límites del parser rechazan entradas excesivas con error completo; no truncan en silencio. La compatibilidad V4Sequence fue verificada con Qt 6.11.2 y el schema de Ambxst 1.2.6. No se promete contener ejecución arbitraria de getters/proxies de código JS hostil.
6. Una instalación hecha desde otra versión de las fuentes no coincide con este proyecto y será rechazada. La migración de la instalación real v0.1.0 queda para un plan de despliegue autorizado, después de revisar este candidato.
7. Los scripts QA históricos completos tienen expectativas de v0.1.0 que ya no describen la política de recuperación. Se preservaron y sus fallos de harness se reportaron; se extrajeron regresiones mantenibles y se repitieron seis ataques originales adaptando únicamente su localización.

Preservación verificada: **22 artefactos históricos** siguen coincidiendo con su manifest, y los **5 archivos de la instalación real más binds.json** mantienen sus hashes previos. [Evidencia](evidence/preservation.json). No se modificaron dotfiles, backups, `.orig`, audio/Bluetooth, Plasma ni Yazi. Sin commit, tag, push, stash, reset o clean.

## G. Diff completo resumido

- `common.sh`: clasificación compartida, rechazo de registro colgante, validación de componentes, directorios anclados, bloqueo cooperante, recuperación duradera y primitivas exactas.
- `install.sh` / `uninstall.sh`: transacciones reutilizan esos helpers; se elimina la purga automática de archivos, se conserva recuperación tras éxito/rollback y se completan los diagnósticos aun cuando una operación de rollback falla.
- `verify.sh`: sintaxis Bash individual, regresiones puras, preferencia/identificación Qt 6 y estado instalado común.
- `ShortcutData.js`: validación y presupuesto de trabajo, normalización segura, maps/consultas propias, hardware por key y etiqueta de conteo. La compacción de familias conserva su algoritmo.
- `ShortcutsOverlay.qml`: catch alrededor de construcción, rótulo de filas y Wrap. Sin cambio de integración, navegación, geometría general, shortcuts o servicios.
- `tests/`: regresiones pequeñas para las clases de defecto, suite normal y ciclo completo opcional. Los fixtures originales reconocen aliases físicos y recuperación nueva.
- README/REQUIREMENTS/AGENTS/CHANGELOG: contrato verificable, footprint/limpieza manual, límites y versión pendiente. QA: diseño, reporte y evidencia nueva separados del historial inmutable.

El diff de archivos seguidos por Git tiene 12 archivos modificados, 644 inserciones y 507 eliminaciones al cerrar la adenda I (los conteos previos de 514 aparecen en las filas históricas de D). Los archivos nuevos enumerados en C no aparecen en `git diff --stat` mientras sigan sin seguimiento; forman parte explícita del candidato revisable.

**Archivos exactos de un despliegue futuro:**

```text
modules/widgets/shortcuts/ShortcutsOverlay.qml
modules/widgets/shortcuts/ShortcutData.js
modules/services/Visibilities.qml
modules/services/GlobalShortcuts.qml
shell.qml
```

Más el footprint de recuperación documentado. `patches/ambxst-integration.patch` permanece byte a byte igual: GlobalShortcuts +1/-0; Visibilities +4/-3; shell +16/-1. Ningún otro archivo compartido forma parte del despliegue.

## H. Estado Git final

Rama `main`; HEAD y único tag en HEAD siguen siendo el baseline indicado. `git diff --check`: exit 0, sin salida. No se hizo commit/tag/push.

```text
 M AGENTS.md
 M CHANGELOG.md
 M README.md
 M REQUIREMENTS.md
 M scripts/common.sh
 M scripts/install.sh
 M scripts/uninstall.sh
 M scripts/verify.sh
 M src/modules/widgets/shortcuts/ShortcutData.js
 M src/modules/widgets/shortcuts/ShortcutsOverlay.qml
 M tests/fixtures/fs-wrapper.sh
 M tests/transactional-scripts.test.sh
?? docs/qa/
?? tests/deployment.test.py
?? tests/fixtures/race-wrapper.py
?? tests/full-tree-cycle.test.py
?? tests/hardening.test.js
?? tests/qml.test.py
?? tests/run.sh
?? tests/verify.test.sh
```

El `?? docs/qa/` agrega el historial preexistente y la carpeta nueva v0.1.1; el inventario C distingue ambos. [Salida de comandos Git](evidence/final-checks.json).

## I. Adenda 2026-09-08 — revisiones CR-001 y CR-002

Segunda ronda de revisión del candidato v0.1.1. Resultado: implementado y verificado en aislamiento, sin commit/tag/push. No se tocó la instalación real (overlay v0.1.0 publicado), los dotfiles, `binds.json`, las recuperaciones ni los cambios preservados de usuario.

### CR-001 — `install` re-abre el candidato y trunca por nombre

**Hallazgo (ronda 1).** `install -m 0644 -- "$source" "$candidate"` abría de nuevo la ruta del `mktemp` para una escritura con truncado (leaf TOCTOU): un symlink colocado ahí se seguía (escritura a través a `outside/VICTIM`), un directorio fallaba sin identificación útil y un archivo regular concurrente podía pisarse. `install -T` no aporta `O_NOFOLLOW` ni conserva identidad; la identidad percibida del staged (el inode del hardlink publicado) era accidental, no impuesta.

**Decisión final (ronda 2, Bash-only; revierte la ronda 1).** `stage_file()` en `common.sh` ya no usa `mktemp` ni reabre por nombre: el nombre se genera **sin crear** (`scripts/gen_candidate`) y la creación es una única apertura atómica `set -o noclobber` + `exec {fd}> "$candidate"` (capa `O_WRONLY|O_CREAT|O_EXCL`, verificada en bash 5.3.15 contra `redir.c`):
1. Exclusividad real por `O_EXCL`: si algo ya ocupa el nombre (regular, symlink, directorio) la apertura falla con `EEXIST` y **se abandona el nombre y se reintenta** (hasta 8 intentos; nunca se borra, trunca ni sigue el nodo que ganó la colisión). Un `-e`/`-L` previo evita abrir un FIFO/device preexistente (que bloquearía), mientras `O_EXCL` sigue cerrando la ventana create→open.
2. Preparación única verificada **solo por el descriptor abierto** (`/proc/<pid>/fd/<fd>`): `cat source >&fd`, `cmp -s`, `chmod 0644`. `umask 077` deja el pre-chmod en 0600. Un fallo cierra el FD y aborta sin publicar staging parcial.
3. `device + inode` se verifican **después** del create como chequeo de identidad extra (el nombre debe seguir resolviendo al objeto abierto); no es el mecanismo de identidad.
4. `set -C` y `umask 077` viven en un subshell de sustitución de comando, por lo que no filtran a `install.sh`. `stat`/`readlink -e` se eliminaron como mecanismo.

Rechazado de la ronda 1: `mktemp` + reapertura por nombre con `stat` como identidad primaria (un inode propio colocado en el nombre recién leído era indistinguible, y `install -T` no es seguro). También se descartó `truncate` (el archivo fresco exclusivo no lo necesita) y helper `mkstemp`+paso de fd a una herramienta externa. Límite de frontera declarado: un actor **same-UID/root** colocando objetos especiales deliberadamente en el directorio privado `0700`, o un montaje o SIGKILL/pérdida de energía, queda fuera del alcance de esta solución; no se añadieron más rondas de hardening.

**Regresiones** (`tests/deployment.test.py`, wrapper `tests/fixtures/race-wrapper.py`): sustitución inmediata del candidato por symlink (a `<outside>/VICTIM` prellenado), directorio, FIFO y socket Unix (sin cuelgue; socket vía `bind()` corto + symlink por el límite de 108 bytes de `AF_UNIX` tras el difícil fd real), device (mknod; skipped si el entorno lo deniega), y **`staging-regular-replacement`**: un inode A ocupa el nombre y un actor lo reemplaza por un inode regular B nuevo — instalación aborta y B queda intacto (regresión por corrección de producto, no debilitada). `staging-prepfail` hace fallar el `chmod` final: aborta sin publicar y conserva el contenido preparado con modo 0600. `staging-identity` verifica `device+inode` publicado == preparado y ≠ inode canónico, modo 0644 y nlink 2. `gen_candidate` (proyecto) y `mktemp` entran en el conjunto real envuelto; el wrapper de inyección se re-ancla de `mktemp` a `gen_candidate`.

### CR-002 — resolver con bytes de control

**Hallazgo.** `resolve_ambxst_target()` no rechazaba LF/CR en argumento, `AMBXST_SOURCE_DIR`, registro `shell_repo` ni fallback; una ruta con `\r`/`\n` llegaba a operaciones de resolución, `cd` y escritura del registro.

**Decisión (refinada por el revisor).** `reject_control_target()` rechaza **solo** LF ("salto de línea") y CR ("retorno de carro") de forma fail-closed, con diagnóstico mediante `printf '%q'` (no puede re-inyectar un byte de control). **Espacios, tabulaciones y UTF-8 siguen siendo válidos.** Se invoca en un único punto de estrangulamiento en `resolve_ambxst_target()`, después de la rama argumento/entorno/registro/fallback y antes del chequeo de ruta absoluta, cubriendo las cuatro fuentes.

**Regresiones** (`tests/transactional-scripts.test.sh`): rechazo de argumento con CR (directorio real existente), argumento con LF, entorno con CR y registro `shell_repo` con línea CRLF real — todos sin modificar el árbol. Aceptación de destinos reales con espacios, tabulaciones y UTF-8.

### Resultados de la adenda

| Comando (raíz del proyecto) | Resultado | Nota |
|---|---|---|
| `bash tests/transactional-scripts.test.sh` | PASS | 32 (eran 25): +7 CR-002 (4 negativos, 3 positivos). |
| `python3 tests/deployment.test.py`  | PASS | 38 (eran 37): +1 `staging-regular-replacement`; staging re-anclado de `mktemp` a `gen_candidate`; wrapper de `gen_candidate` añadido al conjunto real. |
| `bash tests/run.sh`                 | PASS | Suite completa: parser 15, hardening 29, verify 3, transaccionales 32, deployment 38, Qt 9. |
| `bash scripts/verify.sh /home/kuroflynn/.local/src/ambxst` | exit 1 esperado | Solo lectura; sigue reportando «ShortcutsOverlay.qml instalado difiere de la fuente canónica» (v0.1.0 instalado vs. candidato v0.1.1). Hashes de los 5 archivos desplegados y de `binds.json` sin cambios. |
| `git diff --check` | PASS | Sin errores de whitespace. |

Sin commit/tag/push. Faltan en la release real los pasos T018–021 de la sesión y el despliegue autorizado de v0.1.1.

## J. Adenda 2026-09-09 — cierre de release v0.1.1 y validación runtime T018–T021

Migración y despliegue autorizados de v0.1.1 sobre la instalación real (v0.1.0):
backup durable byte-exacto en `.ambxst-shortcuts-recovery/upgrade-v0.1.0-*`, revert
del patch v0.1.0, `scripts/install.sh` v0.1.1 (exit 0), `scripts/verify.sh` (exit 0,
«overlay instalado y coincidente»), y reload de Ambxst (RC 0). La instancia real
quedó en v0.1.1; `binds.json` intacto. Sobre esa instancia se ejecutó la validación
runtime de sesión real:

- **T018 (toggle/Esc): PASS.** `ambxst run shortcuts` y el bind personal `SUPER+/`
  abren/cierran; `Esc` cierra desde cualquier foco; 6/6 comprobaciones con
  confirmación visual en ambas pantallas; 0 CRIT/FATAL/ERROR del shell.
- **T019-A (navegación/scroll/foco/multimonitor): PASS.** Scroll con rueda/trackpad,
  navegación por teclado (↑/↓, AvPág/RePág), cierre con `Esc` o clic exterior,
  panel completo en ambos monitores. El hover no resalta: es diseño (overlay
  informativo sin estado hover).
- **T019-B (escalas distintas): PASS.** eDP-2 1.25 y HDMI-A-1 1.0; sin cambios.
- **T020 (refresco dinámico y bindings condicionados): T020-1 PASS** (cambio de
  etiqueta reflejado en vivo con el overlay abierto), **T020-2 PASS** (cambio con
  el overlay cerrado reflejado al abrir), **T020-3 PASS** (JSON inválido → estado de
  error contenido sin crash ni filas stale; recuperación en vivo al restaurar el
  archivo). **T020-4 BLOCKED / NOT EXECUTED**: no pudo accionarse el selector de
  layout de la barra mientras el overlay permanece abierto (captura foco y sigue al
  puntero), por lo que no hubo cambio de layout ni evento `onCompositorLayoutChanged`
  que evaluar; Hyprland y `states.json` permanecen en `dwindle`. No constituye fallo
  del overlay. La configuración probada no tiene binds con `layouts` no vacíos, así
  que el sub-check de bindings condicionados por layout es vacuo.
- **T021-A (convivencia de overlays): PASS.** Abrir Dashboard (SUPER+D) con
  Shortcuts abierto cierra el overlay (exclusión vía `Visibilities.clearAll`);
  volver a `SUPER+/` reabre Shortcuts y cierra Dashboard; cierre limpio sin foco
  residual ni superficies.
- **T021-B (lock/unlock): PASS.** Lockscreen normal (`WlSessionLock`,
  `ambxst run lockscreen`); el overlay queda detrás del lockscreen, sin verse ni ser
  interactuable; tras desbloquear, Ambxst/Quickshell siguen estables y Shortcuts se
  abre/cierra con normalidad (Esc, SUPER+/, clic exterior); sin superficies
  residuales.
- **T021-C (suspend/wake): PASS.** Suspensión del sistema (overlay cerrado antes del
  sleep), wake + desbloqueo PAM; misma instancia Quickshell/axctl (sin restart);
  wallpapers re-sincronizados (video-sync code 0); Shortcuts y Dashboard abren y
  cierran con normalidad; foco, ambos monitores y superficies intactos;
  0 CRIT/FATAL/ERROR tras el wake.

Curación de evidencia en el commit de release: se versionan los informes REPORT.md
y DESIGN.md, el reproductor `replay-historical.py` y los resultados JSON
(`final-checks.json`, `preservation.json`, `full-tree-cycle.json`,
`historical-replay.json`, `parser-historical.json`). Los dumps de consola (*.log)
de la validación aislada quedan fuera del commit por política de evidencia y son
reproducibles con los tests permanentes de `tests/`; `docs/qa/v0.1.0/` permanece sin
seguimiento como historial inalterado.

Release v0.1.1 cerrada: commit `release: prepare v0.1.1`, tag anotado `v0.1.1` y push
de `main` y del tag a origin.
