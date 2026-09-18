.pragma library

var SECTION_DEFINITIONS = [
    { id: "ambxst", title: "Ambxst y aplicaciones" },
    { id: "windows", title: "Ventanas y foco" },
    { id: "workspaces", title: "Espacios de trabajo" },
    { id: "layout", title: "Distribución y columnas" },
    { id: "system", title: "Sistema y sesión" },
    { id: "media", title: "Multimedia y brillo" }
];

var ACTION_LABELS = {
    "ambxst.launcher": { label: "Abrir el lanzador", group: "ambxst" },
    "ambxst.dashboard": { label: "Abrir el panel", group: "ambxst" },
    "ambxst.assistant": { label: "Abrir el asistente", group: "ambxst" },
    "ambxst.clipboard": { label: "Abrir el portapapeles", group: "ambxst" },
    "ambxst.emoji": { label: "Abrir selector de emojis", group: "ambxst" },
    "ambxst.notes": { label: "Abrir notas", group: "ambxst" },
    "ambxst.tmux": { label: "Abrir Tmux", group: "ambxst" },
    "ambxst.wallpapers": { label: "Cambiar fondo de pantalla", group: "ambxst" },
    "ambxst.shortcuts": { label: "Mostrar atajos de teclado", group: "ambxst" },
    "ambxst.config": { label: "Abrir configuración", group: "system" },
    "ambxst.overview": { label: "Vista general de ventanas", group: "windows" },
    "ambxst.powermenu": { label: "Abrir menú de energía", group: "system" },
    "ambxst.tools": { label: "Abrir herramientas", group: "ambxst" },
    "ambxst.screenshot": { label: "Capturar pantalla", group: "system" },
    "ambxst.screenrecord": { label: "Grabar pantalla", group: "system" },
    "ambxst.lens": { label: "Abrir lupa", group: "system" },
    "ambxst.reload": { label: "Recargar Ambxst", group: "system" },
    "ambxst.quit": { label: "Cerrar Ambxst", group: "system" },
    "window.close": { label: "Cerrar ventana", group: "windows" },
    "window.drag": { label: "Arrastrar ventana", group: "windows" },
    "window.resize-drag": { label: "Redimensionar con el ratón", group: "windows" },
    "window.fullscreen": { label: "Alternar pantalla completa", group: "windows" },
    "window.toggle-floating": { label: "Alternar ventana flotante", group: "windows" },
    "workspace.toggle-special": { label: "Alternar espacio especial", group: "workspaces" },
    "workspace.move-window-special": { label: "Mover ventana al espacio especial", group: "workspaces" },
    "scrolling.promote": { label: "Separar ventana en nueva columna", group: "layout" },
    "scrolling.toggle-fit": { label: "Ajustar columnas al espacio", group: "layout" },
    "scrolling.toggle-full-column": { label: "Cambiar ancho de columna predefinido", group: "layout" },
    "system.lock": { label: "Bloquear sesión", group: "system" },
    "system.lock-locked": { label: "Bloquear sesión", group: "system" },
    "system.calculator": { label: "Abrir calculadora", group: "ambxst" },
    "media.play-pause": { label: "Reproducir o pausar", group: "media" },
    "media.play-pause-locked": { label: "Reproducir o pausar", group: "media" },
    "media.prev": { label: "Pista anterior", group: "media" },
    "media.previous": { label: "Pista anterior", group: "media" },
    "media.next": { label: "Pista siguiente", group: "media" },
    "media.stop": { label: "Detener reproducción", group: "media" },
    "media.stop-locked": { label: "Detener reproducción", group: "media" },
    "audio.volume-up": { label: "Subir volumen", group: "media" },
    "audio.volume-down": { label: "Bajar volumen", group: "media" },
    "audio.mute-toggle": { label: "Silenciar o activar audio", group: "media" },
    "brightness.up": { label: "Subir brillo", group: "media" },
    "brightness.down": { label: "Bajar brillo", group: "media" }
};

var FAMILY_DEFINITIONS = [
    { actionId: "workspace.switch", label: "Cambiar de espacio de trabajo", group: "workspaces", order: 0 },
    { actionId: "workspace.move-window", label: "Mover ventana y cambiar al espacio", group: "workspaces", order: 1 },
    { actionId: "workspace.move-window-silent", label: "Mover ventana sin cambiar de espacio", group: "workspaces", order: 2 },
    { actionId: "scrolling.move-column-workspace", label: "Mover columna a espacio de trabajo", group: "layout", order: 0 }
];

