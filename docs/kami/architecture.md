# Kami platform architecture

Kami is a fork of Gumroad being adapted into a Brazil-first commerce platform. This
document describes how the fork is layered on top of upstream, what the platform
manifest is, and the roadmap for making the codebase fully modular.

## Current state

The fork adds four regional capability areas on top of stock Gumroad:

| Area | Code | Docs |
| --- | --- | --- |
| Pix payments | `app/business/payments/charging/implementations/stripe/stripe_chargeable_pix.rb`, `stripe_charge_intent.rb`, `app/javascript/components/Checkout/PixPayment.tsx` | `docs/brazil/pix-integration.md` |
| CPF/CNPJ tax IDs | `app/services/cpf_cnpj_validation_service.rb`, `app/javascript/components/Checkout/CpfCnpjInput.tsx`, `app/javascript/utils/taxId.ts` | — |
| BRL settlement | `app/models/purchase_settlement.rb`, `MerchantAccount#settlement_currency`, `app/models/brazilian_bank_account.rb` | `docs/brazil/multi-currency-settlement.md` |
| Localization & identity | `app/controllers/concerns/locale_selection.rb`, `app/javascript/i18n/`, `config/locales/pt-BR.yml`, premium theme tokens in `tailwind.css` / `_definitions.scss` | `docs/brazil/visual-identity.md` |

Everything integrates through seams upstream already provides — the chargeable
abstraction for Pix, the `BankAccount` STI hierarchy for Brazilian payouts, the
`RegionalVatIdValidationService` dispatch for CPF/CNPJ, design tokens for the theme —
so upstream merges stay cheap. Keep it that way: prefer new classes plugged into
existing dispatch points over edits to upstream classes.

## The platform manifest

`config/kami.yml` declares what makes this deployment Kami rather than stock Gumroad:

- **brand** — name and tagline, the seed for de-Gumroading user-facing copy.
- **locales** — default, available list, and language aliases (`pt` → `pt-BR`).
- **currency** — default display currency (`DEFAULT_CURRENCY` env still wins).
- **modules** — which regional capabilities the platform ships.

`lib/kami.rb` (`Kami`) is the single reader for the manifest. It is deliberately
Rails-independent because `config/application.rb` requires it during boot to set
`i18n` defaults. `app/javascript/kami/config.ts` mirrors the manifest for the
frontend; keep the two in sync when editing either.

### Modules vs. feature flags

These are two different axes and both gates apply:

- `Kami.module_enabled?(:brl_settlement)` — does this **platform** ship the
  capability at all? Static per deployment, overridable per environment via
  `KAMI_MODULE_<NAME>` env vars. A future non-Brazil vertical would turn Pix off
  here.
- `Feature.active?(:brl_settlement, user)` — is the capability **rolled out** to
  this seller? Runtime, per-user, managed with Flipper.

`MerchantAccount#settlement_currency` is the reference implementation of the
double gate.

## Modularization roadmap

Phase 1 (this branch) centralizes platform configuration. The remaining phases, in
order of leverage:

1. **Brand extraction.** User-facing "Gumroad" strings live in mailers, page titles,
   and legal copy. Move them behind `Kami.brand_name` / i18n keys incrementally,
   one surface at a time (receipts first — highest visibility). Do not bulk-rename:
   many specs assert copy, and upstream merges would conflict everywhere.
2. **Namespace the regional domain.** New Brazil-specific services and models go
   under `Kami::` namespaces (e.g. `app/services/kami/`). Existing classes stay put
   until there's a mechanical win — `BrazilianBankAccount` is STI (`type` column
   stores the class name), so renaming it requires a data migration; leave it.
3. **Boundary enforcement.** Once the regional code is namespaced, add
   [packwerk](https://github.com/Shopify/packwerk) with two packages (core,
   brazil) and let CI flag new cross-boundary references. Only after the graph is
   clean is extracting a Rails engine worth considering — an engine before the
   boundaries exist just moves the spaghetti.
4. **Generated frontend manifest.** Replace the hand-mirrored
   `app/javascript/kami/config.ts` with a build step that generates it from
   `config/kami.yml`, removing the sync burden.

## Working agreements for fork code

- New regional capability = new entry in the `modules` map of `config/kami.yml`,
  gated at its entry point with `Kami.module_enabled?`.
- Never widen the diff against upstream inside a shared class when a new class at
  an existing dispatch point works.
- Schema changes follow the side-table pattern (`purchase_settlements`): the
  `users` and `purchases` tables cannot take new columns.
- Every capability area gets a doc under `docs/brazil/` (or `docs/kami/` for
  platform-level concerns) explaining the design, not just the code.
