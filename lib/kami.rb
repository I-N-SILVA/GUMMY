# frozen_string_literal: true

require "yaml"

# Platform manifest for the Kami fork. Everything that distinguishes this platform from
# stock Gumroad — brand identity, locale policy, default currency, and which regional
# modules are active — is declared in config/kami.yml and read through this module.
# Must stay loadable without Rails: it is required from config/application.rb before the
# framework finishes booting.
module Kami
  CONFIG_PATH = File.expand_path("../config/kami.yml", __dir__)

  class << self
    def brand_name
      config.dig("brand", "name")
    end

    def brand_tagline
      config.dig("brand", "tagline")
    end

    # ENV["DEFAULT_LOCALE"] takes precedence so existing deployments keep working.
    def default_locale
      ENV.fetch("DEFAULT_LOCALE", config.dig("locales", "default")).to_sym
    end

    def available_locales
      config.dig("locales", "available").map(&:to_sym)
    end

    # Maps a BCP 47 language tag (e.g. "pt-br", "en-US") to a supported locale symbol,
    # or nil when the platform doesn't ship that language.
    def normalize_locale(tag)
      language = tag.to_s.strip.split("-").first.to_s.downcase
      return nil if language.empty?

      candidate = (locale_aliases[language] || language).to_sym
      available_locales.include?(candidate) ? candidate : nil
    end

    # ENV["DEFAULT_CURRENCY"] takes precedence so existing deployments keep working.
    def default_currency
      ENV.fetch("DEFAULT_CURRENCY", config.dig("currency", "default")).upcase
    end

    # Platform-level switch for a regional module (see config/kami.yml). This is about
    # what the platform ships, not per-user rollout — runtime rollout stays on Feature
    # flags. ENV["KAMI_MODULE_<NAME>"] overrides the manifest for a single deployment.
    def module_enabled?(name)
      override = ENV["KAMI_MODULE_#{name.to_s.upcase}"]
      return override.casecmp?("true") unless override.nil?

      config.dig("modules", name.to_s) == true
    end

    def reload!
      @config = nil
    end

    private
      def config
        @config ||= YAML.safe_load_file(CONFIG_PATH)
      end

      def locale_aliases
        config.dig("locales", "aliases") || {}
      end
  end
end
