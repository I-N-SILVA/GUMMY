# frozen_string_literal: true

class SellerProfileLinksSection < SellerProfileSection
  MAX_LINKS = 50
  MAX_TITLE_LENGTH = 100
  MAX_SUBTITLE_LENGTH = 200
  ALLOWED_URL_SCHEMES = %w[http https].freeze

  validate :limit_number_of_links
  validate :validate_titles
  validate :validate_urls

  def links
    json_data["links"] || []
  end

  private
    def limit_number_of_links
      errors.add(:base, "You can add up to #{MAX_LINKS} links") if links.size > MAX_LINKS
    end

    def validate_titles
      errors.add(:base, "Every link needs a title") unless links.all? { _1["title"].to_s.strip.present? }
      errors.add(:base, "Link titles must be #{MAX_TITLE_LENGTH} characters or fewer") if links.any? { _1["title"].to_s.length > MAX_TITLE_LENGTH }
      errors.add(:base, "Link descriptions must be #{MAX_SUBTITLE_LENGTH} characters or fewer") if links.any? { _1["subtitle"].to_s.length > MAX_SUBTITLE_LENGTH }
    end

    def validate_urls
      return if links.all? { valid_link_url?(_1["url"]) }

      errors.add(:base, "Every link needs a valid URL starting with http:// or https://")
    end

    def valid_link_url?(url)
      return false unless /\A#{URI::DEFAULT_PARSER.make_regexp(ALLOWED_URL_SCHEMES)}\z/.match?(url)

      URI.parse(url).host.present?
    rescue URI::InvalidURIError
      false
    end
end
