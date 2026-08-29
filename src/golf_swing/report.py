from __future__ import annotations

import html
import json
from pathlib import Path
from typing import Any

from golf_swing.types import Finding, SwingResult, VideoInfo

CSS = """
:root { color-scheme: dark; --bg:#0b0e12; --card:#151a21; --line:#28313c;
  --text:#f5f6f7; --muted:#a7b0bb; --cyan:#41c9f2; --orange:#ff9137;
  --green:#70d684; --red:#ff6b66; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.5 Inter,
  ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { width:min(1220px, calc(100% - 32px)); margin:0 auto; padding:44px 0 80px; }
h1,h2,h3 { line-height:1.12; margin:0; letter-spacing:-.025em; }
h1 { font-size:clamp(2.3rem,6vw,4.6rem); max-width:900px; }
h2 { margin-top:52px; font-size:2rem; }
h3 { font-size:1.22rem; }
p { margin:.55rem 0; } a { color:var(--cyan); }
.eyebrow { color:var(--cyan); font-size:.78rem; font-weight:800; letter-spacing:.14em;
  text-transform:uppercase; margin-bottom:14px; }
.lede { color:var(--muted); font-size:1.13rem; max-width:860px; margin:18px 0 28px; }
.meta,.grid,.findings,.metrics { display:grid; gap:14px; }
.meta { grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); }
.meta div,.card,.finding,.scope { background:var(--card); border:1px solid var(--line);
  border-radius:14px; padding:18px; }
.meta strong { display:block; font-size:1.32rem; }.meta span,.muted { color:var(--muted); }
.scope { margin:28px 0; border-left:4px solid var(--orange); }
.findings { grid-template-columns:repeat(auto-fit,minmax(285px,1fr)); margin-top:18px; }
.finding { position:relative; padding-top:24px; }
.finding:before { content:""; position:absolute; inset:0 auto auto 0; width:100%; height:4px;
  background:var(--cyan); border-radius:14px 14px 0 0; }
.finding.priority:before { background:var(--red); }.finding.watch:before { background:var(--orange); }
.finding.good:before { background:var(--green); }
.finding .tag { color:var(--muted); font-size:.72rem; font-weight:800; letter-spacing:.1em;
  text-transform:uppercase; }
.swing { border-top:1px solid var(--line); margin-top:54px; padding-top:34px; }
.sequence { width:100%; display:block; border-radius:14px; border:1px solid var(--line);
  margin:20px 0; background:#050608; }
.metrics { grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); }
table { width:100%; border-collapse:collapse; font-size:.9rem; }
th,td { padding:9px 8px; text-align:right; border-bottom:1px solid var(--line); }
th:first-child,td:first-child { text-align:left; } th { color:var(--muted); font-weight:600; }
.footer { color:var(--muted); margin-top:56px; font-size:.88rem; }
code { color:#d9e3ed; }
"""


def _format_time(seconds: float) -> str:
    minutes = int(seconds // 60)
    remainder = seconds - minutes * 60
    return f"{minutes:02d}:{remainder:05.2f}"


def _finding_html(finding: Finding) -> str:
    return f"""
    <article class="finding {html.escape(finding.severity)}">
      <div class="tag">{html.escape(finding.severity)} · {html.escape(finding.confidence)} confidence · {html.escape(finding.event)}</div>
      <h3>{html.escape(finding.title)}</h3>
      <p>{html.escape(finding.observation)}</p>
      <p class="muted">{html.escape(finding.interpretation)}</p>
    </article>"""


def _metrics_table(metrics: dict[str, Any]) -> str:
    event_data = metrics["events"]
    rows = [
        ("Torso inclination", "torso_inclination_deg", "°"),
        ("Shoulder line", "shoulder_tilt_deg", "°"),
        ("Hip line", "hip_tilt_deg", "°"),
        ("Left knee", "left_knee_deg", "°"),
        ("Right knee", "right_knee_deg", "°"),
        ("Left elbow", "left_elbow_deg", "°"),
        ("Right elbow", "right_elbow_deg", "°"),
        ("Head shift", "head_shift_shoulders", " shoulders"),
    ]
    body = []
    for label, key, unit in rows:
        cells = []
        for event in ("address", "top", "impact", "finish"):
            value = event_data[event].get(key)
            cells.append("—" if value is None else f"{value}{unit}")
        body.append(
            "<tr><td>"
            + html.escape(label)
            + "</td>"
            + "".join(f"<td>{cell}</td>" for cell in cells)
            + "</tr>"
        )
    return (
        """
      <table><thead><tr><th>Projected metric</th><th>Address</th><th>Top</th><th>Impact</th><th>Finish</th></tr></thead>
      <tbody>"""
        + "".join(body)
        + "</tbody></table>"
    )


def write_video_report(
    path: Path,
    *,
    info: VideoInfo,
    results: list[SwingResult],
    collection_findings: list[Finding],
    view: str,
    manifest: dict[str, Any],
) -> None:
    all_findings = collection_findings + [
        finding for result in results for finding in result.findings
    ]
    findings_html = "".join(_finding_html(finding) for finding in all_findings)
    swing_sections = []
    for result in results:
        timing = result.metrics["timing"]
        swing_sections.append(
            f"""
            <section class="swing" id="swing-{result.number:02d}">
              <div class="eyebrow">Swing {result.number:02d} · impact {_format_time(result.events.impact)}</div>
              <h2>Evidence sequence</h2>
              <p class="muted">Impact selected by {html.escape(result.events.impact_source)}. Segmentation confidence {result.events.confidence:.2f}.</p>
              <img class="sequence" src="{html.escape(result.sequence_image)}" alt="Annotated address, top, impact, and finish frames for swing {result.number}">
              <div class="meta">
                <div><strong>{timing["backswing_seconds"]:.2f}s</strong><span>Backswing</span></div>
                <div><strong>{timing["downswing_seconds"]:.2f}s</strong><span>Downswing</span></div>
                <div><strong>{timing["tempo_ratio"]:.2f}:1</strong><span>Measured tempo ratio</span></div>
                <div><strong>{result.events.confidence:.2f}</strong><span>Sequence confidence</span></div>
              </div>
              <h2>Angle measurements</h2>
              <p class="muted">These are image-plane angles. They change with camera placement and are not true 3D joint angles.</p>
              {_metrics_table(result.metrics)}
            </section>"""
        )

    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(info.path.name)} · Golf swing analysis</title><style>{CSS}</style></head>
