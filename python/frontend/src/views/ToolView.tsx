import { useCallback, useEffect, useState } from "react";
import { api, type CatalogItem, type ScanResult, type ToolKey } from "../api";
import { Footer } from "../layout/Footer";
import { PageHeading } from "../layout/PageHeading";
import { SpecsPanel } from "../layout/SpecsPanel";
import { Topbar } from "../layout/Topbar";
import { ChecklistPanel, type LevelMeta } from "./ChecklistPanel";
import { StatsPanel, type ScanCounts } from "./StatsPanel";
import { ToolbarBar } from "./ToolbarBar";
import "./ToolView.css";
import type { PCSpecs } from "../api";

interface ToolConfig {
  title: string;
  eyebrow: string;
  headingPlain: string;
  headingAccent: string;
  subtitle: string;
  footerNote: string;
  levelMeta: Record<number, LevelMeta>;
}

const TOOL_CONFIG: Record<ToolKey, ToolConfig> = {
  fps: {
    title: "FPS Optimizer",
    eyebrow: "P R I M E P C T U N E R   ·   F O R  G A M I N G  R I G S",
    headingPlain: "FPS ",
    headingAccent: "Optimizer",
    subtitle:
      "Scanned automatically against your system — green means already applied. Uncheck anything you don't want. Nothing is changed in dry-run mode.",
    footerNote: "FPS Optimizer v0.3 · dry run — no changes applied",
    levelMeta: {
      1: { title: "LEVEL 1 · SAFE", color: "var(--green)" },
      2: { title: "LEVEL 2 · DEBLOAT", color: "var(--gold-a)" },
      3: { title: "LEVEL 3 · AGGRESSIVE", color: "var(--gold-b)" },
    },
  },
  startup: {
    title: "Startup Optimizer",
    eyebrow: "P R I M E P C T U N E R   ·   F O R  E V E R Y D A Y  P C s",
    headingPlain: "Startup ",
    headingAccent: "Optimizer",
    subtitle:
      "Every app, task, and Windows extra that launches itself at logon on this PC. Green means already clean. Unchecked rows are recommended keeps. Nothing is changed in dry-run mode.",
    footerNote: "Startup Optimizer v0.1 · dry run — no changes applied",
    levelMeta: {
      1: { title: "STARTUP APPS", color: "var(--green)" },
      2: { title: "LOGON TASKS", color: "var(--gold-a)" },
      3: { title: "WINDOWS EXTRAS", color: "var(--gold-b)" },
    },
  },
};

interface ToolViewProps {
  tool: ToolKey;
  specs: PCSpecs | null;
  onBack: () => void;
}

/** Ports New-PrimeChecklistApp + Invoke-PrimeScan — the branded checklist
 * window shared by both tools. Scan is one blocking POST /scan call (§6.6's
 * "ship the regression" decision), not a live per-row flip. */
export function ToolView({ tool, specs, onBack }: ToolViewProps) {
  const cfg = TOOL_CONFIG[tool];
  const [catalog, setCatalog] = useState<CatalogItem[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState<Map<string, ScanResult>>(new Map());
  const [counts, setCounts] = useState<ScanCounts | null>(null);
  const [reportAvailable, setReportAvailable] = useState(false);
  const [statusText, setStatusText] = useState("Not scanned yet — press Scan to check");

  const runScan = useCallback(
    async (ids: string[]) => {
      setScanning(true);
      setStatusText("Scanning…");
      try {
        const scanResults = await api.scan(tool, ids);
        const map = new Map(scanResults.map((r) => [r.Id, r]));
        const c: ScanCounts = {
          applied: 0,
          pending: 0,
          review: 0,
          skipped: 0,
          errors: 0,
        };
        for (const r of scanResults) {
          if (r.Status === "APPLIED") c.applied++;
          else if (r.Status === "PENDING") c.pending++;
          else if (r.Status === "REVIEW") c.review++;
          else if (r.Status === "SKIPPED") c.skipped++;
          else if (r.Status === "ERROR") c.errors++;
        }
        setResults(map);
        setCounts(c);
        setReportAvailable(true);
        setStatusText(
          `${c.applied} applied · ${c.pending} pending · ${c.review} review · ` +
            `${c.skipped} skipped · ${c.errors} errors`,
        );
      } catch (e) {
        setStatusText(
          `Scan failed: ${e instanceof Error ? e.message : "unknown error"}`,
        );
      } finally {
        setScanning(false);
      }
    },
    [tool],
  );

  useEffect(() => {
    // No auto-scan on load — the catalog renders with every row IDLE
    // ("not scanned") until the user presses Scan. Cancellation guard is
    // still needed for StrictMode's dev-mode double-invoke (mount →
    // cleanup → mount), since the catalog fetch itself is async.
    let cancelled = false;
    setCatalog(null);
    setResults(new Map());
    setCounts(null);
    setReportAvailable(false);
    setStatusText("Not scanned yet — press Scan to check");
    api
      .catalog(tool)
      .then((items) => {
        if (cancelled) return;
        setCatalog(items);
        const defaultChecked = new Set(items.filter((i) => i.DefaultChecked).map((i) => i.Id));
        setChecked(defaultChecked);
      })
      .catch((e) => {
        if (!cancelled) setLoadError(e.message ?? "failed to load catalog");
      });
    return () => {
      cancelled = true;
    };
  }, [tool]);

  const toggle = (id: string, isChecked: boolean) => {
    setChecked((prev) => {
      const next = new Set(prev);
      if (isChecked) next.add(id);
      else next.delete(id);
      return next;
    });
  };

  const selectAll = () =>
    catalog && setChecked(new Set(catalog.map((i) => i.Id)));
  const selectNone = () => setChecked(new Set());
  const uncheckLevel3 = () =>
    catalog &&
    setChecked((prev) => {
      const l3 = new Set(catalog.filter((i) => i.Level === 3).map((i) => i.Id));
      return new Set([...prev].filter((id) => !l3.has(id)));
    });
  const openReport = () => window.open(`/api/${tool}/report/latest`, "_blank");

  return (
    <div className="page">
      <div className="topRow">
        <button className="back" onClick={onBack}>
          ← HUB
        </button>
        <Topbar />
      </div>
      <PageHeading
        eyebrow={cfg.eyebrow}
        headingPlain={cfg.headingPlain}
        headingAccent={cfg.headingAccent}
        subtitle={cfg.subtitle}
        size="md"
      />

      <div className="metaRow">
        {specs && <SpecsPanel specs={specs} />}
        <div className="statsRow">
          <StatsPanel counts={counts} />
        </div>
      </div>

      {loadError && (
        <div className="error">Couldn't load catalog: {loadError}</div>
      )}
      {!catalog && !loadError && (
        <div className="loading">Loading catalog…</div>
      )}

      {catalog && (
        <div className="checklistWrap">
          <ChecklistPanel
            items={catalog}
            levelMeta={cfg.levelMeta}
            checkedIds={checked}
            onToggle={toggle}
            results={results}
            scanning={scanning}
          />
          <ToolbarBar
            onSelectAll={selectAll}
            onSelectNone={selectNone}
            onUncheckLevel3={uncheckLevel3}
            onOpenReport={openReport}
            reportAvailable={reportAvailable}
            statusText={statusText}
            onRescan={() => runScan([...checked])}
            scanning={scanning}
            hasScanned={counts !== null}
          />
        </div>
      )}

      <Footer note={cfg.footerNote} />
    </div>
  );
}
