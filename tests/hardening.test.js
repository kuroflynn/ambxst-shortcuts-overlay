#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = path.resolve(__dirname, '../src/modules/widgets/shortcuts');
const api = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(source, 'ShortcutData.js'), 'utf8').replace(/^\.pragma library\s*/, ''), api);
let count = 0;
function test(name, fn) { fn(); console.log(`ok ${++count} - ${name}`); }
const binding = (id='future.action', name='Acción') => ({name, keys:[{key:'T',modifiers:['SUPER']}],actions:[{id}]});
const build = custom => api.build({custom}, 'scrolling');
const rows = result => result.sections.flatMap(s => s.rows);
function rejected(model) {
    api.input = model;
    const result = vm.runInContext('build(input, "scrolling")', api, {timeout:500});
    assert.ok(result.error); assert.equal(result.total, 0); assert.equal(result.sections.length,0);
}
for (const length of [-1, 1.5, Infinity, 1000000000])
    test(`QA-004 forged custom length ${length}`, () => rejected({custom:{length}}));
for (const field of ['keys','actions'])
    test(`QA-004 forged ${field}`, () => rejected({custom:[{...binding(),[field]:{length:1000000000}}]}));
for (const [field, value] of [['modifiers',{length:1000000000}],['modifiers','SUPER']])
    test(`QA-004 invalid ${field} ${typeof value}`, () => rejected({custom:[{...binding(),keys:[{key:'T',[field]:value}]}]}));
test('QA-004 forged layouts', () => rejected({custom:[{...binding(),actions:[{id:'future.action',layouts:{length:1000000000}}]}]}));
test('QA-004 sparse oversized real array', () => rejected({custom:new Array(1000000000)}));
test('QA-004 expanded work budget', () => rejected({custom:Array.from({length:200},(_,i)=>({...binding('future.'+i),keys:Array.from({length:64},(_,k)=>({key:'Key'+k})),actions:Array.from({length:64},(_,a)=>({id:'future.'+a}))}))}));
test('QA-004 cyclic arguments', () => { const args={};args.self=args;rejected({custom:[{...binding(),actions:[{id:'future.action',args}]}]}); });
test('QA-004 deeply nested arguments', () => { let args={};for(let i=0;i<100;i++)args={next:args};rejected({custom:[{...binding(),actions:[{id:'future.action',args}]}]}); });
test('QA-004 text limit', () => rejected({custom:[binding('future.action','X'.repeat(32769))]}));
test('QA-004 JSON length limit', () => assert.equal(api.parseJson(' '.repeat(2097153)).ok,false));
test('QA-004 numeric labels sort as text', () => { const r=build([binding('future.one',42),binding('future.two',43)]);assert.equal(r.error,'');assert.deepEqual(Array.from(rows(r),r=>r.label),['42','43']); });
test('QA-004 valid long label remains intact', () => {const label='L'.repeat(10000);assert.equal(rows(build([binding('future.action',label)]))[0].label,label);});
for (const name of ['Configure Lid Switch','Turn display off on lid close','Turn display on lid open'])
    test(`QA-005 normal key named ${name}`, () => assert.equal(build([binding('future.action',name)]).total,1));
test('QA-005 mixed hardware and keyboard alternatives', () => {
    const b=binding();b.keys=[{key:'switch:Lid Switch'},{key:' event:test'},{key:'Lid Switch'},{key:'T',modifiers:['SUPER']}];
    const r=rows(build([b]));assert.equal(r.length,1);assert.deepEqual(Array.from(r[0].combos,c=>c.text),['SUPER + T']);
});
for (const id of ['constructor','toString','__proto__']) {
    test(`QA-010 custom ${id}`, () => {const r=rows(build([binding(id)]));assert.equal(r.length,1);assert.equal(r[0].actionId,id);});
    test(`QA-010 core ${id}`, () => {const core=Object.create(null);core[id]=binding(id);assert.equal(api.build({ambxst:core}).total,1);});
}
test('QA-009 compacted rows and plural', () => {
    const family=Array.from({length:10},(_,i)=>({keys:[{key:i===9?'0':String(i+1),modifiers:['SUPER']}],actions:[{id:'workspace.switch',args:{index:i+1}}]}));
    const r=build(family);assert.equal(r.total,1);assert.equal(api.rowCountLabel(r.total),'1 fila de atajos');
    assert.equal(api.rowCountLabel(2),'2 filas de atajos');assert.equal(api.rowCountLabel(0),'0 filas de atajos');
});
test('QA-004 refresh contains a thrown builder and clears stale state', () => {
    const qml=fs.readFileSync(path.join(source,'ShortcutsOverlay.qml'),'utf8');
    const body=qml.slice(qml.indexOf('    function refreshData()'),qml.indexOf('    function scrollBy('));
    const context=vm.createContext({Config:{keybindsLoader:{loaded:true,text:()=> '{}',adapter:{ambxst:{}}}},
        ShortcutData:{parseJson:api.parseJson,build(){throw Error('injected builder failure');}},
        GlobalStates:{compositorLayout:'scrolling'},sections:[1],shortcutCount:1,dataError:'',shortcutsFlickable:{contentY:20}});
    vm.runInContext(body+'\nrefreshData();',context,{timeout:500});
    assert.equal(context.sections.length,0);assert.equal(context.shortcutCount,0);assert.ok(context.dataError);
    assert.ok(qml.includes('ShortcutData.rowCountLabel(root.shortcutCount)'));
});
console.log(`OK: ${count} hardening regressions.`);
