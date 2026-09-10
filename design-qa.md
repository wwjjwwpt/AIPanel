# Design QA

Reference: selected ideation direction 1, the compact keyboard-first macOS command shelf.

Runtime checked on macOS using the installed `/Applications/瞬贴.app` build.

## Visual and interaction checks

- Pass: compact floating native macOS panel with a dominant search field.
- Pass: unified filters for all items, clipboard items, and screenshots.
- Pass: keyboard hints, selected-row action, empty state, and recording status are readable without crowding.
- Pass: global `⌘⇧V` opens the panel from Finder.
- Pass: opening the app displays the panel instead of appearing unresponsive.
- Pass: first launch displays a native folder chooser for the screenshot archive workspace.
- Pass: Settings exposes launch at login, archive workspace, screenshot source, history cleanup, and Quit.
- Pass: choosing an item copies it, returns to the previous app, and leaves normal `⌘V` as the paste action.
- Pass: search is cleared whenever the panel is reopened so a stale query cannot make the app appear empty.

The native implementation intentionally omits the mockup's decorative desktop wallpaper and sample history; it uses the user's real desktop and real local history instead.

final result: passed