var MODIFIER_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"];

// Bounds apply to consumed shortcut data, not QObject introspection. Qt 6
// list<string>/list<var> are V4Sequence objects, not JavaScript Arrays.
function checkedList(value, maximum) {
    if (value === undefined || value === null)
        return [];
    if (!Array.isArray(value) && Object.prototype.toString.call(value) !== "[object V4Sequence]")
        throw new Error("Invalid shortcut list");
    if (!Number.isInteger(value.length) || value.length < 0 || value.length > maximum)
        throw new Error("Shortcut list limit");
    return value;
}

function spend(budget, amount) {
    budget.remaining -= amount;
    if (budget.remaining < 0)
        throw new Error("Shortcut work limit");
}

function displayString(value) {
    if (value === undefined || value === null)
        return "";
    if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean")
        throw new Error("Invalid shortcut text");
    var text = String(value);
    if (text.length > 32768)
        throw new Error("Shortcut text limit");
    return text;
}

function ownValue(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key) ? object[key] : undefined;
}

function rowCountLabel(count) {
    return count === 1 ? "1 fila de atajos" : String(count) + " filas de atajos";
}

function parseJson(text) {
    if (typeof text === "string" && text.length > 2097152)
        return { ok: false, data: null, error: "La configuración de atajos es demasiado grande." };
    if (typeof text !== "string" || text.trim().length === 0) {
        return { ok: false, data: null, error: "El archivo de atajos está vacío." };
    }

    try {
        var data = JSON.parse(text);
        if (!data || typeof data !== "object" || Array.isArray(data)) {
            return { ok: false, data: null, error: "El archivo de atajos no contiene un objeto válido." };
        }
        return { ok: true, data: data, error: "" };
    } catch (error) {
        return { ok: false, data: null, error: "No se pudo leer la configuración de atajos." };
    }
}

function build(source, currentLayout) {
    try {
        return buildModel(source, currentLayout);
    } catch (error) {
        return { sections: [], total: 0, error: "La configuración de atajos no es válida o excede los límites de lectura." };
    }
}

function buildModel(source, currentLayout) {
    var model = source;
    if (typeof source === "string") {
        var parsed = parseJson(source);
        if (!parsed.ok)
            return { sections: [], total: 0, error: parsed.error };
        model = parsed.data;
    }

    if (!model || typeof model !== "object" || Array.isArray(model))
        return { sections: [], total: 0, error: "La configuración de atajos no está disponible." };

    var rowsByIdentity = Object.create(null);
    var budget = { remaining: 100000 };
    collectCoreBindings(model.ambxst, rowsByIdentity, currentLayout, budget);
    collectCustomBindings(model.custom, rowsByIdentity, currentLayout, budget);

    var rows = [];
    var identities = Object.keys(rowsByIdentity);
    for (var i = 0; i < identities.length; i++) {
        var row = rowsByIdentity[identities[i]];
        row.combos.sort(compareCombos);
        rows.push(row);
    }

    for (var familyIndex = 0; familyIndex < FAMILY_DEFINITIONS.length; familyIndex++)
        rows = compactFamily(rows, FAMILY_DEFINITIONS[familyIndex]);

    var sections = [];
    var total = 0;
    for (var sectionIndex = 0; sectionIndex < SECTION_DEFINITIONS.length; sectionIndex++) {
        var sectionDefinition = SECTION_DEFINITIONS[sectionIndex];
        var sectionRows = rows.filter(function(candidate) {
            return candidate.group === sectionDefinition.id && candidate.combos.length > 0;
        });
        sectionRows.sort(compareRows);
        if (sectionRows.length > 0) {
            sections.push({
                id: sectionDefinition.id,
                title: sectionDefinition.title,
                rows: sectionRows
            });
            total += sectionRows.length;
        }
    }

    return { sections: sections, total: total, error: "" };
}

