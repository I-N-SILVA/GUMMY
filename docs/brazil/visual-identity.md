# Visual identity & premium theme

A refined, vibrant Brazilian identity layered on top of the existing design-token
system. It reuses the token architecture (CSS custom properties consumed by the
Tailwind `@theme` in `app/javascript/stylesheets/tailwind.css`) so the `ui/`
components inherit it automatically.

## Brand color

`--accent` is the single variable that drives every accent in the app. It is now a
premium emerald, set in `app/javascript/stylesheets/_definitions.scss` after the
`$base-colors` loop so it overrides the original pink without touching the semantic
state colors (success / danger / warning / info). Contrast is set to white.

| Token | Value | Use |
| --- | --- | --- |
| `--accent` / `bg-accent` | emerald `rgb(0 168 107)` | primary brand accent |
| `--brand-emerald` / `bg-brand-emerald` | `rgb(0 168 107)` | gradients, charts |
| `--brand-gold` / `bg-brand-gold` | `rgb(255 180 0)` | gradients, highlights |
| `--brand-azure` / `bg-brand-azure` | `rgb(30 115 255)` | gradients, links |

Because contrasts are auto-computed in `_colors.scss`, the rest of the system adapts
to the new accent automatically, in both light and dark mode.

## Premium tokens (Tailwind utilities)

Defined in `@theme` in `tailwind.css`, so they generate first-class utilities:

- **Easing:** `ease-premium` (Apple-style deceleration `cubic-bezier(0.32, 0.72, 0, 1)`)
  and `ease-spring` for playful overshoot.
- **Elevation:** `shadow-premium` — a soft, layered three-stop shadow.
- **Fluid type:** `text-fluid-sm | base | lg | xl | 2xl`, each a `clamp()` that scales
  smoothly with the viewport.

## Surface & background utilities

- `surface-glass` — frosted translucent surface (`backdrop-blur` + saturation) for
  cards and sheets.
- `bg-mesh` — a vibrant four-point radial mesh gradient built from the brand palette.
- `animate-aurora` — slowly drifts a `bg-mesh` background (disabled under
  `prefers-reduced-motion`).
- `bg-grain` — a subtle SVG film-grain overlay (via `::after`) for richness; apply to a
  positioned container.

## Example

`PixPayment` (`app/javascript/components/Checkout/PixPayment.tsx`) demonstrates the
language: a `surface-glass shadow-premium bg-grain rounded-2xl` card, a `text-fluid-lg`
heading, and a QR image that scales on hover with `ease-premium`.

A typical premium page shell:

```tsx
<div className="bg-mesh animate-aurora min-h-screen">
  <section className="surface-glass shadow-premium rounded-2xl p-8">
    <h1 className="text-fluid-2xl font-semibold">…</h1>
  </section>
</div>
```

## Principles

- Animate only `transform` / `opacity` for 60fps; never layout properties.
- Always provide a `prefers-reduced-motion` path.
- Keep the accent semantic: state colors stay distinct from the brand emerald.
