# Shared TUI keybinding table for the Pi-compatible clients (Pi, Prime).
# Both renderers serialize this one table; client-specific additions stay
# local `//` overrides in the renderer that owns them.
{
  "tui.editor.cursorUp" = [
    "up"
    "ctrl+p"
  ];
  "tui.editor.cursorDown" = [
    "down"
    "ctrl+n"
  ];
  "tui.editor.cursorLeft" = [
    "left"
    "ctrl+b"
  ];
  "tui.editor.cursorRight" = [
    "right"
    "ctrl+f"
  ];
  "tui.editor.cursorWordLeft" = [
    "alt+left"
    "alt+b"
  ];
  "tui.editor.cursorWordRight" = [
    "alt+right"
    "alt+f"
  ];
  "tui.editor.deleteCharForward" = [
    "delete"
    "ctrl+d"
  ];
  "tui.editor.deleteCharBackward" = [
    "backspace"
    "ctrl+h"
  ];
  "tui.input.newLine" = [
    "shift+enter"
    "ctrl+j"
  ];
  "app.model.select" = [ "ctrl+l" ];
}
