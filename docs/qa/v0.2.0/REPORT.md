# QA smoke runtime — v0.2.0 (mod nativo `kuroflynn.shortcuts-overlay`)

Fecha: 2026-09-16. Sesión: Hyprland 0.56.2 (config provider lua), Ambxst 1.3.3 base `af9f8ad4f42d`, Quickshell (`qs -p <generación>/shell.qml`), 2 monitores (eDP-2 1.25, HDMI-A-1 1.0). Mod activado por el gestor `ambxst mods`: generación activa `20260916T182432Z-6e56891e`.

**Resultado: criterios de release satisfechos → veredicto v0.2.0: LISTO.** BUG-001 analizado y cerrado como **falso positivo** (QA contaminado por input manual concurrente del usuario). T018–T021 de la línea v0.1.x quedan **DEPRECADOS** y sustituidos por esta ronda.

## 1. Resumen por punto

| Punto | Resultado | Detalle |
|---|---|---|
| 1. Activación/desactivación vía gestor de mods | **PASS** | `ambxst mods disable/enable` + `ambxst reload`: al desactivar, `ambxst run shortcuts` no crea superficie; al activar, abre. Generaciones nuevas reconstruidas en `~/.local/share/ambxst/mods/generations/`. |
| 2. Ambxst sigue funcionando tras la activación | **PASS** | Capas `ambxst`, `ambxst:wallpaper`, `ambxst:screenCorners` y `ambxst:reservation:*` presentes en ambos monitores tras cada reload. |
| 3. Apertura/cierre múltiple (toggle) | **PASS** | `ambxst run shortcuts` hace toggle (`toggleSimpleModule`); ciclos repetidos abren/cierran de forma fiable. Durante la sesión se registraron cierres adicionales correspondientes a la interacción manual del usuario (ver BUG-001). |
| 4. Cierre con `Esc` y click exterior | **PASS** (`Esc`) / **parcial** (click) | `wtype -k Escape` cierra de forma fiable con el overlay enfocado. Click exterior: no inyectable headless (sin `ydotool`; Hyprland `fakeinput` no disponible; dispatcher CLI roto en proveedor lua); ruta `FocusGrab.onCleared`/scrim existe y es la misma de v0.1.x (validación manual recomendada). |
| 5. Navegación teclado y scroll | **PASS** (`Esc`/flechas/PgUp/PgDn/Home/End ya gestionados) | Con `wtype`: `End`→abajo, `Home`→arriba, `Page_Down`→desplaza; diffs de pantalla y OCR (top=«Aplicaciones/Ventanas», bottom=«Distribución/Sistema/Multimedia») confirman el scroll real. Rueda de ratón: no inyectable headless (Flickable `interactive:true`); misma ruta Qt que v0.1.x. |
| 6. Posición en monitor enfocado | **PASS (parcial, HDMI)** | `hyprctl layers` muestra `ambxst:shortcuts` en el monitor enfocado (HDMI-A-1, nivel 3 Overlay). Pie eDP-2 no verificable headless (no se pudo cambiar monitor enfocado; dispatcher CLI roto + sin click); flujo `moveActiveModuleToFocusedScreen` presente. Validación manual en eDP-2 recomendada. |
| 7. Sin superficies residuales | **PASS** | Tras cierre deliberado, `hyprctl layers` no muestra `ambxst:shortcuts` (comprobado por JSON en ambos monitores). |
| 8. Cambio de bind reflejado | **PASS** | Insert en `binds.json` con key (`SUPER+F9`) + nombre: al abrir, el overlay muestra el nuevo bind y pasa de «59 filas» a «60 filas» (OCR). Restaurado byte-exacto (`61175392d33b7ea2004071d8bd26fa8d043ac1086ca9f2b0f791bbc1603517f6`) y el overlay vuelve a 59; **nota:** el gestor normaliza y puede re-escribir el archivo desde su modelo (auto-save); la restauración requiere iterar hasta converger. |
| 9. Ciclo suspend/wake | **PASS** | `qs ipc --pid <pid> call suspend prepare` → la carga del overlay desaparece (`wakeReady=false`); `suspend wake` → sigue oculto en ~0,4 s y reaparece a los ~4 s (timer `wakeReady` de 3 s). |
| 10. `tests/run.sh` y `scripts/verify.sh` | **PASS** | `tests/run.sh` exit 0 (15 ShortcutData + 29 hardening + 125 manifiesto + 69 composición + 18 verify + 9 QML). `verify.sh --package-only` y `verify.sh /home/kuroflynn/.local/src/ambxst` exit 0; parche literal sobre base `af9f8ad4`; composición solo en `/tmp`; el destino no se modificó (drift-guard de `manifest.schema.json` OK). |

