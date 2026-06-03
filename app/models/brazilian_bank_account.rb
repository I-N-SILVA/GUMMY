# frozen_string_literal: true

class BrazilianBankAccount < BankAccount
  include BrazilianBankAccount::AccountType

  BANK_ACCOUNT_TYPE = "BR"

  # Código do banco (e.g. 001 Banco do Brasil, 237 Bradesco, 341 Itaú, 104 Caixa).
  BANK_CODE_FORMAT_REGEX = /\A[0-9]{3}\z/
  private_constant :BANK_CODE_FORMAT_REGEX

  # Agência. Usually four digits, occasionally with a check digit.
  BRANCH_CODE_FORMAT_REGEX = /\A[0-9]{4,5}\z/
  private_constant :BRANCH_CODE_FORMAT_REGEX

  # Conta with its check digit, digits only (any hyphen is stripped before saving).
  ACCOUNT_NUMBER_FORMAT_REGEX = /\A[0-9]{4,13}\z/
  private_constant :ACCOUNT_NUMBER_FORMAT_REGEX

  alias_attribute :bank_code, :bank_number

  before_validation :set_default_account_type, on: :create, if: ->(bank_account) { bank_account.account_type.nil? }

  validate :validate_bank_code
  validate :validate_branch_code
  validate :validate_account_number
  validates :account_type, inclusion: { in: AccountType.all }

  def routing_number
    "#{bank_code}-#{branch_code}"
  end

  def bank_account_type
    BANK_ACCOUNT_TYPE
  end

  def country
    Compliance::Countries::BRA.alpha2
  end

  def currency
    Currency::BRL
  end

  def account_number_visual
    "******#{account_number_last_four}"
  end

  def to_hash
    {
      routing_number:,
      account_number: account_number_visual,
      bank_account_type:
    }
  end

  private
    def validate_bank_code
      return if BANK_CODE_FORMAT_REGEX.match?(bank_code)
      errors.add :base, "The bank code is invalid."
    end

    def validate_branch_code
      return if BRANCH_CODE_FORMAT_REGEX.match?(branch_code)
      errors.add :base, "The branch code is invalid."
    end

    def validate_account_number
      return if ACCOUNT_NUMBER_FORMAT_REGEX.match?(account_number_decrypted)
      errors.add :base, "The account number is invalid."
    end

    def set_default_account_type
      self.account_type = BrazilianBankAccount::AccountType::CHECKING
    end
end
