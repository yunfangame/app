import 'package:fl_clash/common/linux_tray.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray/tray.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  test(
    'Linux tray preserves callbacks, disabled state and nested selections',
    () {
      MenuItem? selected;
      final node = MenuItem.checkbox(
        label: 'Hong Kong',
        checked: true,
        onClick: (item) => selected = item,
      );
      var exits = 0;
      final converted = toLinuxTrayMenu([
        MenuItem(label: 'Login', disabled: true),
        MenuItem.submenu(
          label: 'Nodes',
          submenu: Menu(items: [node]),
        ),
        MenuItem.separator(),
        MenuItem(label: 'Exit', onClick: (_) => exits++),
      ]);
      expect((converted[0] as TrayMenuAction).enabled, isFalse);
      final group = converted[1] as TrayMenuSubmenu;
      expect(group.label, 'Nodes');
      final checkbox = group.items.single as TrayMenuCheckbox;
      expect(checkbox.checked, isTrue);
      checkbox.onSelected!();
      expect(selected, same(node));
      expect(converted[2], isA<TrayMenuSeparator>());
      (converted[3] as TrayMenuAction).onSelected!();
      expect(exits, 1);
    },
  );
}
