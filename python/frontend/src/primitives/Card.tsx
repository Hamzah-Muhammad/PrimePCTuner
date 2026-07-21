import type { HTMLAttributes } from "react";
import "./Card.css";

interface CardProps extends HTMLAttributes<HTMLDivElement> {
  interactive?: boolean;
}

/** Ports the "RowCard" XAML Style — used for both checklist item rows and
 * the hub's tool-launch cards. */
export function Card({ interactive, className, ...rest }: CardProps) {
  return (
    <div
      className={["card", interactive && "interactive", className]
        .filter(Boolean)
        .join(" ")}
      {...rest}
    />
  );
}
