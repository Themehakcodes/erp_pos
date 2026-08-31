import re

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix keyboard on Close Shift (add autofocus: true)
pattern1 = r"(\s+)(content: TextField\(\s+)(controller: txt,)"
replacement1 = r"\1\2autofocus: true,\n\1  \3"
content = re.sub(pattern1, replacement1, content)

# 2. Fix the loading indicator in _processPayment to look professional
pattern2 = r"showDialog\(\s*context: context,\s*barrierDismissible: false,\s*builder: \(\_\) => const Center\(child: CircularProgressIndicator\(\)\),\s*\);"
replacement2 = """showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Text('Processing Payment...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );"""
content = re.sub(pattern2, replacement2, content)

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
