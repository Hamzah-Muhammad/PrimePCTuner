import type { ButtonHTMLAttributes } from "react";
import "./Button.css";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary";
}

/** Ports the BtnPri / BtnSec XAML Styles. */
export function Button({
  variant = "secondary",
  className,
  ...rest
}: ButtonProps) {
  const variantClass = variant === "primary" ? "btnPri" : "btnSec";
  return (
    <button
      className={["btn", variantClass, className].filter(Boolean).join(" ")}
      {...rest}
    />
  );
}
