import type { CatalogItem, ScanResult } from "../api";
import { Card } from "../primitives/Card";
import { Checkbox } from "../primitives/Checkbox";
import { StatusPill, type PillStatus } from "../primitives/StatusPill";
import "./ChecklistRow.css";

interface ChecklistRowProps {
  item: CatalogItem;
  checked: boolean;
  onToggle: (checked: boolean) => void;
  result: ScanResult | undefined;
  scanning: boolean;
}

/** Ports the per-item card built inline in New-PrimeChecklistApp's checklist-rows loop. */
export function ChecklistRow({
  item,
  checked,
  onToggle,
  result,
  scanning,
}: ChecklistRowProps) {
  const status: PillStatus = scanning
    ? "SCANNING"
    : (result?.Status ?? "IDLE");
  const detail = scanning ? undefined : result?.Current;

  return (
    <Card>
      <div className="row">
        <span className="check">
          <Checkbox checked={checked} onChange={onToggle} label={item.Name} />
        </span>
        <span className="idPill">{item.Id}</span>
        <div className="texts">
          <div className="name">{item.Name}</div>
          <div className="desc">{item.Desc}</div>
          <div className="target">target: {item.Target}</div>
        </div>
        <div className="statusCol">
          <StatusPill status={status} detail={detail} />
        </div>
      </div>
    </Card>
  );
}