function collectCoreBindings(ambxst, rowsByIdentity, currentLayout, budget) {
    if (!ambxst || typeof ambxst !== "object")
        return;

    var knownCoreKeys = ["launcher", "dashboard", "assistant", "clipboard", "emoji", "notes", "tmux", "wallpapers"];
    var seen = Object.create(null);
    for (var i = 0; i < knownCoreKeys.length; i++) {
        var coreKey = knownCoreKeys[i];
        seen[coreKey] = true;
        addBinding(ambxst[coreKey], coreKey, "ambxst", rowsByIdentity, currentLayout, budget);
    }

    var extraKeys = safeObjectKeys(ambxst);
    for (var extraIndex = 0; extraIndex < extraKeys.length; extraIndex++) {
        var extraKey = extraKeys[extraIndex];
        if (extraKey !== "system" && !seen[extraKey])
            addBinding(ambxst[extraKey], extraKey, "ambxst", rowsByIdentity, currentLayout, budget);
    }

    var system = ambxst.system;
    if (!system || typeof system !== "object")
        return;

    var knownSystemKeys = ["overview", "powermenu", "config", "lockscreen", "tools", "screenshot", "screenrecord", "lens", "reload", "quit"];
    seen = Object.create(null);
    for (var systemIndex = 0; systemIndex < knownSystemKeys.length; systemIndex++) {
        var systemKey = knownSystemKeys[systemIndex];
        seen[systemKey] = true;
        addBinding(system[systemKey], systemKey, "system", rowsByIdentity, currentLayout, budget);
    }

    extraKeys = safeObjectKeys(system);
    for (var futureIndex = 0; futureIndex < extraKeys.length; futureIndex++) {
        var futureKey = extraKeys[futureIndex];
        if (!seen[futureKey])
            addBinding(system[futureKey], futureKey, "system", rowsByIdentity, currentLayout, budget);
    }
}

function collectCustomBindings(custom, rowsByIdentity, currentLayout, budget) {
    custom = checkedList(custom, 4096);
    for (var i = 0; i < custom.length; i++) {
        var bind = custom[i];
        if (!bind || bind.enabled === false)
            continue;
        addBinding(bind, bind.name, "", rowsByIdentity, currentLayout, budget);
    }
}

function addBinding(bind, fallbackName, groupHint, rowsByIdentity, currentLayout, budget) {
    if (!bind || typeof bind !== "object" || bind.enabled === false)
        return;
    spend(budget, 1);
    fallbackName = displayString(fallbackName);
    spend(budget, fallbackName.length);

    var keys = bindingKeys(bind);
    var combos = [];
    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
        if (isHardwareEvent(keys[keyIndex]))
            continue;
        var combo = normalizeCombo(keys[keyIndex]);
        if (combo)
            spend(budget, combo.text.length);
        if (combo && !comboExists(combos, combo.text))
            combos.push(combo);
    }
    if (combos.length === 0)
        return;

    var actions = bindingActions(bind);
    for (var actionIndex = 0; actionIndex < actions.length; actionIndex++) {
        var action = actions[actionIndex];
        if (!isActionActive(action, currentLayout))
            continue;

        var rawActionId = actionIdentifier(action);
        var actionId = canonicalActionId(rawActionId);
        var args = actionArguments(action);
        var description = describeAction(rawActionId, args, fallbackName, groupHint);
        var identity = actionId + "|" + stableStringify(args, budget);
        spend(budget, identity.length);

        if (!rowsByIdentity[identity]) {
            rowsByIdentity[identity] = {
                identity: identity,
                actionId: actionId,
                args: args,
                label: description.label,
                group: description.group,
                combos: [],
                compactOrder: 100
            };
        }

        var row = rowsByIdentity[identity];
        for (var comboIndex = 0; comboIndex < combos.length; comboIndex++) {
            spend(budget, row.combos.length + combos[comboIndex].text.length + 1);
            if (!comboExists(row.combos, combos[comboIndex].text))
                row.combos.push(combos[comboIndex]);
        }
    }
}

function bindingKeys(bind) {
    if (bind.keys !== undefined && bind.keys !== null)
        return copyList(checkedList(bind.keys, 64));
    if (bind.key !== undefined)
        return [bind];
    return [];
}

function bindingActions(bind) {
    var actions = checkedList(bind.actions, 64);
    if (actions.length > 0)
        return copyList(actions);
    if (bind.action)
        return [bind.action];
    if (bind.id || bind.dispatcher)
        return [bind];
    return [];
}

function isActionActive(action, currentLayout) {
    if (!action || action.enabled === false)
        return false;

    var layouts = checkedList(action.layouts, 64);
    if (layouts.length === 0 || !currentLayout)
        return true;

    for (var i = 0; i < layouts.length; i++) {
        if (String(layouts[i]) === String(currentLayout))
            return true;
    }
    return false;
}

