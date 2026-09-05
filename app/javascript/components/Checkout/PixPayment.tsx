import * as React from "react";
import { useTranslation } from "react-i18next";

import { getPixPaymentState, PixPaymentState } from "$app/data/purchase";
import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { CopyToClipboard } from "$app/components/CopyToClipboard";
import { LoadingSpinner } from "$app/components/LoadingSpinner";
import { Alert } from "$app/components/ui/Alert";

const POLL_INTERVAL_MS = 3000;

export type PixPaymentProps = {
  qrCode: string;
  qrCodeImageUrl: string;
  expiresAt: Date | null;
  purchaseStatusId: string;
  onConfirmed?: () => void;
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

const usePixPaymentState = (purchaseStatusId: string, polling: boolean) => {
  const [state, setState] = React.useState<PixPaymentState>("in_progress");

  React.useEffect(() => {
    if (!polling) return;
    let cancelled = false;

    const poll = async () => {
      try {
        const nextState = await getPixPaymentState(purchaseStatusId);
        if (!cancelled) setState(nextState);
      } catch (error) {
        assertResponseError(error);
      }
    };

    void poll();
    const interval = setInterval(() => void poll(), POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [purchaseStatusId, polling]);

  return state;
};

export const PixPayment = ({ qrCode, qrCodeImageUrl, expiresAt, purchaseStatusId, onConfirmed }: PixPaymentProps) => {
  const { t } = useTranslation();
  const secondsRemaining = useSecondsRemaining(expiresAt);
  const expired = secondsRemaining === 0;
  const state = usePixPaymentState(purchaseStatusId, !expired);

  React.useEffect(() => {
    if (state === "successful") onConfirmed?.();
  }, [state]);

  if (state === "successful")
    return (
      <Alert variant="success" role="status">
        {t("checkout.paymentConfirmed")}
      </Alert>
    );

  if (state === "failed")
    return (
      <Alert variant="danger" role="status">
        {t("checkout.pixFailed")}
      </Alert>
    );

  if (expired)
    return (
      <Alert variant="warning" role="status">
        {t("checkout.pixExpired")}
      </Alert>
    );

  return (
    <div className="bg-grain flex flex-col items-center gap-4 rounded-2xl surface-glass p-8 text-center shadow-premium">
      <p className="text-fluid-lg font-medium">{t("checkout.pixInstructions")}</p>
      <img
        src={qrCodeImageUrl}
        alt={t("checkout.payWithPix")}
        className="size-48 rounded-2xl ring-1 ring-border transition-transform duration-500 ease-premium hover:scale-105"
      />
      <CopyToClipboard
        text={qrCode}
        copyTooltip={t("checkout.pixCopyCode")}
        copiedTooltip={t("checkout.pixCodeCopied")}
      >
        <Button color="primary">{t("checkout.pixCopyCode")}</Button>
      </CopyToClipboard>
      <code className="text-xs break-all">{qrCode}</code>
      <div aria-live="polite" className="flex items-center gap-2">
        <LoadingSpinner />
        <span>
          {t("checkout.awaitingPayment")}
          {secondsRemaining != null
            ? ` · ${t("checkout.pixExpiresIn", { time: formatCountdown(secondsRemaining) })}`
            : null}
        </span>
      </div>
    </div>
  );
};
