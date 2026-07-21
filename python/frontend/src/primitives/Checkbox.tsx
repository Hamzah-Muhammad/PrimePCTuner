import "./Checkbox.css";

interface CheckboxProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label?: string;
}

/** Ports the "PrimeCheck" custom ControlTemplate. */
export function Checkbox({ checked, onChange, label }: CheckboxProps) {
  return (
    <span className="checkbox">
      <input
        className="input"
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        aria-label={label}
      />
      <span className="box">
        <span className="mark">✓</span>
      </span>
    </span>
  );
}