function actionIdentifier(action) {
    if (!action)
        return "unknown";
    return displayString(action.id || action.dispatcher || action.command || "unknown");
}

function canonicalActionId(actionId) {
    var aliases = {
        "media.play-pause-locked": "media.play-pause",
        "media.stop-locked": "media.stop",
        "media.previous": "media.prev"
    };
    return ownValue(aliases, actionId) || actionId;
}

function actionArguments(action) {
    if (!action)
        return {};
    if (action.args && typeof action.args === "object")
        return action.args;
    if (action.argument !== undefined && action.argument !== "")
        return { argument: action.argument };
    return {};
}

function describeAction(actionId, args, fallbackName, groupHint) {
    var known = ownValue(ACTION_LABELS, actionId);
    if (known)
        return known;

    var directionLabels = { u: "arriba", d: "abajo", l: "a la izquierda", r: "a la derecha" };
    var direction = ownValue(directionLabels, String(args.direction || "").toLowerCase()) || "";
    if (actionId === "window.focus")
        return { label: direction ? "Enfocar " + direction : "Cambiar foco", group: "windows" };
    if (actionId === "window.move")
        return { label: direction ? "Mover ventana " + direction : "Mover ventana", group: "windows" };
    if (actionId === "window.resize")
        return { label: resizeLabel(args.delta), group: "windows" };
    if (actionId === "workspace.switch")
        return { label: "Espacio de trabajo " + String(args.index || ""), group: "workspaces" };
    if (actionId === "workspace.move-window")
        return { label: "Mover ventana al espacio " + String(args.index || "") + " y cambiar a él", group: "workspaces" };
    if (actionId === "workspace.move-window-silent")
        return { label: "Mover ventana al espacio " + String(args.index || "") + " sin cambiar de espacio", group: "workspaces" };
    if (actionId === "workspace.switch-relative")
        return { label: signedDirection(args.offset, "Espacio anterior", "Espacio siguiente", "Cambiar espacio"), group: "workspaces" };
    if (actionId === "workspace.switch-occupied")
        return { label: signedDirection(args.offset, "Espacio ocupado anterior", "Espacio ocupado siguiente", "Cambiar entre espacios ocupados"), group: "workspaces" };
    if (actionId === "scrolling.move-column-workspace")
        return { label: "Mover columna al espacio " + String(args.index || ""), group: "layout" };
    if (actionId === "scrolling.resize-column")
        return { label: String(args.delta || "").charAt(0) === "-" ? "Reducir ancho de columna" : "Aumentar ancho de columna", group: "layout" };
    if (actionId === "scrolling.swap-column")
        return { label: direction ? "Intercambiar columna " + direction : "Intercambiar columna", group: "layout" };

    return {
        label: fallbackName || readableIdentifier(actionId),
        group: groupHint || groupForAction(actionId)
    };
}

function resizeLabel(delta) {
    var value = String(delta || "").trim();
    if (value === "0 50")
        return "Aumentar alto de ventana";
    if (value === "0 -50")
        return "Reducir alto de ventana";
    if (value === "50 0")
        return "Aumentar ancho de ventana";
    if (value === "-50 0")
        return "Reducir ancho de ventana";
    return "Redimensionar ventana";
}

function signedDirection(value, negativeLabel, positiveLabel, fallbackLabel) {
    var text = String(value || "");
    if (text.charAt(0) === "-")
        return negativeLabel;
    if (text.charAt(0) === "+" || Number(text) > 0)
        return positiveLabel;
    return fallbackLabel;
}

function groupForAction(actionId) {
    if (actionId.indexOf("window.") === 0)
        return "windows";
    if (actionId.indexOf("workspace.") === 0)
        return "workspaces";
    if (actionId.indexOf("scrolling.") === 0 || actionId.indexOf("layout.") === 0)
        return "layout";
    if (actionId.indexOf("media.") === 0 || actionId.indexOf("audio.") === 0 || actionId.indexOf("brightness.") === 0)
        return "media";
    if (actionId.indexOf("system.") === 0)
        return "system";
    return "ambxst";
}

function readableIdentifier(identifier) {
    var text = String(identifier || "Atajo").replace(/[._-]+/g, " ").trim();
    return text.length > 0 ? text.charAt(0).toUpperCase() + text.slice(1) : "Atajo";
}

