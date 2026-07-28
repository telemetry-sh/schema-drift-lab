const defaults = {
  total_events: 12000,
  v2_percent: 35,
  v3_percent: 25,
  error_percent: 8,
  slow_percent: 12,
  raw_route_percent: 18,
  slo_ms: 750,
  max_series: 500,
};

const number = new Intl.NumberFormat("en-US");
const form = document.querySelector("#controls");
const status = document.querySelector("#experiment-status");
const strategyTabs = [...document.querySelectorAll("[data-strategy]")];
const evidenceTabs = [...document.querySelectorAll("[data-evidence]")];
let result = null;
let activeStrategy = "lenient";
let activeEvidence = 0;
let requestTimer = null;

const outputIds = {
  total_events: "total-events-output",
  v2_percent: "v2-percent-output",
  v3_percent: "v3-percent-output",
  slow_percent: "slow-percent-output",
  raw_route_percent: "raw-route-percent-output",
  max_series: "max-series-output",
};

function readParams() {
  return Object.fromEntries(
    [...form.querySelectorAll("input")].map((input) => [
      input.name,
      Number(input.value),
    ]),
  );
}

function setText(id, value) {
  document.querySelector(`#${id}`).textContent = value;
}

function refreshOutputs() {
  constrainRollout();
  const values = readParams();
  Object.entries(outputIds).forEach(([key, id]) => {
    const suffix = key.endsWith("_percent") ? "%" : "";
    setText(id, `${number.format(values[key])}${suffix}`);
  });
}

function constrainRollout() {
  const v2 = form.elements.namedItem("v2_percent");
  const v3 = form.elements.namedItem("v3_percent");
  const maximum = Math.min(80, 95 - Number(v2.value));
  v3.max = String(maximum);
  if (Number(v3.value) > maximum) v3.value = String(maximum);
}

