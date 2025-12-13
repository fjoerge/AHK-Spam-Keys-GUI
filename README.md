# AHK-Spam-Keys-GUI

A configurable AutoHotkey-based input helper with a clean GUI: enable/disable multiple keys, set individual timers, and toggle everything with a single hotkey.
Settings are saved and can be reused across sessions.

Features
Toggle multiple keys on/off with one hotkey.

Per-key interval (ms) so each key can run at a different speed.

Persistent configuration via INI (portable-friendly).

Designed to be simple to set up and quick to adjust.

Getting started
Run the script (or compiled EXE).

Pick your toggle hotkey and enable the keys you want to repeat.

Set the interval per key and click Apply/Save (depending on your UI).

Use the toggle hotkey to start/stop sending inputs.

Configuration
Config is stored in an INI file (either next to the script/EXE or in your chosen config path).

Typical values to store:

Toggle hotkey (e.g. XButton2 or a keyboard hotkey).

Enabled keys (true/false per key).

Interval per key in milliseconds.

Example config.ini, can be filled via GUI:

text
[General]
ToggleHotkey=XButton2

[Keys]
Key1=1
Key1Enabled=1
Key1Interval=1250

Key4=4
Key4Enabled=1
Key4Interval=1250
