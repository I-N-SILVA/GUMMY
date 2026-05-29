import i18n from "i18next";
import { initReactI18next } from "react-i18next";

import en from "./locales/en.json";
import ptBR from "./locales/pt-BR.json";

export const DEFAULT_LOCALE = "en";
export const SUPPORTED_LOCALES = ["en", "pt-BR"] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

function normalizeLocale(locale: string | undefined): SupportedLocale {
  if (!locale) return DEFAULT_LOCALE;
  if (locale.toLowerCase().startsWith("pt")) return "pt-BR";
  return (SUPPORTED_LOCALES as readonly string[]).includes(locale) ? (locale as SupportedLocale) : DEFAULT_LOCALE;
}

let initialized = false;

export function initI18n(locale?: string) {
  const resolved = normalizeLocale(locale);

  if (!initialized) {
    void i18n.use(initReactI18next).init({
      resources: {
        en: { translation: en },
        "pt-BR": { translation: ptBR },
      },
      lng: resolved,
      fallbackLng: DEFAULT_LOCALE,
      interpolation: { escapeValue: false },
      returnNull: false,
    });
    initialized = true;
  } else if (i18n.language !== resolved) {
    void i18n.changeLanguage(resolved);
  }

  return i18n;
}

export default i18n;
