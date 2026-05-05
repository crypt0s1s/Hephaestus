# 0011. Anvil Design System Packages

**Status:** Proposed
**Date:** 2026-05-05
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define the package boundary for shared theme tokens and reusable base UI components before expanding workflow and task UI surfaces.

---

## Context

Hephaestus is starting to grow beyond the initial app shell and task workspace. The workflow runner now has project navigation, expandable workflow rows, step lists, status output, and macOS control styling. Similar local styling already exists in `TaskWorkspaceFeature`.

Today, styling is mostly embedded directly in views:

- raw `Color(nsColor:)` roles,
- repeated `.foregroundStyle(.secondary)` and `.buttonStyle(...)`,
- local spacing and corner radius choices,
- ad hoc sidebar row and panel styling, and
- local workflow/task row layouts.

ADR-0006 sketched future packages named `HephaestusTheme` and `HephaestusUI`. Later modularization notes also mention `HephaestusDesignSystem`. That direction kept design-system code product-specific, but the current direction is to put reusable theme and base UI infrastructure in the Anvil family.

This ADR amends ADR-0006's design-system package layout. ADR-0006 remains the source of truth for package-boundary principles and cross-package deep-link registration, but its `HephaestusTheme` / `HephaestusUI` package sketch is replaced by `AnvilTheme` / `AnvilUI`.

### Problem Statement

The project needs a shared design-system boundary that prevents every feature from inventing its own theme, spacing, button, row, and panel conventions while keeping product-specific workflow/task behavior out of generic UI infrastructure.

### Goals

- Establish separate packages for theme primitives and base UI components.
- Keep reusable design-system surfaces in the Anvil family.
- Preserve `Anvil` as the core architecture package for pages, interactors, routing, task scopes, and state primitives.
- Let feature packages adopt shared visual conventions without depending on app-specific implementation.
- Make theme tokens testable, discoverable, and stable enough to reuse across features.
- Keep first implementation small and driven by actual repeated UI patterns.

### Non-Goals

- Redesign the whole app in this ADR.
- Define every final color, typography, spacing, animation, or component.
- Move workflow/task domain concepts into Anvil packages.
- Introduce a third-party design framework.
- Create product-specific `HephaestusTheme`, `HephaestusUI`, or `HephaestusDesignSystem` packages as the primary design-system home.
- Define final ownership for Hephaestus-specific visual identity, brand presets, or product-only composite components.

---

## Decision Drivers

* Feature UI is beginning to duplicate styling and layout rules.
* The design direction is a dense, calm, native macOS workbench, not a marketing page or chatbot clone.
* Shared UI should be reusable by multiple product features without coupling them to each other.
* `Anvil` should stay generic, but design-system primitives are also generic enough to live beside it.
* Theme tokens should be separate from concrete components so low-level visual roles do not force a dependency on higher-level UI controls.
* The first package shape should leave room for growth without over-designing every component category.

---

## Considered Options

### Option 1: Product-Specific `HephaestusDesignSystem`

**Description:** Create one product-specific package that owns theme tokens and shared UI components for Hephaestus.

**Pros:**
- Clear product ownership.
- Avoids making Anvil responsible for visual style.
- Easy to place Hephaestus-specific workflow/task components there.

**Cons:**
- Blurs generic UI primitives with product-specific surfaces.
- Makes it harder to reuse the same foundation in Anvil-oriented proof apps.
- Conflicts with the current direction that the design system should be in the Anvil family.
- Encourages broad imports when a feature only needs theme tokens.
- Still may be needed later for Hephaestus-specific presets or product-only composites, but should not be the primary home for generic tokens and base controls.

### Option 2: `AnvilTheme` And `AnvilUI` As Separate Packages

**Description:** Create sibling packages to `Anvil`: `AnvilTheme` for core theme primitives and `AnvilUI` for reusable base UI components. `AnvilUI` may depend on `AnvilTheme`; `AnvilTheme` does not depend on `AnvilUI` or product packages.

**Pros:**
- Keeps architecture primitives, theme primitives, and UI components separate.
- Lets features import only tokens or both tokens and components.
- Keeps design-system code reusable outside Hephaestus-specific features.
- Avoids putting SwiftUI styling into the core `Anvil` architecture package.
- Creates a natural place for shared macOS workbench components like panels, rows, icon buttons, status labels, and disclosure rows.

**Cons:**
- Adds two packages to manage.
- Requires discipline to keep product-specific workflow/task concepts out of `AnvilUI`.
- May feel slightly heavier before several components have been extracted.

