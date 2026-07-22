import type { MouseEvent, ReactNode } from "react";
import { Button } from "./Button";
import { Card } from "./Card";
import "./ConfirmModal.css";

interface ConfirmModalProps {
  title: string;
  message: ReactNode;
  callout?: ReactNode;
  confirmLabel: string;
  busy?: boolean;
  busyLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

/** Generic destructive-action confirmation dialog — new addition, not in the
 * original WPF app (which had no apply/undo UI, dry-run only). Used by both
 * the Apply and Undo flows per §8.5's "requires an explicit second
 * confirmation modal before firing" decision. */
export function ConfirmModal({
  title,
  message,
  callout,
  confirmLabel,
  busy,
  busyLabel,
  onConfirm,
  onCancel,
}: ConfirmModalProps) {
  return (
    <div className="modalOverlay" onClick={onCancel}>
      <Card
        className="modalCard"
        onClick={(e: MouseEvent) => e.stopPropagation()}
      >
        <h3 className="modalTitle">{title}</h3>
        <div className="modalMessage">{message}</div>
        {callout && <div className="modalCallout">{callout}</div>}
        <div className="modalActions">
          <Button onClick={onCancel} disabled={busy}>
            Cancel
          </Button>
          <Button variant="danger" onClick={onConfirm} disabled={busy}>
            {busy ? (busyLabel ?? "Working…") : confirmLabel}
          </Button>
        </div>
      </Card>
    </div>
  );
}