function isHardwareEvent(keyObject) {
    var rawKey = displayString((keyObject && keyObject.key) || "").trim().toLowerCase();
    return rawKey.indexOf("switch:") === 0
        || rawKey.indexOf("event:") === 0
        || rawKey === "lid switch";
}

function normalizeCombo(keyObject) {
    if (!keyObject)
        return null;

    var rawKey = displayString(keyObject.key || "");
    if (rawKey.length === 0)
        return null;

    var modifiers = normalizeModifiers(keyObject.modifiers);
    var key = normalizeKey(rawKey);
    if (key === "SUPER" && modifiers.indexOf("SUPER") !== -1)
        key = "";

    var parts = modifiers.slice();
    if (key.length > 0)
        parts.push(key);
    if (parts.length === 0)
        return null;

    return {
        modifiers: modifiers,
        key: key,
        rawKey: rawKey,
        text: parts.join(" + ")
    };
}

function normalizeModifiers(modifiers) {
    var normalized = [];
    modifiers = checkedList(modifiers, 32);
    if (modifiers.length > 0) {
        for (var i = 0; i < modifiers.length; i++) {
            var modifier = displayString(modifiers[i]).toUpperCase();
            if (modifier === "MOD4" || modifier === "META")
                modifier = "SUPER";
            if (modifier === "CONTROL")
                modifier = "CTRL";
            if (normalized.indexOf(modifier) === -1)
                normalized.push(modifier);
        }
    }

    normalized.sort(function(left, right) {
        var leftIndex = MODIFIER_ORDER.indexOf(left);
        var rightIndex = MODIFIER_ORDER.indexOf(right);
        if (leftIndex === -1)
            leftIndex = MODIFIER_ORDER.length;
        if (rightIndex === -1)
            rightIndex = MODIFIER_ORDER.length;
        return leftIndex === rightIndex ? left.localeCompare(right) : leftIndex - rightIndex;
    });
    return normalized;
}

function normalizeKey(key) {
    var raw = String(key);
    var upper = raw.toUpperCase();
    var aliases = {
        "SUPER_L": "SUPER",
        "SUPER_R": "SUPER",
        "ESCAPE": "Esc",
        "PERIOD": ".",
        "COMMA": ",",
        "SPACE": "Espacio",
        "TAB": "Tab",
        "RETURN": "Enter",
        "ENTER": "Enter",
        "BACKSPACE": "Retroceso",
        "UP": "↑",
        "DOWN": "↓",
        "LEFT": "←",
        "RIGHT": "→",
        "MOUSE_UP": "Rueda ↑",
        "MOUSE_DOWN": "Rueda ↓",
        "XF86AUDIOPLAY": "Reproducir",
        "XF86AUDIOMEDIA": "Multimedia",
        "XF86AUDIOPREV": "Anterior",
        "XF86AUDIONEXT": "Siguiente",
        "XF86AUDIOSTOP": "Detener",
        "XF86AUDIORAISEVOLUME": "Vol +",
        "XF86AUDIOLOWERVOLUME": "Vol −",
        "XF86AUDIOMUTE": "Silencio",
        "XF86MONBRIGHTNESSUP": "Brillo +",
        "XF86MONBRIGHTNESSDOWN": "Brillo −",
        "XF86CALCULATOR": "Calculadora"
    };
    if (ownValue(aliases, upper) !== undefined)
        return aliases[upper];
    if (upper.indexOf("MOUSE:") === 0) {
        var button = upper.substring(6);
        if (button === "272")
            return "Ratón 1";
        if (button === "273")
            return "Ratón 2";
        return "Ratón " + button;
    }
    if (raw.length === 1)
        return upper;
    return raw;
}

