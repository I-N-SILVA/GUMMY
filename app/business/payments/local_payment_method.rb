# frozen_string_literal: true

# The catalog of local payment methods: bank-transfer and voucher methods tied to one market, as
# opposed to cards, which work everywhere.
#
# Adding a method should be one entry in the catalog at the bottom of this file plus its chargeable
# class, rather than another branch in the charge processor and another country test somewhere else.
# A definition carries everything the rest of the platform needs: which chargeable builds the charge,
# which countries offer it, which currency it settles in, whether it confirms asynchronously, and an
# optional flag to gate its rollout independently of the market's.
class LocalPaymentMethod
  REGISTRY = {}
  private_constant :REGISTRY

  attr_reader :id, :countries, :settlement_currency, :feature_flag

  def self.register(id, chargeable:, countries:, settlement_currency:, asynchronous: false, feature_flag: nil)
    REGISTRY[id.to_sym] = new(id: id.to_sym, chargeable:, countries:, settlement_currency:, asynchronous:, feature_flag:)
  end

  def self.all
    REGISTRY.values
  end

  def self.[](id)
    REGISTRY[id.to_sym]
  end

  # Checkout names the chosen method with a truthy param under its id, e.g. `pix: true`.
  def self.from_params(params)
    all.find { params[_1.id].present? }
  end

  def self.available_for(merchant_account)
    all.select { _1.available_for?(merchant_account) }
  end

  def initialize(id:, chargeable:, countries:, settlement_currency:, asynchronous:, feature_flag:)
    @id = id
    @chargeable_class_name = chargeable
    @countries = countries.freeze
    @settlement_currency = settlement_currency
    @asynchronous = asynchronous
    @feature_flag = feature_flag
  end

  def asynchronous?
    @asynchronous
  end

  def build_chargeable(**)
    @chargeable_class_name.constantize.new(**)
  end

  # Offerable only when the account sits in one of the method's countries and already settles in the
  # currency the method requires. The currency check is the one that matters: Stripe rejects a Pix
  # intent that is not in BRL, so offering Pix on a USD-settling account would fail at the processor.
  # Deriving it from the account's settlement currency means a market cannot be half-opened — the
  # method appears only once its market's settlement flag is actually on for that seller.
  def available_for?(merchant_account)
    return false unless countries.include?(merchant_account.country)
    return false unless merchant_account.settlement_currency == settlement_currency
    return false if feature_flag.present? && !Feature.active?(feature_flag, merchant_account.user)

    true
  end
end

LocalPaymentMethod.register :pix,
                            chargeable: "StripeChargeablePix",
                            countries: [Compliance::Countries::BRA.alpha2],
                            settlement_currency: Currency::BRL,
                            asynchronous: true
