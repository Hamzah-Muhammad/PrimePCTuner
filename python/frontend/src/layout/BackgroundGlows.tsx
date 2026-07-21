import "./BackgroundGlows.css";

/** Ports the two RadialGradientBrush Ellipses from PrimeUI.ps1's Get-PrimeGlowsXaml. */
export function BackgroundGlows() {
  return (
    <div className="glows" aria-hidden="true">
      <div className="glowTop" />
      <div className="glowBottom" />
    </div>
  );
}
