import type { ReactNode } from "react";
import "./Chip.css";

interface ChipProps {
  label: string;
  value: ReactNode;
  valueColor?: string;
}

/** Ports the "Chip" XAML Style — used for spec chips and scan-stat chips. */
export function Chip({ label, value, valueColor }: ChipProps) {
  return (
    <span className="chip">
      <span className="label">{label}</span>
      <span
        className="value"
        style={valueColor ? { color: valueColor } : undefined}
      >
        {value}
      </span>
    </span>
  );
}
