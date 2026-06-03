# frozen_string_literal: true

# Validates Brazilian taxpayer identifiers locally using their official check-digit
# algorithms: CPF (11 digits, individuals) and CNPJ (14 digits, companies).
# Punctuation (dots, slash, hyphen) is ignored, so both "111.444.777-35" and
# "11144477735" are accepted.
class CpfCnpjValidationService
  CPF_LENGTH = 11
  CNPJ_LENGTH = 14

  CNPJ_FIRST_CHECK_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze
  CNPJ_SECOND_CHECK_WEIGHTS = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2].freeze

  attr_reader :tax_id

  def initialize(tax_id)
    @tax_id = tax_id
  end

  def process
    digits = tax_id.to_s.gsub(/\D/, "")

    case digits.length
    when CPF_LENGTH then valid_cpf?(digits)
    when CNPJ_LENGTH then valid_cnpj?(digits)
    else false
    end
  end

  private
    def valid_cpf?(digits)
      return false if all_same_digit?(digits)

      check_digit(digits, 9, 10.downto(2).to_a) == digits[9].to_i &&
        check_digit(digits, 10, 11.downto(2).to_a) == digits[10].to_i
    end

    def valid_cnpj?(digits)
      return false if all_same_digit?(digits)

      check_digit(digits, 12, CNPJ_FIRST_CHECK_WEIGHTS) == digits[12].to_i &&
        check_digit(digits, 13, CNPJ_SECOND_CHECK_WEIGHTS) == digits[13].to_i
    end

    def check_digit(digits, length, weights)
      sum = (0...length).sum { |index| digits[index].to_i * weights[index] }
      remainder = sum % 11
      remainder < 2 ? 0 : 11 - remainder
    end

    def all_same_digit?(digits)
      digits.chars.uniq.size == 1
    end
end
