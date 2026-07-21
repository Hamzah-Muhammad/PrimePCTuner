import { Button } from "../primitives/Button";
import "./ToolbarBar.css";

interface ToolbarBarProps {
  onSelectAll: () => void;
  onSelectNone: () => void;
  onUncheckLevel3: () => void;
  onOpenReport: () => void;
  reportAvailable: boolean;
  statusText: string;
  onRescan: () => void;
  scanning: boolean;
  hasScanned: boolean;
}

/** Ports the bottom DockPanel toolbar (Grid.Row=4) from New-PrimeChecklistApp.
 * No scan runs automatically (user directive) — this button is the only
 * trigger, first scan and every one after. */
export function ToolbarBar({
  onSelectAll,
  onSelectNone,
  onUncheckLevel3,
  onOpenReport,
  reportAvailable,
  statusText,
  onRescan,
  scanning,
  hasScanned,
}: ToolbarBarProps) {
  return (
    <div className="bar">
      <div className="left">
        <Button onClick={onSelectAll}>Select all</Button>
        <Button onClick={onSelectNone}>Select none</Button>
        <Button onClick={onUncheckLevel3}>Uncheck Level 3</Button>
        <Button onClick={onOpenReport} disabled={!reportAvailable}>
          Open report
        </Button>
      </div>
      <div className="right">
        <span className="status">{statusText}</span>
        <Button variant="primary" onClick={onRescan} disabled={scanning}>
          {hasScanned ? "Re-scan" : "Scan"}
        </Button>
      </div>
    </div>
  );
}
