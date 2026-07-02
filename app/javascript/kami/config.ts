// Frontend mirror of config/kami.yml — the platform manifest for the Kami fork.
// Keep the two files in sync when changing brand, locales, or modules.

export const KAMI_BRAND = {
  name: "Kami",
  tagline: "The creator economy, made for Brazil",
} as const;

export const DEFAULT_LOCALE = "en";
export const SUPPORTED_LOCALES = ["en", "pt-BR"] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

const LOCALE_ALIASES: Record<string, SupportedLocale> = { pt: "pt-BR" };

export function normalizeLocale(locale: string | undefined): SupportedLocale {
  if (!locale) return DEFAULT_LOCALE;
  const language = locale.trim().split("-")[0]?.toLowerCase() ?? "";
  const candidate = LOCALE_ALIASES[language] ?? language;
  return SUPPORTED_LOCALES.find((supported) => supported === candidate) ?? DEFAULT_LOCALE;
}