## 2. Incidentes de QA analizados

### BUG-001 — Cierres del overlay atribuidos a input espurio: **FALSE POSITIVE, CERRADO**

- Síntoma registrado: cierres del overlay y pulsaciones `Escape` en la instrumentación sin inyección del proyecto.
- Resolución: **QA contaminado por input manual concurrente del usuario**, que cerró el overlay con `Escape` al verlo aparecer durante la ejecución. Confirmado por el usuario.
- Los cierres observados corresponden a su interacción; no hay defecto de input en el overlay.
- No se aplicó corrección de código; las propuestas de debounce/cambios a `Escape` e investigación de Hyprland/wlroots quedan **descartadas**.
- Detalle completo en `docs/qa/v0.2.0/BUG-001.md`.

No quedan bugs abiertos para v0.2.0.

## 3. Confirmación de deprecación T018–T021

T018–T021 (línea v0.1.x, Ambxst 1.2.6) quedan marcados como **DEPRECATED** en:

- `AGENTS.md` (baseline v0.1.1).
- `REQUIREMENTS.md` §9 (criterios v0.1.0/v0.1.1).
- `CHANGELOG.md` (entrada v0.1.1).
- `README.md` (sección referencia).
- `docs/qa/v0.1.1/REPORT.md` (cabecera).

No se vuelven a ejecutar; el criterio runtime actual es el de este reporte.

## 4. Limitaciones del harness de QA (solo notas informativas, no fallos del proyecto)

- Sin inyección de click/rueda (no `ydotool`; `hyprctl dispatch fakeinput` no existe; dispatcher CLI de Hyprland lua falla al parsear argumentos con `:`/`-`).
- Sin cambio de monitor enfocado headless → pie eDP-2 de P6 y click exterior de P4 requieren validación manual; coordinar con el usuario (puede interferir en las observaciones, ver BUG-001).
- Logs de `qs` van a `/dev/null` (no hay `console.log` disponible en runtime).
- El gestor Ambxst re-escribe/ordena `binds.json` (auto-save/repair): ediciones externas se convergen tras iterar; se finalizó con `binds.json` byte-exacto al original.
- Durante esta ronda el usuario estaba usando el equipo en paralelo; los inputs manuales concurrentes deben tenerse en cuenta en futuras rondas.

## 5. Veredicto

**LISTO para v0.2.0.** Los 10 puntos de la ronda (1–10) pasan dentro de las limitaciones del harness, la integración se verifica íntegra (tests + `verify.sh` con destino real), y BUG-001 quedó cerrado como falso positivo sin corrección de código. Los ítems pendientes de validación manual (click exterior, pie eDP-2, rueda de ratón) no bloquean el release y quedan como notas informativas.

## 6. Estado del repositorio y configuración al cierre

- `binds.json`: restaurado byte-exacto (sha `61175392d33b7ea2004071d8bd26fa8d043ac1086ca9f2b0f791bbc1603517f6`).
- `mods.json`: mod `kuroflynn.shortcuts-overlay 0.2.0` habilitado (como al inicio); generación activa sin instrumentación (prístinos restaurados y verificados).
- Sin `__pycache__` (`PYTHONDONTWRITEBYTECODE=1`); sin residuos de `verify.sh`; sin escrituras en `$HOME/.local/src/ambxst`.
- Cambios de documentación: marcado DEPRECATED T018–T021, este reporte y `BUG-001.md` (cerrado como falso positivo). Sin commit; pendiente revisión del usuario y autorización de release.