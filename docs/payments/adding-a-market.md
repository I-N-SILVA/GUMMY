# Adding a market or a local payment method

Brazil was the first market to need something other than USD settlement and something other than a
card. Rather than leave that as a pile of Brazil-specific branches, the two decisions live in data:

| Decision | Where it lives |
| --- | --- |
| Which currency a country's local accounts settle in | `SettlementCurrencyPolicy::MARKETS` |
| Which local payment methods exist and where they're offered | the catalog at the bottom of `LocalPaymentMethod` |

Everything downstream — the charge processor, `PurchaseSettlement`, checkout — reads the answer from
those two, so opening a market does not mean editing the money pipeline.

## Opening a new market

A "market" is a country whose local Stripe Connect accounts settle in their own currency instead of
USD. Add one entry:

```ruby
# app/business/payments/settlement_currency_policy.rb
MARKETS = {
  Compliance::Countries::BRA.alpha2 => Market.new(currency: Currency::BRL, feature_flag: :brl_settlement),
  Compliance::Countries::POL.alpha2 => Market.new(currency: Currency::PLN, feature_flag: :pln_settlement)
}.freeze
```

That is the whole change. `MerchantAccount#settlement_currency` starts returning the new currency for
sellers in that country once the flag is on for them, `StripeChargeProcessor` charges in it,
converting the amount, application fee, and destination transfer at one rate, and
`PurchaseSettlement` records what each purchase settled for.

Requirements before adding an entry:

- The country must take **local** Stripe Connect accounts, not cross-border payouts — i.e. it is
  absent from `Country::CROSS_BORDER_PAYOUTS_COUNTRIES` and `Country#can_accept_stripe_charges?` is
  true for it. A cross-border country has no local balance to settle into.
- The currency must be a first-class currency — one of the nineteen in `config/currencies.json`
  (`aud cad chf czk eur gbp hkd ils inr jpy krw nzd php pln sgd twd usd zar` plus `brl`), which is
  what makes `Currency::<CODE>` exist *and* gives the conversion helpers a rate for it. The long tail
  of codes declared at the bottom of `Currency` are payout-only: the constant exists, but
  `usd_cents_to_currency` has no rate and the conversion silently misbehaves. `Currency::MXN` is one
  of these, so Mexico cannot be a market without first promoting MXN.
- The flag starts off. Enable it per seller (`Feature.activate_user`) for a pilot before going wide.

## Adding a local payment method

Register it in the catalog with the chargeable that builds its charge:

```ruby
LocalPaymentMethod.register :blik,
                            chargeable: "StripeChargeableBlik",
                            countries: [Compliance::Countries::POL.alpha2],
                            settlement_currency: Currency::PLN,
                            asynchronous: true
```

The chargeable follows `StripeChargeablePix`: it returns the processor's payment-method params from
`stripe_charge_params`, returns `nil` from `reusable_token!` if the method cannot be saved for
off-session reuse, and leaves the card-specific fields nil.

`settlement_currency` is not decoration. `#available_for?` will only offer the method on an account
that **already settles** in that currency, because Stripe rejects a Pix intent that is not in BRL and
a BLIK charge that is not in PLN. That coupling is what stops a market being half-opened: a method
appears only once its market's settlement flag is genuinely on for that seller. A method whose
currency no market settles in can never be offered, and a spec in
`spec/business/payments/local_payment_method_spec.rb` fails if one is registered.

Pass `feature_flag:` to gate a method's rollout separately from its market's — useful when the market
is already live on cards and you want to add the method to a subset of its sellers.

## What `asynchronous:` means

An asynchronous method does not authorize during checkout. Stripe returns a code for the buyer to pay
in their banking app and confirms later by webhook, so the purchase has to hold in an awaiting state
and be confirmed or expired by the webhook rather than succeeding inline. That machinery is still
outstanding — see `docs/brazil/pix-integration.md` items 3, 4, and 5. Until it lands, registering an
asynchronous method makes it buildable but not yet checkout-complete.

## Still market-agnostic work

These are shared blockers, not per-market ones, and are listed in
`docs/brazil/multi-currency-settlement.md`:

- Partial refunds of a non-USD charge currently raise, because the refund has to use the rate the
  charge settled at and `refund!` only receives a charge id.
- The backtax-collection transfers in `StripeChargeProcessor` still assume USD.
