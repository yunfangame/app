import 'package:tray/tray.dart';
import 'package:tray_manager/tray_manager.dart';

List<TrayMenuItem> toLinuxTrayMenu(List<MenuItem> items) => [
  for (final item in items)
    switch (item.type) {
      'separator' => const TrayMenuSeparator(),
      'checkbox' => TrayMenuCheckbox(
        label: item.label ?? '',
        checked: item.checked ?? false,
        enabled: !item.disabled,
        onSelected: () => item.onClick?.call(item),
      ),
      'submenu' => TrayMenuSubmenu(
        label: item.label ?? '',
        items: toLinuxTrayMenu(item.submenu?.items ?? []),
        enabled: !item.disabled,
      ),
      _ => TrayMenuAction(
        label: item.label ?? '',
        enabled: !item.disabled,
        onSelected: () => item.onClick?.call(item),
      ),
    },
];
