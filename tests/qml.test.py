#!/usr/bin/env python3
"""Render the actual row delegate in isolated Qt 6; never load Ambxst services."""
from pathlib import Path
import os, re, shutil, subprocess, tempfile
project = Path(__file__).resolve().parents[1]
runner = shutil.which('qmltestrunner6') or '/usr/lib/qt6/bin/qmltestrunner'
if not Path(runner).is_file():
    raise SystemExit('Qt 6 qmltestrunner unavailable; this probe was NOT executed.')
source = project / 'src/modules/widgets/shortcuts'
qml = (source / 'ShortcutsOverlay.qml').read_text()
start = qml.index('delegate: Item {', qml.index('model: sectionCard.modelData.rows')) + len('delegate: ')
opening = qml.index('{', start); depth = 1; end = opening+1
while depth:
    depth += (qml[end] == '{') - (qml[end] == '}'); end += 1
row = qml[start:end]
row = row.replace('id: shortcutRow', 'id: shortcutRow\nproperty alias actionText: actionLabel\nproperty alias keysColumn: keyColumn')
row = row.replace('required property var modelData', 'property var modelData', 1).replace('required property int index', 'property int index: 0', 1)
row = row.replace('StyledRect {', 'Rectangle {').replace('variant: "common"', 'color: "#333333"')
row = row.replace('Config.theme.font', '"sans-serif"').replace('color: keyPill.item', 'color: "white"')
row = re.sub(r'Styling.fontSize\(-\d\)', '13', row)
row = re.sub(r'Styling.radius\(-\d\)', '4', row)
row = re.sub(r'Colors\.\w+', '"white"', row)
row = row.replace('visible: shortcutRow.index < sectionCard.modelData.rows.length - 1', 'visible: false')
probe = '''import QtQuick
import QtQuick.Layouts
import QtTest
import "ShortcutData.js" as ShortcutData
Item {
 id: root
 width: 1280; height: 1000
 property int columnCount: 1
 property list<string> modifiers: ["SUPER", "CTRL"]
 property list<var> custom: [{keys:[{key:"T"}], actions:[{id:"future.action"}]}]
 property QtObject core: QtObject {
  property QtObject launcher: QtObject {
   property list<string> modifiers: ["SUPER"]
   property string key: "Super_L"
   property var action: ({id:"ambxst.launcher"})
  }
 }
 Component { id: rowFactory
 ROW
 }
 TestCase {
  name: "OverlayHardening"; when: windowShown
  function test_qmlSequences() {
   compare(ShortcutData.normalizeModifiers(root.modifiers).join("+"), "SUPER+CTRL");
   var result = ShortcutData.build({ambxst:root.core,custom:root.custom},"scrolling");
   compare(result.error, ""); compare(result.total, 2);
  }
  function test_rows_data() {
   return [{tag:"one-long",columns:1,panel:600,longText:true},
           {tag:"two-long",columns:2,panel:900,longText:true},
           {tag:"three-long",columns:3,panel:1200,longText:true},
           {tag:"one-normal",columns:1,panel:600,longText:false},
           {tag:"two-normal",columns:2,panel:900,longText:false},
           {tag:"three-normal",columns:3,panel:1200,longText:false}];
  }
  function test_rows(data) {
   root.columnCount = data.columns;
   var label = data.longText ? "AccionSinSeparadores".repeat(40) : "Cambiar foco";
   var key = data.longText ? "SUPER + CTRL + ALT + SHIFT + " + "TeclaLarga".repeat(20) : "SUPER + T";
   var row = createTemporaryObject(rowFactory, root, {width:data.panel/data.columns-48,
        modelData:{label:label,combos:[{text:key},{text:"ALT + T"}]}});
   verify(row !== null); wait(30);
   var action = row.actionText;
   verify(action.contentWidth <= action.width + 1, "action overflow");
   verify(row.implicitHeight >= action.y + action.implicitHeight, "row clips label");
   verify(row.implicitHeight >= row.keysColumn.implicitHeight, "row clips key column");
   var pills = row.keysColumn.children;
   var checked = 0;
   for (var i=0; i<pills.length; i++) {
    if (!pills[i].modelData) continue;
    var text = pills[i].children[0];
    verify(text.contentWidth <= text.width + 1, "key overflow");
    verify(pills[i].height >= text.implicitHeight, "pill clips key"); checked++;
   }
   compare(checked, 2);
  }
 }
}
'''.replace('ROW', row)
with tempfile.TemporaryDirectory(prefix='ambxst-qml-', dir='/tmp') as directory:
    target=Path(directory)
    shutil.copy2(source / 'ShortcutData.js', target / 'ShortcutData.js')
    (target / 'tst_overlay.qml').write_text(probe)
    env=os.environ.copy();env.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
    raise SystemExit(subprocess.run([runner,'-input',directory],env=env,timeout=30).returncode)
