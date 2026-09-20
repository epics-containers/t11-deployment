# Terminal shortcuts

This project uses a curated `terminal.integrated.commandsToSkipShell` list for
Codex, Pi and Claude Code. Blanket forwarding is disabled. A minus prefix
releases a VS Code command's shortcuts to the terminal; the remaining default
VS Code terminal shortcuts retain their normal behavior.

`settings.json` applies when opening this folder directly. For multi-folder
use, copy these settings into the `settings` object of your `.code-workspace`
file: these window settings cannot be applied from individual folders.
The local `t11-deployment.code-workspace` has been updated but is Git-ignored.
User settings are unchanged.

| Released conflict (standard Windows/Linux bindings) | Agent use |
| --- | --- |
| Toggle Panel: Ctrl+J | Newline |
| Quick Open: Ctrl+P | Pi model cycling / CLI navigation |
| Terminal Find: Ctrl+F | Move cursor forward / transcript search |
| Zoom Out: Ctrl+- | Pi undo |
| Kill terminal editor: Ctrl+W | Delete previous word even in an editor-area terminal |
| Next/previous terminal or editor: Ctrl+PageUp/PageDown | Pi editor paging |
| Next/previous terminal pane: Alt+Down/Up | Pi model ordering / restore queued messages |
| Terminal command scrolling: Ctrl+Up/Down | Agent transcript navigation |
| Terminal selection/line scrolling: Ctrl+Shift+Up/Down | Pi transcript navigation |
| Terminal top/bottom scrolling: Ctrl+Home/End | Pi editor start/end |
| Terminal width toggle: Alt+Z | Pi undo on WSL |

Ordinary CLI keys such as Ctrl+A/B/E/G/K/L/O/R/S/T/U/Y and Alt+B/F/D
already pass through under VS Code defaults and need no command exclusions.
Bindings can vary by platform, extensions and custom user keybindings.

The Command Palette command is explicitly retained: **Ctrl+Shift+P and F1**
remain VS Code shortcuts with terminal focus. This deliberately takes priority
over Pi's previous-model shortcut; use Ctrl+L for the model picker or Ctrl+P
to cycle forward. Terminal toggle, new/split terminal, standard copy/paste,
Shift+PageUp/PageDown scrollback and other unlisted defaults are retained.

`allowChords: false` releases chord prefixes such as Ctrl+K and Ctrl+X for
CLI editing and sequences. VS Code chord shortcuts are consequently unavailable
with terminal focus. `allowMnemonics: false` releases Alt menu shortcuts, and
`macOptionIsMeta: true` enables Option as Meta on macOS.

Workspace settings operate on command IDs, not exact keys, so all shortcuts
for each excluded command are affected. VS Code does not natively support a
project `.vscode/keybindings.json`. On Windows, Ctrl+V remains VS Code paste;
Pi/Claude offer Alt+V for CLI clipboard actions. Clipboard access itself still
depends on where the agent runs. On macOS, Command shortcuts may stay with
VS Code; this configuration primarily targets the Ctrl/Alt CLI bindings.

Older VS Code versions may not distinguish Shift+Enter; Ctrl+J is the newline
fallback. If Tab changes focus, turn off **Tab Key Moves Focus** using the
Command Palette. OS/browser-reserved keys cannot be overridden here.

Validation: both JSON files parse, their terminal settings match, and command
IDs were checked against VS Code source. The user confirmed that existing
Ctrl+Alt+Shift+Super (Hyper) bindings still work; no Hyper overrides were needed.
Other desktop keyboard delivery remains unverified. With terminal focus,
check Ctrl+Shift+P opens the Command Palette,
then Escape back to the terminal and check Ctrl+J inserts a newline in Codex.

Sources:

- [VS Code terminal shortcuts](https://code.visualstudio.com/docs/terminal/advanced#_keyboard-shortcuts-and-the-shell)
- [Multi-root setting scope](https://code.visualstudio.com/docs/editing/workspaces/multi-root-workspaces#_settings)
- [Pi keybindings](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md)
- [Claude interactive controls](https://code.claude.com/docs/en/interactive-mode)
