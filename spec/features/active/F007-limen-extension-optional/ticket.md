# F007 · pi and omp start in this repo without limen installed

## Outcome

A contributor or CI machine without limen can run `pi` or `omp` in the vscreen repo. Today the committed project extension stops pi at startup with "limen is not on PATH; cannot load package hooks", and omp prints the same error. After this change the extension loads nothing when limen is absent. Adam's plant keeps every limen hook when limen is installed.

## Scope

- The two committed project stubs: `.pi/extensions/limen.ts` and `.omp/extensions/limen.ts`.
- Limen is absent when `LIMEN_PACKAGE` is unset or empty and no `limen` executable is on PATH. Then the stub returns without loading hooks and without an error.
- Limen is present when `LIMEN_PACKAGE` is set or `limen` is on PATH. Then the stub loads the wake, communication, steering and group-peer hooks as before.

## Out of scope

- Changes to the limen package or its hooks.
- Removing or relocating the stubs, or a different discovery rule (for example a config file).
- Any vscreen Swift source.

## Acceptance

- With PATH stripped of limen and `LIMEN_PACKAGE` unset, importing each stub and calling its default export resolves without an error and registers no hooks.
- With PATH stripped of limen and `LIMEN_PACKAGE` set to the package root, each stub registers the limen hooks.
- With limen on PATH and `LIMEN_PACKAGE` unset, each stub registers the limen hooks.
- `pi -p` started in the repo with PATH stripped of limen gets past extension loading (no "Failed to load extension" error).
- `omp -p` started in the repo with PATH stripped of limen prints no "Failed to load extension" error.

## Notes

- The absent case is silent on purpose. A startup log line would add noise to every contributor session.
