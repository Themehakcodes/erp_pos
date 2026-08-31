with open('d:/projects/ErpGoPos/erp_pos/lib/screens/main_home.dart', 'r', encoding='utf-8', newline='') as f:
    content = f.read()

# Fix 1: heartbeat off main thread
old_hb = '    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {\r\n      ApiService().heartbeat();\r\n    });'
new_hb = '    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {\r\n      Future.microtask(() => ApiService().heartbeat());\r\n    });'
if old_hb in content:
    content = content.replace(old_hb, new_hb)
    print("heartbeat: OK")
else:
    print("heartbeat pattern not found - skipping")

# Fix 2: IndexedStack -> Offstage
old_idx = 'IndexedStack(\r\n        index: _currentIndex,\r\n        children: ['
new_body_start = 'Stack(\r\n        children: ['
if old_idx in content:
    content = content.replace(old_idx, new_body_start)
    print("IndexedStack header: OK")

# Wrap each child in Offstage
import re

def wrap_offstage(m):
    text = m.group(0)
    text = text.replace(
        '          PosScreen(\r\n            onSaleCompleted: _recordSale,\r\n            selectedPrinter: _selectedPrinter,\r\n          ),',
        '          Offstage(\r\n            offstage: _currentIndex != 0,\r\n            child: PosScreen(\r\n              onSaleCompleted: _recordSale,\r\n              selectedPrinter: _selectedPrinter,\r\n            ),\r\n          ),'
    )
    text = text.replace(
        '          SalesScreen(\r\n            openingBalance: widget.openingBalance,\r\n            totalCash: _totalCash,\r\n            totalUpi: _totalUpi,\r\n          ),',
        '          Offstage(\r\n            offstage: _currentIndex != 1,\r\n            child: SalesScreen(\r\n              openingBalance: widget.openingBalance,\r\n              totalCash: _totalCash,\r\n              totalUpi: _totalUpi,\r\n            ),\r\n          ),'
    )
    text = text.replace(
        '          SettingsTab(\r\n            currentPrinter: _selectedPrinter,\r\n            onPrinterSelected: _setPrinter,\r\n          ),',
        '          Offstage(\r\n            offstage: _currentIndex != 2,\r\n            child: SettingsTab(\r\n              currentPrinter: _selectedPrinter,\r\n              onPrinterSelected: _setPrinter,\r\n            ),\r\n          ),'
    )
    return text

# apply to the Stack children section
content = re.sub(
    r'Stack\([\s\S]+?children: \[[\s\S]+?\],\r\n      \),\r\n      bottomNavigationBar',
    wrap_offstage,
    content,
    count=1
)

# Fix 3: simplify onTap
old_tap = '        onTap: (index) {\r\n          setState(() {\r\n            _currentIndex = index;\r\n          });\r\n        },'
new_tap = '        onTap: (index) => setState(() => _currentIndex = index),'
if old_tap in content:
    content = content.replace(old_tap, new_tap)
    print("onTap: OK")

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/main_home.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(content)

print("Done!")
