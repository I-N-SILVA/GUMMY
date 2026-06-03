# frozen_string_literal: true

module LocaleSelection
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  private
    def switch_locale(&action)
      I18n.with_locale(requested_locale, &action)
    end

    def requested_locale
      locale_from_params || locale_from_header || I18n.default_locale
    end

    def locale_from_params
      locale = params[:locale].presence&.to_sym
      locale if I18n.available_locales.include?(locale)
    end

    def locale_from_header
      return unless request.respond_to?(:env)

      header = request.env["HTTP_ACCEPT_LANGUAGE"].presence
      return unless header

      requested = header.split(",").map { |part| part.split(";").first.to_s.strip }
      requested.map! { |tag| normalize_locale_tag(tag) }
      requested.find { |locale| I18n.available_locales.include?(locale) }
    end

    def normalize_locale_tag(tag)
      return :"pt-BR" if tag.downcase.start_with?("pt")

      tag.split("-").first.to_s.downcase.to_sym
    end
end
