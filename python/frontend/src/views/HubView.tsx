import type { ToolKey, ToolsResponse } from "../api";
import { Footer } from "../layout/Footer";
import { PageHeading } from "../layout/PageHeading";
import { SpecsPanel } from "../layout/SpecsPanel";
import { Topbar } from "../layout/Topbar";
import { ToolCard } from "./ToolCard";
import "./HubView.css";

interface HubViewProps {
  data: ToolsResponse | null;
  error: string | null;
  healthWarning: string | null;
  version: string | null;
  onLaunch: (tool: ToolKey) => void;
}

/** Ports PrimePCTuner.ps1 — the suite hub: specs + pick a tool. */
export function HubView({
  data,
  error,
  healthWarning,
  version,
  onLaunch,
}: HubViewProps) {
  return (
    <div className="page">
      <Topbar healthWarning={healthWarning} />
      <PageHeading
        eyebrow="P R I M E P C T U N E R"
        headingPlain="Prime"
        headingAccent="PCTuner"
        subtitle="Your system, detected below. Pick the tool that fits this PC — every tool shows you each change as a checkbox before anything happens."
        size="lg"
      />

      {error && (
        <div className="error">Couldn't reach the backend: {error}</div>
      )}
      {!data && !error && <div className="loading">Detecting your system…</div>}

      {data && (
        <>
          <div className="specsRow">
            {data.specs && <SpecsPanel specs={data.specs} />}
          </div>
          <div className="cards">
            {data.tools.map((tool) => (
              <ToolCard
                key={tool.Key}
                tool={tool}
                onLaunch={() => onLaunch(tool.Key)}
              />
            ))}
          </div>
        </>
      )}

      <Footer note={version ? `PrimePCTuner hub v${version}` : "PrimePCTuner hub"} />
    </div>
  );
}
