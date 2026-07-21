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
}

/** Ports the bottom DockPanel toolbar (Grid.Row=4) from New-PrimeChecklistApp. */
export function ToolbarBar({
  onSelectAll,
  onSelectNone,
  onUncheckLevel3,
  onOpenReport,
  reportAvailable,
  statusText,
  onRescan,
  scanning,
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
          Re-scan
        </Button>
      </div>
    </div>
  );
}
