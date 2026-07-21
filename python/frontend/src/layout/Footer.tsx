import "./Footer.css";

interface FooterProps {
  note: string;
}

export function Footer({ note }: FooterProps) {
  return (
    <div className="footer">
      <span>
        <span className="at">@</span>Humzeeny
      </span>
      <span>{note}</span>
    </div>
  );
}