<body><main>
  <div class="eyebrow">Replay Caddie · evidence report</div>
  <h1>{html.escape(info.path.name)}</h1>
  <p class="lede">{len(results)} driver swings found in a {_format_time(info.duration)} portrait video. The report links every observation to measured pose geometry or event timing.</p>
  <div class="meta">
    <div><strong>{len(results)}</strong><span>Complete swings</span></div>
    <div><strong>{info.fps:.2f} fps</strong><span>Source frame rate</span></div>
    <div><strong>{info.display_width}×{info.display_height}</strong><span>Display resolution</span></div>
    <div><strong>{html.escape(view.replace("-", " "))}</strong><span>Declared camera view</span></div>
  </div>
  <div class="scope"><strong>What this run can support</strong>
    <p>Body pose, projected joint and body-line angles, event timing, visible movement, and repeatability.</p>
    <p class="muted">It cannot support clubface angle, club path, attack angle, clubhead speed, pressure shift, ball flight, or true 3D rotation from this single 30 fps view.</p>
  </div>
  <h2>Coaching hypotheses</h2>
  <p class="muted">Use these as testable priorities, not a diagnosis. Check each one against strike location and ball flight.</p>
  <div class="findings">{findings_html}</div>
  {"".join(swing_sections)}
  <section class="swing"><h2>Record the next session better</h2>
    <p>Use a fixed phone at hand height, record one true face-on view and one true down-the-line view, keep the full club and body visible, lock exposure on the golfer, and use 120 or 240 fps with a short shutter if available.</p>
  </section>
  <p class="footer">Source SHA-256 <code>{html.escape(manifest["source_sha256"])}</code> · Model SHA-256 <code>{html.escape(manifest["model_sha256"])}</code><br>
  This software is an analysis aid, not a substitute for a qualified golf instructor or medical professional.</p>
</main></body></html>"""
    path.write_text(document, encoding="utf-8")


def write_collection_index(
    path: Path,
    reports: list[dict[str, Any]],
    findings: list[Finding] | None = None,
) -> None:
    cards = []
    for report in reports:
        cards.append(
            f"""<a class="card" href="{html.escape(report["href"])}" style="text-decoration:none;color:inherit">
              <div class="eyebrow">{report["swings"]} swings</div><h3>{html.escape(report["name"])}</h3>
              <p class="muted">Open the annotated evidence report.</p></a>"""
        )
    findings_html = "".join(_finding_html(finding) for finding in (findings or []))
    summary = (
        f'<h2>Across all videos</h2><div class="findings">{findings_html}</div>'
        if findings_html
        else ""
    )
    document = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Golf swing analysis</title><style>{CSS}</style></head><body><main>
<div class="eyebrow">Replay Caddie · analysis collection</div><h1>Golf swing evidence</h1>
<p class="lede">Local reports for {sum(item["swings"] for item in reports)} detected swings.</p>
<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(280px,1fr))">{"".join(cards)}</div>
{summary}
</main></body></html>"""
    path.write_text(document, encoding="utf-8")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