async function runExperiment() {
  const params = new URLSearchParams(readParams());
  status.textContent = "Recomputing model…";
  status.classList.remove("is-error");

  try {
    const response = await fetch(`/api/simulate?${params}`, {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      throw new Error(`model returned ${response.status}`);
    }
    result = await response.json();
    render();
    status.textContent = "Model synchronized";
  } catch (error) {
    status.textContent = "Model unavailable";
    status.classList.add("is-error");
    console.error(error);
  }
}

function scheduleExperiment() {
  refreshOutputs();
  window.clearTimeout(requestTimer);
  requestTimer = window.setTimeout(runExperiment, 120);
}

function render() {
  renderTruth();
  renderCohorts();
  renderCoverageChart();
  renderStrategy();
  renderEvidence();
  setText("lesson", result.lesson);
}

function renderTruth() {
  const { truth } = result;
  setText("truth-events", number.format(truth.total_events));
  setText("truth-slow", number.format(truth.slo_violations));
  setText("truth-slow-detail", `${truth.slow_percent}% of requests`);
  setText("truth-latency", number.format(truth.mean_latency_ms));
  setText("truth-drift", `${truth.drifted_percent}%`);
}

function renderCohorts() {
  const { cohorts } = result;
  const mix = `v1 ${cohorts.v1.percent}% · v2 ${cohorts.v2.percent}% · v3 ${cohorts.v3.percent}%`;
  setText("mix-caption", mix);
  setText("cohort-v1", "");
  setText("cohort-v2", "");
  setText("cohort-v3", "");
  document.querySelector("#cohort-v1").style.width = `${cohorts.v1.percent}%`;
  document.querySelector("#cohort-v2").style.width = `${cohorts.v2.percent}%`;
  document.querySelector("#cohort-v3").style.width = `${cohorts.v3.percent}%`;
  document.querySelector(".cohort-bar").setAttribute("aria-label", mix);
}

function renderCoverageChart() {
  const svg = document.querySelector("#coverage-chart");
  const points = result.timeline;
  const width = 760;
  const height = 250;
  const pad = { top: 18, right: 14, bottom: 33, left: 41 };
  const innerWidth = width - pad.left - pad.right;
  const innerHeight = height - pad.top - pad.bottom;
  const x = (index) => pad.left + (index / (points.length - 1)) * innerWidth;
  const y = (value) => pad.top + ((100 - value) / 100) * innerHeight;
  const ns = "http://www.w3.org/2000/svg";

  while (svg.lastChild && !["title", "desc"].includes(svg.lastChild.tagName)) {
    svg.removeChild(svg.lastChild);
  }

  [0, 25, 50, 75, 100].forEach((tick) => {
    const line = document.createElementNS(ns, "line");
    line.setAttribute("x1", pad.left);
    line.setAttribute("x2", width - pad.right);
    line.setAttribute("y1", y(tick));
    line.setAttribute("y2", y(tick));
    line.setAttribute("stroke", "#d8d3c8");
    line.setAttribute("stroke-width", "1");
    svg.appendChild(line);

    const label = document.createElementNS(ns, "text");
    label.setAttribute("x", pad.left - 9);
    label.setAttribute("y", y(tick) + 3);
    label.setAttribute("text-anchor", "end");
    label.setAttribute("font-size", "9");
    label.setAttribute("font-family", "monospace");
    label.setAttribute("fill", "#6b6860");
    label.textContent = `${tick}%`;
    svg.appendChild(label);
  });

  const series = [
    ["lenient_coverage_percent", "#e5472f", "4 4"],
    ["coerce_semantic_percent", "#d19d00", "7 4"],
    ["versioned_coverage_percent", "#1859ff", ""],
  ];

  series.forEach(([key, color, dash]) => {
    const path = document.createElementNS(ns, "path");
    const d = points
      .map((point, index) => `${index === 0 ? "M" : "L"} ${x(index)} ${y(point[key])}`)
      .join(" ");
    path.setAttribute("d", d);
    path.setAttribute("fill", "none");
    path.setAttribute("stroke", color);
    path.setAttribute("stroke-width", "3");
    path.setAttribute("vector-effect", "non-scaling-stroke");
    if (dash) path.setAttribute("stroke-dasharray", dash);
    svg.appendChild(path);
  });

  const start = document.createElementNS(ns, "text");
  start.setAttribute("x", pad.left);
  start.setAttribute("y", height - 9);
  start.setAttribute("font-size", "9");
  start.setAttribute("font-family", "monospace");
  start.setAttribute("fill", "#6b6860");
  start.textContent = "ROLLOUT START";
  svg.appendChild(start);

  const end = document.createElementNS(ns, "text");
  end.setAttribute("x", width - pad.right);
  end.setAttribute("y", height - 9);
  end.setAttribute("text-anchor", "end");
  end.setAttribute("font-size", "9");
  end.setAttribute("font-family", "monospace");
  end.setAttribute("fill", "#6b6860");
  end.textContent = "CURRENT MIX";
  svg.appendChild(end);

  const final = points.at(-1);
  document.querySelector("#coverage-chart-desc").textContent =
    `At the final rollout mix, lenient ingestion understands ${final.lenient_coverage_percent} percent, ` +
    `best-effort coercion understands ${final.coerce_semantic_percent} percent, and the versioned contract understands 100 percent.`;
}

function renderStrategy() {
  if (!result) return;
  const strategy = result.strategies.find((item) => item.id === activeStrategy);
  const truth = result.truth;
  const params = result.params;

  setText("strategy-state", `STATE / ${strategy.state}`);
  setText("strategy-name", strategy.label);
  setText("strategy-description", strategy.description);
  setText("strategy-diagnosis", strategy.diagnosis);
  setText("metric-coverage", `${strategy.semantic_coverage_percent}%`);
  setText(
    "metric-understood",
    `${number.format(strategy.understood_events)} / ${number.format(truth.total_events)} understood`,
  );
  setText("metric-slo", number.format(strategy.observed_slo_violations));
  setText(
    "metric-slo-delta",
    signedDelta(strategy.observed_slo_violations - truth.slo_violations, "vs truth"),
  );
  setText("metric-mean", `${number.format(strategy.observed_mean_latency_ms)} ms`);
  setText(
    "metric-mean-delta",
    signedDelta(strategy.observed_mean_latency_ms - truth.mean_latency_ms, "ms vs truth"),
  );
  setText("metric-series", number.format(strategy.route_series));
  setText(
    "metric-series-budget",
    strategy.route_series > params.max_series
      ? `${number.format(strategy.route_series - params.max_series)} over budget`
      : `${number.format(params.max_series - strategy.route_series)} budget remaining`,
  );
  setText("metric-dropped", number.format(strategy.dropped_events));
  setText("metric-units", number.format(strategy.unit_violations));

  strategyTabs.forEach((tab) => {
    const selected = tab.dataset.strategy === activeStrategy;
    tab.setAttribute("aria-selected", String(selected));
    tab.setAttribute("tabindex", selected ? "0" : "-1");
  });
  const selectedTab = strategyTabs.find((tab) => tab.dataset.strategy === activeStrategy);
  document.querySelector("#strategy-detail").setAttribute("aria-labelledby", selectedTab.id);
}

function signedDelta(value, suffix) {
  const sign = value > 0 ? "+" : "";
  return `${sign}${number.format(value)} ${suffix}`;
}

function renderEvidence() {
  if (!result) return;
  const item = result.evidence[activeEvidence];
  setText("raw-payload", JSON.stringify(item.payload, null, 2));
  setText("normalized-payload", JSON.stringify(item.normalized, null, 2));
  setText("evidence-finding", `${item.status.toUpperCase()} — ${item.finding}`);
  evidenceTabs.forEach((tab, index) => {
    const selected = index === activeEvidence;
    tab.setAttribute("aria-selected", String(selected));
    tab.setAttribute("tabindex", selected ? "0" : "-1");
  });
  document
    .querySelector("#evidence-detail")
    .setAttribute("aria-labelledby", evidenceTabs[activeEvidence].id);
}

form.addEventListener("input", scheduleExperiment);
form.addEventListener("reset", () => {
  window.setTimeout(() => {
    Object.entries(defaults).forEach(([key, value]) => {
      const input = form.elements.namedItem(key);
      if (input) input.value = value;
    });
    scheduleExperiment();
  }, 0);
});

strategyTabs.forEach((tab, index) => {
  tab.addEventListener("click", () => {
    activeStrategy = tab.dataset.strategy;
    renderStrategy();
  });
  tab.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
    event.preventDefault();
    const direction = event.key === "ArrowRight" ? 1 : -1;
    const next = (index + direction + strategyTabs.length) % strategyTabs.length;
    activeStrategy = strategyTabs[next].dataset.strategy;
    strategyTabs[next].focus();
    renderStrategy();
  });
});

evidenceTabs.forEach((tab, index) => {
  tab.addEventListener("click", () => {
    activeEvidence = Number(tab.dataset.evidence);
    renderEvidence();
  });
  tab.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
    event.preventDefault();
    const direction = event.key === "ArrowRight" ? 1 : -1;
    activeEvidence = (index + direction + evidenceTabs.length) % evidenceTabs.length;
    evidenceTabs[activeEvidence].focus();
    renderEvidence();
  });
});

refreshOutputs();
runExperiment();
