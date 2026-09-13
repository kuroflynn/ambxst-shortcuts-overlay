#!/usr/bin/env node

"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sourcePath = path.resolve(__dirname, "../payload/modules/widgets/shortcuts/ShortcutData.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const api = {};
vm.createContext(api);
vm.runInContext(source, api, { filename: sourcePath });

let assertions = 0;
function assert(condition, message) {
    assertions++;
    if (!condition)
        throw new Error(message);
}

function action(id, args = {}, layouts = []) {
    return { id, args, layouts };
}

function custom(name, modifiers, key, actionValue, enabled = true) {
    return {
        name,
        keys: [{ modifiers, key }],
        actions: [actionValue],
        enabled
    };
}

function build(customBinds, ambxst = {}) {
    return api.build({ ambxst, custom: customBinds }, "scrolling");
}

function rows(result) {
    return result.sections.flatMap(section => section.rows);
}

function rowFor(result, actionId) {
    return rows(result).find(row => row.actionId === actionId);
}

assert(!api.parseJson("").ok, "un archivo vacío debe producir error");
assert(!api.parseJson("{").ok, "JSON inválido debe producir error");
assert(!api.parseJson("[]").ok, "la raíz JSON debe ser un objeto");

const active = build([
    custom("Cerrar", ["SUPER"], "C", action("window.close")),
    custom("Deshabilitado", ["SUPER"], "Q", action("window.fullscreen"), false),
    custom("Tapa", [], "switch:Lid Switch", action("system.lock-locked")),
    custom("Foco arriba", ["SUPER"], "Up", action("window.focus", { direction: "u" })),
    custom("Foco arriba alternativo", ["SUPER", "CTRL"], "K", action("window.focus", { direction: "u" })),
    custom("Otra distribución", ["SUPER"], "M", action("window.toggle-floating", {}, ["master"])),
    custom("Combinación larga", ["SHIFT", "ALT", "CTRL", "SUPER"], "TeclaExtremadamenteLarga", action("ambxst.tools"))
], {
    launcher: {
        modifiers: ["SUPER"],
        key: "Super_L",
        action: action("ambxst.launcher")
    }
});

assert(active.error === "", "el modelo activo válido no debe producir error");
assert(rowFor(active, "window.close"), "debe incluir binds activos");
assert(!rowFor(active, "window.fullscreen"), "debe excluir binds deshabilitados");
assert(!rowFor(active, "system.lock-locked"), "debe excluir eventos de hardware");
assert(!rowFor(active, "window.toggle-floating"), "debe excluir acciones de otra distribución");
assert(rowFor(active, "window.focus").combos.length === 2, "debe combinar alternativas equivalentes");
assert(rowFor(active, "ambxst.launcher").combos[0].text === "SUPER", "debe normalizar la tecla Super");
assert(
    rowFor(active, "ambxst.tools").combos[0].text === "SUPER + CTRL + ALT + SHIFT + TeclaExtremadamenteLarga",
    "debe conservar completa y ordenar una combinación larga"
);

const family = [];
for (let index = 1; index <= 6; index++) {
    family.push(custom(
        `Workspace ${index}`,
        ["SUPER"],
        String(index),
        action("workspace.switch", { index: String(index) })
    ));
}
const compacted = build(family);
const compactedRow = rowFor(compacted, "workspace.switch");
assert(compactedRow.identity === "workspace.switch|family", "debe compactar una familia contigua incompleta");
assert(compactedRow.combos[0].text === "SUPER + 1…6", "debe mostrar el rango incompleto correcto");

const gapped = build([
    custom("Workspace 1", ["SUPER"], "1", action("workspace.switch", { index: "1" })),
    custom("Workspace 3", ["SUPER"], "3", action("workspace.switch", { index: "3" }))
]);
assert(rows(gapped).filter(row => row.actionId === "workspace.switch").length === 2, "no debe compactar una familia con huecos");

const defaultsOnly = api.build({
    defaultAmbxstBinds: {
        ambxst: {
            launcher: {
                modifiers: ["SUPER"],
                key: "D",
                action: action("ambxst.launcher")
            }
        }
    }
}, "scrolling");
assert(defaultsOnly.total === 0, "defaultAmbxstBinds no debe mostrarse como estado activo");

console.log(`OK: ${assertions} comprobaciones de ShortcutData.js`);
