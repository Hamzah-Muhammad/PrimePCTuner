import type { ButtonHTMLAttributes } from "react";
import "./Button.css";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "danger";
}

/** Ports the BtnPri / BtnSec XAML Styles. "danger" is a new addition (not in
 * the original WPF app, which had no apply/undo UI) for the apply/undo
 * confirmation flow — same shape as btnPri, red instead of green. */
export function Button({
  variant = "secondary",
  className,
  ...rest
}: ButtonProps) {
  const variantClass =
    variant === "primary" ? "btnPri" : variant === "danger" ? "btnDanger" : "btnSec";
  return (
    <button
      className={["btn", variantClass, className].filter(Boolean).join(" ")}
      {...rest}
    />
  );
}
