# Running Tests

Use these commands when validating Hephaestus changes from the repository root.

## Fast Checks

Run Swift lint on changed Swift files:

```bash
./scripts/lint.sh
```

Check for whitespace and patch-format issues:

```bash
git diff --check
```

## App Build

Build the macOS app without signing:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Unit Tests

Run the Hephaestus unit test target without signing:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.1 -only-testing:HephaestusTests test
```

This command may emit macOS 26.1 deployment-target warnings when using Xcode 26.0. Those warnings are expected in the current local setup if the tests still pass.

## UI Tests

Run UI tests with normal local signing. Do not pass `CODE_SIGNING_ALLOWED=NO`.

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' -only-testing:HephaestusUITests test
```

Focused UI test example:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' -only-testing:HephaestusUITests/HephaestusUITests/testPlanningReviewWorkflowStartsInteractiveWaitingState test
```

Disabling code signing for UI tests can cause the UI test runner to exit before bootstrapping, often with an early unexpected exit or automation-session setup failure. If that happens, rerun the UI test command without `CODE_SIGNING_ALLOWED=NO`.

