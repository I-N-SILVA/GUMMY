# Expansion ideas: apps built on the Kami infrastructure

Kami's infrastructure is a full commerce engine: products, checkout, Stripe/PayPal
charging, Pix, payouts (including Brazilian bank accounts), subscriptions,
affiliates, discount codes, email delivery, analytics, search, and a design-token
UI system. The platform manifest (`config/kami.yml` + `lib/kami.rb`) makes the
Brazil-specific parts switchable, which is exactly what turning this into a family
of products requires: each product is a different manifest plus a vertical layer,
not a new codebase.

Distinctiveness rule for every product below: it must own its **audience**, its
**catalog shape** (what a "product" is), and its **brand layer** (accent color,
type scale, tone of voice via i18n). The engine underneath is shared; the surface
never looks shared.

## Product ideas

### 1. Kami Cursos — course platform for Brazilian creators

Hotmart's turf, attacked with lower fees and Pix-native checkout.

- **Reuses:** products with file delivery, subscriptions, Pix, CPF/CNPJ, BRL
  settlement, affiliates (course co-producers are a huge Brazilian pattern).
- **New vertical layer:** module/lesson catalog shape on top of the existing rich
  content model, completion tracking, certificates (the PDF stamping pipeline
  already exists).
- **Manifest:** `modules: { pix: true, courses: true }`, warm gold accent.

### 2. Kami Assinaturas — membership/newsletter platform

A Substack/Apoia.se hybrid: recurring support with posts and community perks.

- **Reuses:** subscriptions, the posts/email engine (installments), audience
  segmentation, Pix recurring via saved payment methods.
- **New vertical layer:** tiers as the primary catalog shape, member-only feed as
  the primary surface (storefront demoted), creator "thank you" flows.
- **Manifest:** `modules: { pix: true, memberships: true }`, azure accent.

### 3. Kami Eventos — ticketing for workshops and live events

Sympla for the creator long tail.

- **Reuses:** checkout, discount codes, the license-key machinery (a ticket is a
  license with a QR render), refund/dispute flows, mobile API.
- **New vertical layer:** event date/venue/capacity as catalog shape, check-in
  scanner page, post-event recording delivery (files infra).
- **Manifest:** `modules: { pix: true, events: true }`.

### 4. Kami Serviços — productized services marketplace

Sell fixed-scope services (design reviews, mentorship hours, edits) like products.

- **Reuses:** checkout, payouts, reviews, the commission/`is_recurring_billing`
  machinery, chat-adjacent email threads.
- **New vertical layer:** booking/delivery state machine (ordered → delivered →
  accepted), calendar integration, escrow-style delayed payout (the balance
  system already supports holds).
- **Manifest:** `modules: { pix: true, services: true, brl_settlement: true }` —
  settlement matters most here because sellers are labor, not media.

### 5. Kami B2B — invoiced digital goods for companies

CNPJ-first checkout: companies buying licenses/training with proper fiscal
paperwork.

- **Reuses:** CPF/CNPJ validation (CNPJ path), invoices (wkhtmltopdf pipeline),
  multi-seat licenses, team accounts.
- **New vertical layer:** NF-e (nota fiscal) issuance integration, quotes and
  purchase orders, boleto as a payment method (new `modules: boleto` entry beside
  Pix — the chargeable abstraction accepts it the same way).

## How a second product actually ships (suggested mechanics)

1. **One repo, many manifests.** Products are deployments differing in
   `config/kami.yml` (or `KAMI_MODULE_*` env), not long-lived forks of the fork.
   A fork-of-a-fork doubles the upstream-merge tax forever; a manifest is one file.
2. **Vertical layers live in modules.** Each product's unique code lands behind a
   `modules:` switch and (per the architecture roadmap) a `Kami::<Vertical>`
   namespace, so disabled verticals are dead weight, not live risk, in other
   deployments.
3. **Brand is data.** Accent and premium tokens are already CSS custom properties
   (`--accent`, `--brand-*`); a product ships a token override file plus its own
   locale strings. No component forks for branding.
4. **Order of attack.** Ship one vertical end-to-end before starting a second.
   Cursos or Assinaturas first — both are ~90% existing engine and validate the
   manifest mechanics cheaply. Eventos and Serviços need new state machines;
   B2B needs external fiscal integrations (NF-e) and is the most work.

## What's needed to make this work (gap list)

- **Payments:** recurring Pix (automatic debit via Pix Automático or hybrid
  card/Pix fallback for subscriptions), boleto module, NF-e issuance partner.
- **Platform:** phases 2–3 of the modularization roadmap (namespacing +
  packwerk), the generated frontend manifest, and a per-deployment domain/brand
  config (extend `config/domain.rb` the way `kami.yml` extends locale/currency).
- **Compliance:** LGPD data-handling review, marketplace payment license
  assessment for the escrow-like flows in Serviços.
- **Operations:** per-product Elasticsearch index prefixes and Sidekiq queue
  isolation if products share infrastructure; separate Stripe accounts per
  product from day one to keep settlement clean.
