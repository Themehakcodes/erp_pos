import re

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/splash_loader.dart', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = r"      } catch \(e\) \{\n        if \(e\.toString\(\)\.contains\('Session expired'\)[\s\S]*?\} catch\(e\) \{\n      if \(mounted\) ScaffoldMessenger.*?\}\n    \}"

replacement = """      } catch (e) {
        if (e.toString().contains('Session expired') || e.toString().contains('Unauthorized') || e.toString().contains('revoked')) {
          await prefs.remove('access_token');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          return;
        }
        
        final offlineShiftId = prefs.getString('shift_id');
        if (offlineShiftId != null) {
           if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: 0.0)));
           return;
        }
        
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeviceNotRegisteredScreen(deviceId: deviceId)));
      }
    } catch(e) {
      final offlineShiftId = prefs.getString('shift_id');
      if (offlineShiftId != null) {
         if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: 0.0)));
         return;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }"""

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/splash_loader.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)
