import { useEffect, useState } from "react";
import { api, type ToolKey, type ToolsResponse } from "./api";
import { BackgroundGlows } from "./layout/BackgroundGlows";
import { HubView } from "./views/HubView";
import { ToolView } from "./views/ToolView";

type View = { name: "hub" } | { name: "tool"; toolKey: ToolKey };

/** Hand-rolled router (§6.6) — only 2 route shapes and a chromeless window,
 * so a plain view state machine beats pulling in react-router for nothing. */
function App() {
  const [view, setView] = useState<View>({ name: "hub" });
  const [toolsData, setToolsData] = useState<ToolsResponse | null>(null);
  const [toolsError, setToolsError] = useState<string | null>(null);
  const [healthWarning, setHealthWarning] = useState<string | null>(null);
  const [version, setVersion] = useState<string | null>(null);

  useEffect(() => {
    api
      .tools()
      .then(setToolsData)
      .catch((e) => setToolsError(e.message ?? "failed to load"));
    api
      .health()
      .then((h) => setHealthWarning(h.ok ? null : "PowerShell not found"))
      .catch(() => {});
    api
      .version()
      .then((v) => setVersion(v.version))
      .catch(() => {});
  }, []);

  return (
    <>
      <BackgroundGlows />
      {view.name === "hub" ? (
        <HubView
          data={toolsData}
          error={toolsError}
          healthWarning={healthWarning}
          version={version}
          onLaunch={(toolKey) => setView({ name: "tool", toolKey })}
        />
      ) : (
        <ToolView
          tool={view.toolKey}
          specs={toolsData?.specs ?? null}
          onBack={() => setView({ name: "hub" })}
        />
      )}
    </>
  );
}

export default App;