function compactFamily(rows, definition) {
    var candidates = [];
    var indexMap = Object.create(null);
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (row.actionId !== definition.actionId)
            continue;
        var index = Number(row.args && row.args.index);
        if (!isFinite(index) || index < 1 || index > 10 || Math.floor(index) !== index || indexMap[index])
            return rows;
        candidates.push(row);
        indexMap[index] = row;
    }

    if (candidates.length < 2)
        return rows;
    for (var expected = 1; expected <= candidates.length; expected++) {
        if (!indexMap[expected])
            return rows;
    }

    var commonSignatures = [];
    var firstRow = indexMap[1];
    for (var firstComboIndex = 0; firstComboIndex < firstRow.combos.length; firstComboIndex++) {
        var firstCombo = firstRow.combos[firstComboIndex];
        if (firstCombo.key !== "1")
            continue;
        var signature = firstCombo.modifiers.join("+");
        var complete = true;
        for (var familyIndex = 2; familyIndex <= candidates.length && complete; familyIndex++) {
            complete = hasFamilyCombo(indexMap[familyIndex].combos, signature, familyIndex);
        }
        if (complete && commonSignatures.indexOf(signature) === -1)
            commonSignatures.push(signature);
    }

    if (commonSignatures.length === 0)
        return rows;

    var compactCombos = [];
    var rangeKey = candidates.length === 10 ? "1…0" : "1…" + String(candidates.length);
    for (var signatureIndex = 0; signatureIndex < commonSignatures.length; signatureIndex++) {
        var signatureText = commonSignatures[signatureIndex];
        var modifiers = signatureText.length > 0 ? signatureText.split("+") : [];
        compactCombos.push({
            modifiers: modifiers,
            key: rangeKey,
            rawKey: rangeKey,
            text: modifiers.concat([rangeKey]).join(" + ")
        });
    }

    var compactedRows = [];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        var current = rows[rowIndex];
        if (current.actionId !== definition.actionId) {
            compactedRows.push(current);
            continue;
        }

        var currentIndex = Number(current.args && current.args.index);
        current.combos = current.combos.filter(function(combo) {
            var signature = combo.modifiers.join("+");
            return commonSignatures.indexOf(signature) === -1 || combo.key !== familyKey(currentIndex);
        });
        if (current.combos.length > 0)
            compactedRows.push(current);
    }

    compactedRows.push({
        identity: definition.actionId + "|family",
        actionId: definition.actionId,
        args: { first: 1, last: candidates.length },
        label: definition.label,
        group: definition.group,
        combos: compactCombos,
        compactOrder: definition.order
    });
    return compactedRows;
}

function hasFamilyCombo(combos, modifierSignature, index) {
    for (var i = 0; i < combos.length; i++) {
        if (combos[i].modifiers.join("+") === modifierSignature && combos[i].key === familyKey(index))
            return true;
    }
    return false;
}

function familyKey(index) {
    return Number(index) === 10 ? "0" : String(index);
}

function comboExists(combos, text) {
    for (var i = 0; i < combos.length; i++) {
        if (combos[i].text === text)
            return true;
    }
    return false;
}

function compareCombos(left, right) {
    if (left.modifiers.length !== right.modifiers.length)
        return left.modifiers.length - right.modifiers.length;
    return left.text.localeCompare(right.text);
}

function compareRows(left, right) {
    if (left.compactOrder !== right.compactOrder)
        return left.compactOrder - right.compactOrder;
    return left.label.localeCompare(right.label);
}

function copyList(list) {
    list = checkedList(list, 4096);
    var result = [];
    for (var i = 0; i < list.length; i++)
        result.push(list[i]);
    return result;
}

function safeObjectKeys(object) {
    var keys = Object.keys(object || {});
    if (keys.length > 4096)
        throw new Error("Shortcut object limit");
    return keys;
}

function stableStringify(value, budget, depth) {
    budget = budget || { remaining: 100000 };
    depth = depth || 0;
    spend(budget, 1);
    if (depth > 24)
        throw new Error("Shortcut nesting limit");
    if (value === null || value === undefined)
        return "null";
    if (typeof value !== "object") {
        var scalar = JSON.stringify(displayString(value));
        // Preserve the original scalar type for action identity.
        spend(budget, scalar.length);
        return JSON.stringify(value);
    }
    if (Array.isArray(value)) {
        checkedList(value, 4096);
        var items = [];
        for (var arrayIndex = 0; arrayIndex < value.length; arrayIndex++)
            items.push(stableStringify(value[arrayIndex], budget, depth + 1));
        return "[" + items.join(",") + "]";
    }
    var keys = safeObjectKeys(value).sort();
    var properties = [];
    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
        var key = keys[keyIndex];
        spend(budget, key.length);
        properties.push(JSON.stringify(key) + ":" + stableStringify(value[key], budget, depth + 1));
    }
    return "{" + properties.join(",") + "}";
}
