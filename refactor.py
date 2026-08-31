import os
import re

def extract_classes(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Simple brace counting parser to extract classes
    classes = {}
    lines = content.split('\n')
    
    current_class = None
    class_lines = []
    brace_count = 0
    in_class = False
    
    imports = []
    other_top_level = []
    
    for line in lines:
        if not in_class:
            if line.startswith('import '):
                imports.append(line)
                continue
            
            match = re.match(r'^(class|enum)\s+([A-Za-z0-9_]+)', line)
            if match:
                in_class = True
                current_class = match.group(2)
                class_lines = [line]
                brace_count = line.count('{') - line.count('}')
                if brace_count == 0 and '{' in line:
                    # Single line class
                    classes[current_class] = '\n'.join(class_lines)
                    in_class = False
                continue
            else:
                other_top_level.append(line)
        else:
            class_lines.append(line)
            brace_count += line.count('{') - line.count('}')
            if brace_count <= 0:
                classes[current_class] = '\n'.join(class_lines)
                in_class = False
                current_class = None

    return imports, other_top_level, classes

def main():
    base_dir = r'd:\projects\ErpGoPos\erp_pos'
    filepath = os.path.join(base_dir, 'lib/main.dart')
    imports, other, classes = extract_classes(filepath)
    
    print(f"Found {len(classes)} classes")
    print(list(classes.keys()))
    
    screens_dir = os.path.join(base_dir, 'lib/screens')
    models_dir = os.path.join(base_dir, 'lib/models')
    os.makedirs(screens_dir, exist_ok=True)
    os.makedirs(models_dir, exist_ok=True)
    
    # 1. Models
    models = ['Product', 'CartItem', 'PrinterType', 'SelectedPrinter']
    models_content = "import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';\n\n"
    for m in models:
        if m in classes:
            models_content += classes[m] + '\n\n'
            
    with open(os.path.join(models_dir, 'models.dart'), 'w', encoding='utf-8') as f:
        f.write(models_content)
        
    # 2. Extract screens to individual files
    screen_groups = {
        'opening_balance_screen': ['OpeningBalanceScreen', '_OpeningBalanceScreenState'],
        'main_home': ['MainHome', '_MainHomeState'],
        'pos_screen': ['PosScreen', '_PosScreenState'],
        'sales_screen': ['SalesScreen'],
        'settings_tab': ['SettingsTab', '_SettingsTabState'],
        'login_screen': ['LoginScreen', '_LoginScreenState'],
        'splash_loader': ['SplashLoader', '_SplashLoaderState'],
        'device_not_registered_screen': ['DeviceNotRegisteredScreen', '_DeviceNotRegisteredScreenState']
    }
    
    common_imports = "\n".join(imports) + "\nimport '../api_service.dart';\nimport '../models/models.dart';\nimport 'package:flutter/material.dart';\n\n"
    
    for filename, class_names in screen_groups.items():
        content = common_imports
        for c in class_names:
            if c in classes:
                content += classes[c] + '\n\n'
        with open(os.path.join(screens_dir, f'{filename}.dart'), 'w', encoding='utf-8') as f:
            f.write(content)
            
    # 3. Write new main.dart
    main_imports = "\n".join(imports) + "\n"
    for filename in screen_groups.keys():
        main_imports += f"import 'screens/{filename}.dart';\n"
        
    main_content = main_imports + "\n" + "\n".join(other) + "\n"
    if 'PosApp' in classes:
        main_content += classes['PosApp'] + '\n'
        
    with open(os.path.join(base_dir, 'lib/main.dart'), 'w', encoding='utf-8') as f:
        f.write(main_content)

if __name__ == '__main__':
    main()
