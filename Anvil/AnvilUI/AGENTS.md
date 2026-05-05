# AGENTS.md

## Module Purpose

`AnvilUI` is the rendered Anvil design-system layer. It owns reusable, product-neutral SwiftUI components built from `AnvilTheme` tokens.

## Boundary Rules

- Import `AnvilTheme` for tokens and environment access.
- Do not import `Anvil`, app targets, or feature/domain packages.
- Components should accept primitive values, closures, bindings, or generic `ViewBuilder` content.
- Keep task, workflow, run, provider, message, and project concepts in feature modules.
- Tokens and concrete presets such as `.anvilWorkbench` live in `AnvilTheme`; reusable rendered views live here.
- Organize rendered UI elements by size:
  - `Atoms`: smallest reusable rendered views, such as icon buttons, badges, and status text.
  - `Molecules`: small composed elements, such as rows, banners, and compact disclosure controls.
  - `Components`: larger reusable surfaces or sections, such as log surfaces, panels, and empty states.
