# AGENTS.md

## Module Purpose

`AnvilTheme` defines the Anvil design language. It owns the theme types, concrete theme presets, and SwiftUI environment plumbing used to represent visual tokens: colors, spacing, typography, radii, and motion.

## Boundary Rules

- Keep this package component-free.
- Concrete theme presets such as `.anvilWorkbench` and `.hephaestus` belong here.
- Do not import `Anvil`, `AnvilUI`, app targets, or feature/domain packages.
- Add token categories only when reusable UI or feature code needs a stable shared vocabulary.
- Prefer semantic token names over feature names or one-off color descriptions.

Reusable rendered components belong in `AnvilUI`.
