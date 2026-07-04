# MiniClock for Windows 10/11

A tiny transparent clock that stays above every window and lives quietly in the
notification area, similar to Lightshot or Ditto.

## Start it

Double-click **Start MiniClock.cmd**. No installation or extra runtime is needed.

Drag the clock anywhere. Right-click either the clock or its notification-area
icon to open the menu.

## Controls

- Switch between 12-hour and 24-hour time
- Show or hide seconds and the date
- Choose size, opacity, color, and text shadow
- Lock the clock in place
- Enable click-through mode
- Start automatically with Windows
- Hide/show from the notification-area icon
- Hold **Ctrl** and scroll over the clock for fine opacity adjustment

When click-through mode is active, use the notification-area icon to open the
menu again. Settings and screen position are saved in
`%APPDATA%\MiniClock\settings.json`.

## Uninstall

Exit MiniClock from its notification-area menu, delete this folder, and remove
the `MiniClock` shortcut from `shell:startup` if startup was enabled.
