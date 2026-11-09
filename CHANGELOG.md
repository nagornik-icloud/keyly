# Changelog

## 3.0.1

- Custom modules: a translation module could return the text untranslated or a refusal —
  the request no longer tells the model to "keep the text's language". The text is treated
  as data to transform, never as a message to answer.

## 3.0 — first public release

Features: layout switch (RU ⇄ EN), typo correction, voice to text (cloud or local model),
custom AI modules, snippets with trigger mode and search palette, app launcher, undo of the
last change, pause of all hotkeys from the menu bar, settings export/import.

Changes before the public release:

- API keys moved from settings to the macOS Keychain; plain-text copies are removed.
- The app is now `app.keyly.Keyly`; settings from the previous id are migrated on first launch.
- "Copy recognized text to the clipboard" option for dictation (on by default); the dictation
  indicator shows "Done · copied to clipboard".
- Custom module with the "selected text" source no longer sends the old clipboard to the AI
  when nothing is selected.
- A switched-off custom module no longer turns itself back on after restart and no longer
  fires on its hotkey.
- Settings import no longer resets every switch to its default; 7 more settings are exported.
- Undo, snippet palette and cheatsheet work on a bare or media key.
- Clipboard writes used only to paste are marked transient, so clipboard managers don't keep them.
- Dictation: a bad request is no longer retried on every key; the audio race on stop is fixed;
  leftover recordings are deleted at launch.
- The Gemini key is sent in a header, not in the request URL.
- All interface texts are in English and Russian.
