# Mock Implementation Review Loop Plan

## Summary
Create a tiny documentation-only artifact that proves the implementation review loop can:
- read this plan,
- make a scoped change,
- report changed files,
- survive a build command,
- receive reviewer feedback without touching unrelated files.

This is a smoke-test plan for the workflow runner. It should not change app behavior.

## Scope
Add one new Markdown file:

`docs/workflows/mock-implementation-loop-result.md`

Do not modify Swift source files, project files, package manifests, existing docs, or generated files.

## Requirements
The new document should include:
- A title: `Mock Implementation Loop Result`
- A short purpose section explaining that the file was created by the implementation review workflow smoke test.
- A checklist with these exact items:
  - `Plan file was read`
  - `Implementation phase created this file`
  - `Build phase can run after implementation`
  - `Review phase can inspect the resulting diff`
- A "Changed Paths" section listing only `docs/workflows/mock-implementation-loop-result.md`.

## Acceptance Criteria
- Only `docs/workflows/mock-implementation-loop-result.md` is added or modified by this plan.
- The file is valid Markdown.
- The document does not include timestamps, machine-specific paths, or environment-specific output.
- The implementer reports the changed path at the end.

## Reviewer Guidance
Reviewers should pass if:
- the change is limited to the requested Markdown file,
- all required sections/checklist items are present,
- no unrelated files were edited.

Reviewers should report a P1/P2 finding if:
- Swift source, project files, package manifests, or unrelated docs were changed,
- the required checklist or changed-path section is missing,
- the changed path list includes anything other than the requested result file.

## Suggested Build Command
For a fast smoke test in this repository, use:

`xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
