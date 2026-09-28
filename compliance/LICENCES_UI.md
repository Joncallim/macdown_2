# Open Source Licences screen (LC-08): implementation contract

**Owner summary.** MostlyText needs an in-app screen that shows the licences
of every third-party component it ships, readable offline. This page fixes
the design so the screen can be built quickly once E22 is finished, without
a second copy of the notices to maintain. The screen shows the generated
`compliance/generated/THIRD_PARTY_NOTICES.md`, bundled into the app, in the
app's existing native Markdown preview.

**Not started. Starts after E22 closes**, because E22's session is actively
changing the same app menus and window code. It must land before the final
E16 string freeze (#17). It adds a few UI strings and no new dependency.

Risks: the screen could show a stale or hand-edited copy (prevented by
bundling the generated file and checking its digest in the signed app), and
licence text could be altered by rendering (prevented by showing licence
bodies as preformatted text, which the generator already emits).

## Behaviour

- **Entry points:** a button in the About window, and a Help menu item, both
  titled "Open Source Licences". Both open one read-only window; opening it
  again brings the existing window forward.
- **Content:** the bundled `THIRD_PARTY_NOTICES.md`, rendered with the same
  native preview used for Markdown documents (Textual, D4). Licence bodies are
  fenced as plain text by the generator, so they display verbatim.
- **Offline:** reads only the bundled resource. No network access, and no
  links opened automatically.
- **First-party licence:** the window leads with MostlyText's MIT licence
  and MacDown lineage (LC-10). Take the text from the bundled `LICENSE`,
  never from a copy typed into code.

## Implementation notes

- **Resource:** add `compliance/generated/THIRD_PARTY_NOTICES.md` and
  `LICENSE` to the app target's resources in `MacDown2/project.yml`, as
  references to those files rather than copies, then regenerate the project.
- **Strings:** the window title, button and menu titles, and any
  empty-or-error state go in the String Catalog for localisation. Licence text
  itself is never localised.
- **Errors:** if the resource is missing, show a short localised message and
  the source-repository URL, and fail loudly in Debug. A missing resource
  also fails `compliance.py check --artifact`.

## Tests and evidence

| Check | Where |
|---|---|
| The bundled notices load from the built app bundle, not from the source tree | App test against `Bundle.main` |
| The bundled file's digest equals the generated file | `compliance.py check --release --artifact MostlyText.app` (Mac, on the release candidate) |
| Keyboard: reachable from the menu, scrollable and closable with the keyboard; VoiceOver reads the headings | Manual pass on a Release build, recorded under `planning/evidence/` |
| Localisation: surrounding strings present in every shipped language, pseudo-localised layout OK | E16's final pass |
