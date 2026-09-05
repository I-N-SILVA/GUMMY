# Multi-currency settlement (BRL / Pix) — design

Status: design only. No money-pipeline code is changed by this document. It exists so the
settlement change — the actual blocker for "fully functional in Brazil" — can be implemented
and reviewed as a properly tested, standalone PR in an environment with MySQL, Mongo, and
Stripe test credentials (this repository's web/CI environment), per CONTRIBUTING.md's rule
that money-pipeline changes ship with fail-on-revert specs and Stripe-backed VCR cassettes.

## The actual gap

Brazil is already supported on the **seller** side:

- BRL is a first-class currency (`config/currencies.json`; `Currency::BRL`). It can be a product
  price currency, an account default currency, and a payout currency.
- Brazil is in `StripeMerchantAccountManager::COUNTRIES_SUPPORTED_BY_STRIPE_CONNECT`.
- `Country#can_accept_stripe_charges?` is true for Brazil — it is **not** in
  `CROSS_BORDER_PAYOUTS_COUNTRIES` (`app/models/country.rb:6`), so Brazilian sellers get full
  local Connect accounts that settle in BRL. `MerchantAccount#is_a_brazilian_stripe_connect_account?`
  already exists.

What is missing is **settling a charge in a currency other than USD**. Today the platform
displays prices in many currencies but charges and records every sale in USD:

- `Purchase` stores `displayed_price_currency_type` (what the buyer sees) and a
  `rate_converted_to_usd`, but the settled amounts (`price_cents`, `fee_cents`,
  `processor_fee_cents` / `processor_fee_cents_currency` default `"usd"`) are USD.
- `StripeChargeProcessor#create_payment_intent_or_charge!`
  (`app/business/payments/charging/implementations/stripe/stripe_charge_processor.rb:219`)
  hardcodes `currency: "usd"`. The application-fee transfer and platform transfers
  (~lines 501, 527, 536) are USD too.

Stripe Pix settles **only in `brl`**. So Pix cannot work until a charge can be created,
recorded, refunded, and paid out in BRL. That is the general multi-currency settlement problem;
Pix is its first consumer.

## Hard constraint that shapes everything

CLAUDE.md: **do not add, remove, or rename columns on `purchases`** (the table is too large;
migrations block deploys). There is no `settlement_currency` / `settlement_amount_cents` column
and we cannot add one. Therefore the settled-currency amounts must live in a **side table**
keyed by purchase, not in new `purchases` columns.

## Design

### 1. Settlement currency is a property of the merchant account, not the charge call

Add `MerchantAccount#settlement_currency`, derived from the account's country via
`Country#payout_currency` (BRL for Brazil, USD for the existing default account). This keeps the
decision in one place and avoids threading a currency argument through every caller.

`create_payment_intent_or_charge!` replaces the hardcoded `currency: "usd"` with
`currency: merchant_account.settlement_currency`. The default Gumroad-managed account returns
`"usd"`, so every existing path is byte-for-byte unchanged; only Brazilian local accounts diverge.
The chargeable can still override per payment method (e.g. `StripeChargeablePix#stripe_charge_params`
already returns `payment_method_types: ["pix"]`); currency stays an account property so card and
Pix on the same Brazilian account agree.

### 2. Amount conversion happens at charge construction, once

`amount_cents` reaching the processor is USD-derived today. For a non-USD settlement account,
convert the order total to the settlement currency at charge time using the existing currency
helpers (`CurrencyHelper` / `Money`) and pass the settlement-currency amount to Stripe. Record the
rate used so the settlement amount is reproducible (see side table below). Do the conversion in
exactly one place — the order/charge construction — never in the frontend (CLAUDE.md: business
logic in Rails).

### 3. Record settled amounts in a side table

New table `purchase_settlements` (Nano-ID external id, no FK constraint per CLAUDE.md):

- `purchase_id` (indexed)
- `settlement_currency` (e.g. `"brl"`)
- `settlement_amount_cents`
- `settlement_fee_cents`
- `rate_used` (settlement-per-USD, copied at purchase time so historical records stay accurate —
  CLAUDE.md's "copy values at time of purchase" rule)

USD-settled purchases create no row (absence == legacy USD behavior), so the table starts empty
and backfill is unnecessary. Reads go through `Purchase#settlement` with a USD fallback.

### 4. Fees, transfers, refunds, disputes

- Application fee / transfers (`stripe_charge_processor.rb` ~501–536) must use the same settlement
  currency as the charge, not `"usd"`. Audit each `currency:` literal in that file.
- Refunds (`StripeChargeProcessor` refund path) must refund in the charge's currency — Stripe
  enforces this; pull the currency from the charge, not a constant.
- Disputes/chargebacks already read `stripe_dispute.currency` in several places (good); verify the
  reversal/withdrawal math (`FlowOfFunds`) is currency-aware for BRL.

### 5. Payouts

Brazilian Connect accounts already settle and pay out in BRL via the existing native-payout path
(`StripeMerchantAccountManager`, `BrazilianBankAccount`). Once charges settle in BRL the balance is
already BRL, so payouts need no new currency logic — but verify
`min_cross_border_payout_amount_*` and balance reporting handle a BRL local balance.

### 6. Tax

Brazilian indirect tax (and nota fiscal obligations) are out of scope for settlement and tracked
separately. CPF/CNPJ collection (`CpfCnpjValidationService`, `RegionalVatIdValidationService`) is
already on this branch; wiring it into checkout is independent of settlement currency.

## Rollout

- Gate behind a feature flag (e.g. `Feature.active?(:brl_settlement, seller)`), defaulting off.
- Phase 1 — **implemented (specs pending CI)**: settlement plumbing + side table, flag off, no
  behavior change.
  - `purchase_settlements` table + `PurchaseSettlement` model (no FK; internal record, no external
    id; one row per non-USD purchase, absence == USD).
  - `MerchantAccount#settlement_currency` returns `brl` for a Brazilian Stripe Connect account when
    `brl_settlement` is active for the seller, `usd` otherwise. With the flag off it is always
    `usd`, so nothing changes yet.
  - Specs: `spec/models/purchase_settlement_spec.rb` and the `#settlement_currency` block in
    `spec/models/merchant_account_spec.rb`. These need a DB and so run in CI, not in this container.
- Phase 2 — **implemented (specs pending a DB + Stripe environment)**: the charge path now settles in
  the merchant account's currency.
  - `SettlementConversion` (`app/business/payments/settlement_conversion.rb`) converts USD cents into
    the settlement currency. It looks the rate up once per instance and reuses it, so the charge
    amount, the application fee, and the destination transfer of one charge cannot disagree because
    the rate moved between lookups. USD skips the lookup entirely, so the existing USD path gains no
    Redis or exchange-rate HTTP dependency.
  - `StripeChargeProcessor#create_payment_intent_or_charge!` replaces `currency: "usd"` and the raw
    `amount` / `application_fee_amount` / `transfer_data[:amount]` with converted values. With
    `brl_settlement` off, `settlement_currency` is `usd` and `convert` is the identity, so the params
    are unchanged for every existing seller.
  - The `SettlementConversion` is carried on the returned `ChargeIntent#settlement` rather than
    recomputed by callers, so the row recorded against the purchase uses the rate the charge was
    actually created with.
  - `PurchaseSettlement.record_for` writes the row, from `Purchase#create_charge_intent` (single
    charge) and `Charge::CreateService` (combined charge). Each purchase records its own converted
    share, not the charge total, so a combined charge yields per-purchase rows. USD settlement writes
    nothing — absence still means USD.
  - Specs: `spec/business/payments/settlement_conversion_spec.rb`, the `.record_for` block in
    `spec/models/purchase_settlement_spec.rb`, and the "settlement currency" block in
    `spec/business/payments/charging/implementations/stripe/stripe_charge_processor_spec.rb`.

### Must be closed before `brl_settlement` is enabled for any seller

**Partial refunds — resolved.** `StripeChargeProcessor#refund!` receives `amount_cents` in USD, but
Stripe refunds in the charge's own currency, so a partial refund of a BRL charge would have refunded
the wrong amount. Converting at today's rate would also be wrong: a refund has to use the rate the
charge settled at, or a customer refunded a month later gets back a different amount than they paid.
`refund!` only receives a `charge_id`, so the rate is looked up with
`PurchaseSettlement.conversion_rate_for_processor_charge`, which resolves the charge through the
indexed `purchases.stripe_transaction_id` and falls back to `Charge#processor_transaction_id` for
combined charges. A non-USD charge with no recorded rate raises rather than guessing. Full refunds
are unaffected: they send no amount and Stripe refunds the charge in full.

**Fees and transfers outside the charge path.** The `currency: "usd"` literals around
`stripe_charge_processor.rb` lines 500–540 are the backtax-collection transfers, a separate flow from
charge settlement, and are untouched here. They need auditing against a BRL local balance before a
Brazilian seller goes live.

- Phase 2b: enable for a pilot Brazilian seller and confirm a real BRL charge, refund, and payout in
  Stripe test mode.
- Phase 3: Pix payment method on top (the chargeable exists; add the async purchase state and
  webhook handling from `docs/brazil/pix-integration.md` items 1, 3, 4, 5).

## Testing (must run in a DB + Stripe environment)

- Fail-on-revert specs: a Brazilian-account charge produces a `brl` PaymentIntent and a
  `purchase_settlements` row; the default account is unchanged at `usd`.
- VCR cassettes scoped per file, regenerated against Stripe test mode with Pix + BRL enabled — no
  stubbing (CONTRIBUTING.md).
- `processing -> succeeded` Pix webhook marks the purchase paid; expiry cancels it.

## Why this is not implemented here

This container has no MySQL/Mongo and no Stripe credentials, so the mandatory DB-backed and
Stripe-VCR specs cannot be run or recorded. Writing unverified money-pipeline code would violate
CONTRIBUTING.md's verification bar. The standalone PR should be implemented where `bin/rspec` and
VCR recording work.
