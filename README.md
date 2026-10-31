# MyTranslator

Native macOS translation application. Swift sources are in `Sources`, localized interface strings in `Resources`, and the English user guide in `Documentation/UserGuide.html`. Build using `create_app.sh`.

## Source repository

Private repository: [MyTranslator](https://github.com/yvancognasse/MyTranslator). This local folder remains the development/build checkout. Git history starts with the current imported source snapshot; earlier local builds are not reconstructed as historical commits.

After authorized changes, run the project checks and update documentation as required in `AGENTS.md`, then commit and push to `origin/main`. Changes reach GitHub when a push succeeds, not automatically on every file save. Generated applications, caches, logs and local secrets are excluded by `.gitignore`.

```sh
git pull --ff-only
# Make and verify the change
git add .
git commit -m "Describe the change"
git push origin main
```

## Stability checks

```sh
swiftc -parse-as-library Sources/TranslationProcess.swift Tests/StabilityTests.swift -o /tmp/mytranslator-stability-tests
/tmp/mytranslator-stability-tests
```

The tests use synthetic text and child processes; they do not access the clipboard or translate private content. Builds retain the previous app until compilation and signing succeed.