### Option 3: Keep Styling Local Until There Is More Duplication

**Description:** Continue styling views locally and defer design-system package creation.

**Pros:**
- No immediate package work.
- Keeps experimentation fast.
- Avoids premature abstraction.

**Cons:**
- Duplicated styling will keep spreading.
- Later extraction becomes more expensive and more subjective.
- The workflow runner and task workspace can drift visually.
- There is no obvious home for reusable disclosure rows, status labels, or panel primitives.

### Option 4: Put Theme And UI Components Directly In `Anvil`

**Description:** Expand the existing `Anvil` package to include theme tokens and base SwiftUI components.

**Pros:**
- Fewer packages.
- Simple imports for feature code that already depends on `Anvil`.
- Keeps all generic frontend foundation code in one place.

**Cons:**
- Turns `Anvil` into a mixed architecture and visual-style package.
- Forces consumers of routing/page primitives to also compile UI styling code.
- Makes the package less clean as a generic app architecture layer.
- Makes it harder to evolve theme and UI dependencies independently.

---

## Decision

Hephaestus will introduce two separate Anvil-family design-system packages:

- `AnvilTheme`: core theme implementation, semantic color roles, typography roles, spacing, radii, and animation constants.
- `AnvilUI`: reusable base UI components and modifiers built on top of `AnvilTheme`.

`Anvil` remains the generic app architecture package for interactor/page/router/task-scope/state primitives. It should not absorb theme or component code.

**Chosen Option:** Option 2 - `AnvilTheme` And `AnvilUI` As Separate Packages

### Rationale

The design-system foundation is generic enough to live with Anvil, but it is not the same responsibility as routing, page ownership, and interactor lifecycle. Separate packages preserve that distinction.

`AnvilTheme` should be the lowest-level visual layer. It should expose semantic roles rather than one-off raw colors, for example:

- window background,
- sidebar background,
- panel background,
- selection background,
- border/subtle separator,
- primary/secondary/tertiary text,
- success/warning/danger status,
- standard spacing and radius values, and
- standard animation durations.

The rough implementation model should keep the core theme categories explicit:

```swift
public struct AnvilTheme {
    public var colors: AnvilColors
    public var spacing: AnvilSpacing
    public var typography: AnvilTypography
    public var radii: AnvilRadii
    public var motion: AnvilMotion
}
```

The initial Anvil version should:

- use SwiftUI environment values as the main consumption path,
- support light and dark color roles,
- keep token names semantic rather than brand-specific,
- adapt color roles for macOS workbench surfaces,
- use a small semantic spacing scale, and
- omit iOS-only concepts such as status bar style.

`AnvilUI` should consume `AnvilTheme` and provide small, reusable base components. Initial candidates should come from actual repeated patterns, such as:

- icon-only toolbar buttons,
- sidebar rows,
- disclosure rows,
- status labels,
- panel sections, and
- bordered output/log surfaces.

Product concepts should remain outside these packages. `AnvilUI` can provide a disclosure-row shell, sidebar-row shell, list-row shell, or status-row shell, but it should not know what a Hephaestus workflow, task, run, or step is. Feature packages should provide the domain text, actions, step definitions, and state.

This amends the package direction sketched in ADR-0006. Where ADR-0006 mentions `HephaestusTheme` and `HephaestusUI`, the preferred design-system package names are now `AnvilTheme` and `AnvilUI`. If Hephaestus-specific visual identity or product-only composite components later need their own home, that should be decided separately without moving generic base primitives out of the Anvil family.

---

## Consequences

### Positive

- Features can share visual conventions without depending on each other.
- `Anvil` stays focused on app architecture primitives.
- Theme roles can stabilize before components are fully mature.
- The workflow runner and task workspace can converge visually.
- The project has a clear home for reusable macOS workbench UI.

### Negative

- Two additional packages increase package graph surface area.
- Some early components may need to move or be renamed as patterns become clearer.
- Review discipline is required to prevent product-specific concepts from entering `AnvilUI`.
- Hephaestus-specific visual identity or product-only composite components will need an app/product-owned home if they outgrow generic Anvil primitives.

### Neutral

- Existing app-local styling can migrate gradually.
- ADR-0006 remains valid for package-boundary principles, but its design-system package layout and package names are amended by this ADR.
- The app target may keep local experiments until at least one repeated pattern is worth extracting.

---

## Implementation

