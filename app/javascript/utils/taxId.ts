const onlyDigits = (value: string) => value.replace(/\D/gu, "");

// CPF has 11 digits, CNPJ has 14; never keep more than a CNPJ's worth.
const MAX_TAX_ID_DIGITS = 14;

const applyMask = (digits: string, groups: number[], separators: string[]): string => {
  let result = "";
  let position = 0;
  for (let i = 0; i < groups.length; i++) {
    const part = digits.slice(position, position + (groups[i] ?? 0));
    if (!part) break;
    if (i > 0) result += separators[i - 1];
    result += part;
    position += groups[i] ?? 0;
  }
  return result;
};

// Formats a Brazilian tax ID for display only: CPF as 000.000.000-00 (<= 11 digits) and
// CNPJ as 00.000.000/0000-00 (12-14 digits). The authoritative checksum validation lives in
// CpfCnpjValidationService on the server; this is purely presentational masking.
export const formatCpfCnpj = (value: string): string => {
  const digits = onlyDigits(value).slice(0, MAX_TAX_ID_DIGITS);
  if (digits.length <= 11) return applyMask(digits, [3, 3, 3, 2], [".", ".", "-"]);
  return applyMask(digits, [2, 3, 3, 4, 2], [".", ".", "/", "-"]);
};

// Strips formatting to raw digits, capped at a CNPJ's length so the value emitted to
// parent state stays consistent with what formatCpfCnpj displays.
export const stripTaxIdFormatting = (value: string): string => onlyDigits(value).slice(0, MAX_TAX_ID_DIGITS);
