## Imported Claude Cowork project instructions

## Documentation and interface language

- Every development change must update `Documentation/UserGuide.html` in English before rebuilding the app. Keep its "What's new" section current and revise the affected instructions, not just the build number.
- Keep every user-facing string in `Resources/InterfaceLocalizations.json` for every language listed there. Add new English keys through `UILocalization.text` and verify catalog completeness before shipping.
- The app's interface follows the saved Primary language in Settings. The Help menu and its label follow that language; the user guide itself remains in English.

## GitHub source management

- The private source repository is `https://github.com/yvancognasse/MyTranslator`. This Mac folder remains the working checkout for native development and local tests.
- Use the `main` branch and `origin` remote. Preserve unrelated user changes. Commit and push authorized completed code changes after the required documentation updates and checks; report any blocked push explicitly.
- Exclude generated builds, compiled applications, caches, logs, credentials, tokens, local configuration and signing material. Never change the repository visibility or access without explicit instruction.
