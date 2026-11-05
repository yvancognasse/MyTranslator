# MyTranslator

Native macOS translation application. Swift sources are in `Sources`, localized interface strings in `Resources`, and the English user guide in `Documentation/UserGuide.html`. Build using `create_app.sh`.

## Source repository

Public repository: [MyTranslator](https://github.com/yvancognasse/MyTranslator). This local folder remains the development/build checkout. Git history starts with the current imported source snapshot; earlier local builds are not reconstructed as historical commits.

After authorized changes, run the project checks and update documentation as required in `AGENTS.md`, then commit and push to `origin/main`. Changes reach GitHub when a push succeeds, not automatically on every file save. Generated applications, caches, logs and local secrets are excluded by `.gitignore`.

```sh
git pull --ff-only
# Make and verify the change
git add .
git commit -m "Describe the change"
git push origin main
```

## Restored application baseline

On November 5, 2026, the local application was rolled back to the preserved, signed October 19 build 102. Its bundled guide and localization catalog match the initial source import (`e3dbb6d`). The application source and catalog have been restored to that earliest available source snapshot; Git history starts on November 1 and cannot independently prove the October 19 source revision. Later shortcut, translation-process, replacement and clipboard changes have been removed. The safer staged build packaging remains in place.

Run `bash create_app.sh` to validate localization completeness, compile the restored source and sign the application. A rebuild produces a new build number. The rollback itself installs the preserved October 19 bundle without modifying its signature. Existing macOS preferences are retained. The newer local application is preserved under the ignored `.build` directory.
