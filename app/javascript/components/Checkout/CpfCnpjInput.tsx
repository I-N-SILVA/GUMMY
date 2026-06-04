import * as React from "react";
import { useTranslation } from "react-i18next";

import { formatCpfCnpj, stripTaxIdFormatting } from "$app/utils/taxId";

import { Input } from "$app/components/ui/Input";

export type CpfCnpjInputProps = {
  value: string;
  onChange: (digits: string) => void;
  id?: string;
};

// Renders the formatted CPF/CNPJ to the buyer while keeping the parent's state as raw digits.
export const CpfCnpjInput = ({ value, onChange, id }: CpfCnpjInputProps) => {
  const { t } = useTranslation();

  return (
    <Input
      id={id}
      type="text"
      inputMode="numeric"
      autoComplete="off"
      placeholder={t("checkout.taxId")}
      aria-label={t("checkout.taxId")}
      value={formatCpfCnpj(value)}
      onChange={(event) => onChange(stripTaxIdFormatting(event.target.value))}
    />
  );
};
