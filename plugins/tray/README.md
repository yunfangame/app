# tray

Linux tray integration, selectively vendored from
[FlClash v0.8.98](https://github.com/chen08209/FlClash/tree/v0.8.98/plugins/tray)
(`7c61c90ac20493b474d19c75ec96262b478b4b88`). The upstream license is retained in `LICENSE`.

Only the Linux native backend is included and registered in this checkout. Windows and macOS continue using the existing
`tray_manager` package. The portable Dart API retains the upstream platform models, but those do not imply native support
in this local package. Existing application menus are adapted by `lib/common/linux_tray.dart` in the root package.

## API

The plugin owns call ordering, idempotency, call serialization and unchanged-payload suppression.
Callers declare the desired tray state; they never sequence platform calls themselves.

```dart
await Tray.instance.show(
  TraySpec(
    icon: TrayIcon.asset('assets/images/tray/unix/status_1.png', isTemplate: true),
    toolTip: 'FlClash',
    menu: [
      TrayMenuAction(label: 'Show', onSelected: showWindow),
      const TrayMenuSeparator(),
      TrayMenuCheckbox(label: 'TUN', checked: true, onSelected: toggleTun),
      TrayMenuSubmenu(label: 'Proxy', items: proxyItems),
    ],
  ),
);

await Tray.instance.setTitle('↑ 1.2 MB/s');
await Tray.instance.hide();
```

- `show` creates the tray on first call and reconciles it afterwards. Re-sending a structurally
  identical `TraySpec` performs no platform call, so callbacks may be rebuilt freely.
- `setTitle` is the incremental path for high-frequency text. It is a no-op where
  `capabilities.title` is false, and while no tray is visible.
- `hide` is idempotent and returns native state to "`show` was never called", so a later `show`
  rebuilds the tray from scratch.
- `openMenu` is a no-op where `capabilities.menuControl` is false.

`TrayIcon.asset` names a bundled PNG and follows Flutter's resolution-aware layout: every
`2.0x/`, `3.0x/`, `4.0x/` sibling that exists is loaded too. macOS receives them all as
representations of one `size`-point image; Linux is handed the largest raster on disk and lets the
indicator scale it; Windows loads the path as-is, so point it at a multi-size `.ico` instead. The macOS/Windows behavior
describes the upstream API, not native backends bundled here.

Menu item ids are assigned by pre-order position, so an unchanged menu serializes identically across
rebuilds and click dispatch stays stable while a menu is open.

## Events

`Tray.instance.events` is a broadcast stream of `TrayIconActivated`, `TrayMenuRequested` and
`TrayMenuItemSelected`. Per-item `onSelected` callbacks fire before the corresponding stream event.

## Capabilities

`Tray.instance.capabilities` reports the upstream platform capabilities. This checkout calls the plugin only on Linux.

| | macOS | Windows | Linux |
| --- | --- | --- | --- |
| `title` | yes | no | yes |
| `toolTip` | yes | yes | yes |
| `iconEvents` | yes | yes | no |
| `menuControl` | yes | yes | no |

Linux runs on AppIndicator/StatusNotifierItem, where the desktop shell owns the menu; the application
cannot receive icon clicks or open the menu itself.

## Linux requirements

`libayatana-appindicator3-dev`, or `libappindicator3-dev` as a fallback.
