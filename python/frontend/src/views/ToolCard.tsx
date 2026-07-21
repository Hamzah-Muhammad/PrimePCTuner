import type { ToolMeta } from "../api";
import { Button } from "../primitives/Button";
import { Card } from "../primitives/Card";
import "./ToolCard.css";

interface ToolCardProps {
  tool: ToolMeta;
  onLaunch: () => void;
}

const TAG_COLOR: Record<string, string> = {
  fps: "var(--green)",
  startup: "var(--gold-a)",
};

/** Ports the tool-launch card built inline in PrimePCTuner.ps1's foreach loop. */
export function ToolCard({ tool, onLaunch }: ToolCardProps) {
  return (
    <Card interactive>
      <div className="row">
        <div className="texts">
          <div className="titleLine">
            <span className="name">{tool.Name}</span>
            <span className="tag" style={{ color: TAG_COLOR[tool.Key] }}>
              {tool.Tag}
            </span>
          </div>
          <p className="desc">{tool.Desc}</p>
          <div className="meta">{tool.Meta}</div>
        </div>
        <Button variant="primary" className="launchBtn" onClick={onLaunch}>
          Launch →
        </Button>
      </div>
    </Card>
  );
}
