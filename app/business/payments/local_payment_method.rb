# frozen_string_literal: true

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