### Package Layout

The intended package layout is:

```text
Core/
  Anvil/
    Package.swift
    Sources/Anvil/
      Interactor/
      Page/
      Router/
      DeepLinking/
      TaskScope/
      State/

  AnvilTheme/
    Package.swift
    Sources/AnvilTheme/
      AnvilTheme.swift
      AnvilColors.swift
      AnvilTypography.swift
      AnvilSpacing.swift
      AnvilRadii.swift
      AnvilAnimation.swift

  AnvilUI/
    Package.swift
    Sources/AnvilUI/
      Buttons/
      Rows/
      Panels/
      Status/
      Logs/
```

### Dependency Rules

The dependency direction should be:

```text
Anvil
  -> no AnvilTheme dependency
  -> no AnvilUI dependency

AnvilTheme
  -> no Anvil dependency
  -> no product package dependency

AnvilUI
  -> AnvilTheme
  -> no Anvil dependency
  -> no product package dependency

Feature packages
  -> Anvil
  -> AnvilTheme when they only need tokens
  -> AnvilUI when they need reusable components
```

The app target remains the composition root and may import all three Anvil-family packages. `AnvilUI` should not depend on `Anvil` unless a later ADR creates a narrowly scoped bridge package for components that explicitly need page/router/interactor concepts.

### Initial Extraction Candidates

Start with the smallest surfaces that are already repeated or clearly about visual consistency:

- semantic color roles around macOS system colors,
- spacing/radius constants, and
- typography roles used by extracted components.

For the first `AnvilUI` slice, extract only:

- `AnvilIconButton`,
- `AnvilDisclosureRow`,
- `AnvilSidebarRow`,
- `AnvilStatusText`, and
- `AnvilLogSurface`.

Avoid extracting large product-specific workflow cards or task screens at first.

### Migration Strategy

1. Create `AnvilTheme` and `AnvilUI` package scaffolds.
2. Add a minimal token set in `AnvilTheme`: semantic colors, spacing, radii, and typography roles needed by the first components.
3. Extract `AnvilIconButton`, `AnvilDisclosureRow`, `AnvilSidebarRow`, `AnvilStatusText`, and `AnvilLogSurface` into `AnvilUI`.
4. Adopt those components in the workflow runner first.
5. Adopt the same primitives in `TaskWorkspaceFeature`.
6. Do not add more components until the first slice works in both call sites without feature-specific parameters.
7. Mark new public APIs as experimental in doc comments until they have at least two real call sites; promote them by removing the experimental note once the second call site proves the shape.

### Theme Consumption Shape

The expected application API should look like:

```swift
HephaestusRootView()
    .anvilTheme(.workbench)
```

`AnvilTheme` should own generic presets such as `.workbench`. If a product-branded preset is needed, the app or product layer should own that extension:

```swift
extension AnvilTheme {
    static let productWorkbench = AnvilTheme.workbench
}
```

Feature views can consume the theme directly for layout composition and one-off feature-specific content:

```swift
@Environment(\.anvilTheme) private var theme

Text(title)
    .font(theme.typography.headline)
    .foregroundStyle(theme.colors.textPrimary)
    .padding(theme.spacing.cozy)
```

Repeated controls, rows, status labels, and surfaces should consume theme indirectly through `AnvilUI` components:

```swift
AnvilDisclosureRow(
    title: workflow.title,
    subtitle: workflow.subtitle,
    isExpanded: isExpanded,
    onToggle: toggleExpansion
) {
    ForEach(workflow.steps) { step in
        AnvilListRow(title: step.title, subtitle: step.subtitle)
    }
}
```

### Superseded Naming

This ADR amends the design-system package layout and supersedes the design-system package names in ADR-0006:

- `HephaestusTheme` becomes `AnvilTheme`.
- `HephaestusUI` becomes `AnvilUI`.

ADR-0006 still governs the broader package-boundary and cross-package deep-link direction.

---

## Validation

- `swift test` should continue to pass after adding package scaffolds.
- The macOS app should build after importing `AnvilTheme` or `AnvilUI`.
- New packages should not introduce dependencies from `Anvil` to theme/UI code.
- `AnvilUI` should not import Hephaestus feature or domain packages.

---

## References

- [ADR-0006: Package Boundaries And Cross-Package Deep Links](0006-package-boundaries-and-cross-package-deep-links.md)
- [Modularization Objectives](../modularization-objectives.md)
- [Product UI Vision](../product-ui-vision.md)
