import * as React from "react";
import { useTranslation } from "react-i18next";

import { Button } from "$app/components/Button";
import { CopyToClipboard } from "$app/components/CopyToClipboard";
import { LoadingSpinner } from "$app/components/LoadingSpinner";
import { Alert } from "$app/components/ui/Alert";

export type PixPaymentProps = {
  qrCode: string;
  qrCodeImageUrl: string;
  expiresAt: Date | null;
  status: "awaiting" | "confirmed";
};

const formatCountdown = (secondsRemaining: number) => {
  const minutes = Math.floor(secondsRemaining / 60);
  const seconds = secondsRemaining % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
};

const useSecondsRemaining = (expiresAt: Date | null) => {
  const computeRemaining = React.useCallback(
    () => (expiresAt ? Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000)) : null),
    [expiresAt],
  );
  const [secondsRemaining, setSecondsRemaining] = React.useState(computeRemaining);

  React.useEffect(() => {
    setSecondsRemaining(computeRemaining());
    if (!expiresAt) return;

    const interval = setInterval(() => setSecondsRemaining(computeRemaining()), 1000);
    return () => clearInterval(interval);
  }, [expiresAt, computeRemaining]);

  return secondsRemaining;
};

export const PixPayment = ({ qrCode, qrCodeImageUrl, expiresAt, status }: PixPaymentProps) => {
  const { t } = useTranslation();
  const secondsRemaining = useSecondsRemaining(expiresAt);
  const expired = secondsRemaining === 0;

  if (status === "confirmed")
    return (
      <Alert variant="success" role="status">
        {t("checkout.paymentConfirmed")}
      </Alert>
    );

  if (expired)
    return (
      <Alert variant="warning" role="status">
        {t("checkout.pixExpired")}
      </Alert>
    );

  return (
    <div className="flex flex-col items-center gap-4 text-center">
      <p>{t("checkout.pixInstructions")}</p>
      <img src={qrCodeImageUrl} alt={t("checkout.payWithPix")} className="size-48" />
      <CopyToClipboard text={qrCode} copyTooltip={t("checkout.pixCopyCode")} copiedTooltip={t("checkout.pixCodeCopied")}>
        <Button color="primary">{t("checkout.pixCopyCode")}</Button>
      </CopyToClipboard>
      <code className="break-all text-xs">{qrCode}</code>
      <div aria-live="polite" className="flex items-center gap-2">
        <LoadingSpinner />
        <span>
          {t("checkout.awaitingPayment")}
          {secondsRemaining != null ? ` · ${t("checkout.pixExpiresIn", { time: formatCountdown(secondsRemaining) })}` : null}
        </span>
      </div>
    </div>
  );
};
