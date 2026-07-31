"use strict";

const state = { all: [], filtered: [], hours: 24, config: {}, meta: {} };
const colors = { grid: "#20364a", text: "#8fa9bf", download: "#33d6c5", upload: "#4b8cff", ping: "#ffb84d", jitter: "#a889ff", loss: "#ff6577", failure: "rgba(255,101,119,.16)" };
const $ = (id) => document.getElementById(id);

// Acima deste número de pontos os marcadores viram ruído visual e a linha basta.
const MARKER_LIMIT = 60;

function number(value) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(String(value).replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function parseDate(value) {
  const match = String(value || "").match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
  if (!match) return null;
  return new Date(+match[1], +match[2] - 1, +match[3], +match[4], +match[5], +match[6]);
}

function normalize(row) {
  return {
    date: parseDate(row.DataHora), dateText: row.DataHora || "—",
    download: number(row.DownloadMbps), upload: number(row.UploadMbps),
    ping: number(row.PingMs), jitter: number(row.JitterMs), loss: number(row.PerdaPacotesPct),
    isp: row.ISP || "", server: row.Servidor || "—", location: row.LocalServidor || "",
    connection: row.Conexao || "—",
    url: row.URLResultado || "", status: row.Status || "Erro", message: row.Mensagem || ""
  };
}

const fmt = (value, digits = 1) => value === null || !Number.isFinite(value) ? "—" :
  value.toLocaleString("pt-BR", { minimumFractionDigits: digits, maximumFractionDigits: digits });
const avg = (rows, key) => {
  const values = rows.map(r => r[key]).filter(Number.isFinite);
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
};

// Resolução Anatel 574/2011: a velocidade média do período deve alcançar 80% da
// contratada e a instantânea, 40% em pelo menos 95% das medições.
const ANATEL = { averageFloor: 0.8, instantFloor: 0.4, instantShare: 0.95 };

function complianceFor(rows, key, contracted) {
  const values = rows.map(row => row[key]).filter(Number.isFinite);
  if (!values.length || !Number.isFinite(contracted) || contracted <= 0) return null;
  const average = values.reduce((a, b) => a + b, 0) / values.length;
  const aboveInstant = values.filter(value => value >= contracted * ANATEL.instantFloor).length;
  return {
    average,
    averageRatio: average / contracted,
    instantShare: aboveInstant / values.length,
    below: values.length - aboveInstant,
    samples: values.length
  };
}

function meter(label, ratio, target, detail) {
  const passed = ratio >= target;
  const width = Math.max(0, Math.min(100, ratio * 100));
  return `<article class="compliance-item ${passed ? "pass" : "fail"}">
    <header><span>${label}</span><strong>${fmt(ratio * 100)}%</strong></header>
    <div class="meter" role="img" aria-label="${fmt(ratio * 100)} por cento, meta ${fmt(target * 100, 0)} por cento">
      <div class="meter-fill" style="width:${width}%"></div>
      <span class="meter-target" style="left:${Math.min(100, target * 100)}%"></span>
    </div>
    <small>${detail}</small>
  </article>`;
}

function renderCompliance(rows) {
  const contracted = {
    download: number(state.config.contratadoDownloadMbps),
    upload: number(state.config.contratadoUploadMbps)
  };
  const results = {
    download: complianceFor(rows, "download", contracted.download),
    upload: complianceFor(rows, "upload", contracted.upload)
  };
  const active = Object.values(results).filter(Boolean);
  $("compliance").classList.toggle("hidden", active.length === 0);
  if (!active.length) return;

  const blocks = [];
  [["download", "Download"], ["upload", "Upload"]].forEach(([key, label]) => {
    const result = results[key];
    if (!result) return;
    blocks.push(meter(
      `${label} médio`, result.averageRatio, ANATEL.averageFloor,
      `${fmt(result.average)} de ${fmt(contracted[key])} Mbps contratados`
    ));
    blocks.push(meter(
      `${label} instantâneo`, result.instantShare, ANATEL.instantShare,
      `${result.below} de ${result.samples} medições abaixo de ${fmt(contracted[key] * ANATEL.instantFloor)} Mbps`
    ));
  });
  $("complianceGrid").innerHTML = blocks.join("");

  const compliant = active.every(result =>
    result.averageRatio >= ANATEL.averageFloor && result.instantShare >= ANATEL.instantShare);
  const verdict = $("complianceVerdict");
  verdict.textContent = compliant ? "Dentro do contratado" : "Abaixo do contratado";
  verdict.className = `pill ${compliant ? "good" : "bad"}`;
}

function applyRange() {
  const valid = state.all.filter(row => row.date);
  if (!state.hours) state.filtered = valid;
  else {
    const cutoff = new Date(Date.now() - state.hours * 3600000);
    state.filtered = valid.filter(row => row.date >= cutoff);
  }
  render();
}

function setMetric(id, value, threshold, direction) {
  $(id).textContent = fmt(value, 2);
  const card = $(id).closest(".metric");
  const alert = Number.isFinite(value) && Number.isFinite(threshold) &&
    (direction === "min" ? value < threshold : value > threshold);
  card.classList.toggle("alert", alert);
}

function render() {
  const rows = state.filtered;
  const latest = [...state.all].reverse().find(r => r.status === "Sucesso");
  const lastRecord = state.all[state.all.length - 1];
  $("dashboard").classList.toggle("hidden", state.all.length === 0);
  $("emptyState").classList.toggle("hidden", state.all.length !== 0);
  $("historyLink").classList.toggle("hidden", state.all.length === 0);
  if (!state.all.length) return;

  setMetric("downloadNow", latest?.download ?? null, number(state.config.downloadMinMbps), "min");
  setMetric("uploadNow", latest?.upload ?? null, number(state.config.uploadMinMbps), "min");
  setMetric("pingNow", latest?.ping ?? null, number(state.config.pingMaxMs), "max");
  setMetric("jitterNow", latest?.jitter ?? null, number(state.config.jitterMaxMs), "max");
  setMetric("lossNow", latest?.loss ?? null, number(state.config.packetLossMaxPct), "max");

  const successes = rows.filter(r => r.status === "Sucesso");
  renderCompliance(successes);
  $("downloadAvg").textContent = `${fmt(avg(successes, "download"))} Mbps`;
  $("uploadAvg").textContent = `${fmt(avg(successes, "upload"))} Mbps`;
  $("availability").textContent = rows.length ? `${fmt(successes.length * 100 / rows.length)}%` : "—";
  $("testCount").textContent = rows.length.toLocaleString("pt-BR");

  const ageMinutes = lastRecord?.date ? (Date.now() - lastRecord.date.getTime()) / 60000 : Infinity;
  const configuredInterval = number(state.config.collectionIntervalMinutes);
  const staleLimit = number(state.config.staleAfterMinutes) ??
    (Number.isFinite(configuredInterval) ? configuredInterval * 2.5 : 150);
  const pill = $("statusPill");
  pill.className = "pill";
  pill.removeAttribute("title");
  if (lastRecord?.status !== "Sucesso") {
    pill.textContent = "Última coleta falhou";
    pill.classList.add("bad");
    if (lastRecord?.message) pill.title = lastRecord.message;
  } else if (ageMinutes > staleLimit) {
    pill.textContent = "Dados desatualizados";
    pill.classList.add("warn");
  } else {
    pill.textContent = "Conexão medida";
    pill.classList.add("good");
  }

  if (lastRecord?.status !== "Sucesso" && lastRecord?.date) {
    const previousSuccess = latest?.date ?
      ` · Último sucesso: ${latest.date.toLocaleString("pt-BR")}` : "";
    $("freshness").textContent =
      `Última tentativa: ${lastRecord.date.toLocaleString("pt-BR")} · falhou${previousSuccess}`;
  } else {
    $("freshness").textContent = lastRecord?.date ?
      `Última coleta: ${lastRecord.date.toLocaleString("pt-BR")} · ${lastRecord.isp || "provedor não informado"}` :
      "Horário da última coleta indisponível";
  }

  drawChart($("speedChart"), successes, [
    { key: "download", color: colors.download }, { key: "upload", color: colors.upload }
  ], "Mbps");
  drawChart($("latencyChart"), successes, [
    { key: "ping", color: colors.ping }, { key: "jitter", color: colors.jitter }
  ], "ms");
  drawChart($("lossChart"), successes, [{ key: "loss", color: colors.loss }], "%");

  const visible = $("onlyErrors").checked ? rows.filter(r => r.status !== "Sucesso") : rows;
  renderTable([...visible].reverse().slice(0, 50));

  // O gerador do painel corta o histórico; sem este aviso o botão "Tudo" mentiria.
  const total = number(state.meta.totalRows);
  const shown = number(state.meta.shownRows);
  const truncated = Number.isFinite(total) && Number.isFinite(shown) && total > shown;
  setNotice(truncated
    ? `Exibindo as ${shown.toLocaleString("pt-BR")} medições mais recentes de ` +
      `${total.toLocaleString("pt-BR")} registradas. O histórico completo está no CSV.`
    : "");
}

function renderTable(rows) {
  if (!rows.length) {
    $("historyBody").innerHTML = `<tr><td colspan="9" class="table-empty">Nenhuma medição neste período.</td></tr>`;
    return;
  }
  $("historyBody").innerHTML = rows.map(row => {
    const statusClass = row.status === "Sucesso" ? "status-ok" : "status-error";
    const status = row.status === "Sucesso" ? "Sucesso" : `Erro${row.message ? `: ${escapeHtml(row.message)}` : ""}`;
    const server = row.url
      ? `<a href="${escapeHtml(row.url)}" target="_blank" rel="noreferrer noopener">${escapeHtml(row.server)}</a>`
      : escapeHtml(row.server);
    return `<tr>
      <td>${row.date ? row.date.toLocaleString("pt-BR") : escapeHtml(row.dateText)}</td>
      <td>${fmt(row.download, 2)}</td><td>${fmt(row.upload, 2)}</td>
      <td>${fmt(row.ping, 2)}</td><td>${fmt(row.jitter, 2)}</td><td>${fmt(row.loss, 2)}</td>
      <td>${escapeHtml(row.connection)}</td>
      <td title="${escapeHtml(row.location)}">${server}</td>
      <td class="${statusClass}" title="${escapeHtml(row.message)}">${status}</td>
    </tr>`;
  }).join("");
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
}

function drawChart(canvas, rows, series, unit) {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.max(300, Math.floor(rect.width * dpr));
  canvas.height = Math.max(180, Math.floor(rect.height * dpr));
  const ctx = canvas.getContext("2d");
  ctx.scale(dpr, dpr);
  const width = canvas.width / dpr, height = canvas.height / dpr;
  const pad = { l: 52, r: 12, t: 24, b: 30 };
  const plotW = width - pad.l - pad.r, plotH = height - pad.t - pad.b;
  const values = rows.flatMap(row => series.map(s => row[s.key])).filter(Number.isFinite);
  let max = values.length ? Math.max(...values) : 1;
  max = max <= 0 ? 1 : max * 1.12;

  ctx.clearRect(0, 0, width, height);
  ctx.font = "11px Segoe UI";

  // A unidade fica fora da coluna de rótulos: junto ao valor ela estourava o
  // espaço de pad.l e o número aparecia cortado.
  ctx.fillStyle = colors.text;
  ctx.textAlign = "left";
  ctx.textBaseline = "top";
  ctx.fillText(unit, 4, 4);

  ctx.textAlign = "right";
  ctx.textBaseline = "middle";
  for (let i = 0; i <= 4; i++) {
    const y = pad.t + plotH * i / 4;
    const value = max * (1 - i / 4);
    ctx.strokeStyle = colors.grid; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(width - pad.r, y); ctx.stroke();
    ctx.fillStyle = colors.text; ctx.fillText(compact(value), pad.l - 8, y);
  }
  if (!rows.length) {
    ctx.fillStyle = colors.text; ctx.textAlign = "center";
    ctx.fillText("Sem dados neste período", pad.l + plotW / 2, pad.t + plotH / 2);
    return;
  }

  const times = rows.map(r => r.date.getTime());
  const minTime = Math.min(...times), maxTime = Math.max(...times);
  const span = Math.max(1, maxTime - minTime);
  const pointAt = (row, key) => ({
    x: pad.l + (row.date.getTime() - minTime) / span * plotW,
    y: pad.t + plotH - row[key] / max * plotH
  });

  drawFailureBands(ctx, pad, plotW, plotH, minTime, span);

  series.forEach(s => {
    ctx.strokeStyle = s.color; ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round";
    ctx.beginPath(); let started = false;
    rows.forEach(row => {
      const value = row[s.key];
      if (!Number.isFinite(value)) { started = false; return; }
      const point = pointAt(row, s.key);
      if (!started) { ctx.moveTo(point.x, point.y); started = true; } else ctx.lineTo(point.x, point.y);
    });
    ctx.stroke();

    // Um caminho de ponto único não produz traço algum: sem os marcadores, um histórico
    // com uma ou duas medições renderiza um gráfico vazio.
    const points = rows.filter(row => Number.isFinite(row[s.key]));
    if (points.length <= MARKER_LIMIT) {
      ctx.fillStyle = s.color;
      points.forEach(row => {
        const point = pointAt(row, s.key);
        ctx.beginPath();
        ctx.arc(point.x, point.y, 3, 0, Math.PI * 2);
        ctx.fill();
      });
    }
  });

  ctx.fillStyle = colors.text; ctx.textBaseline = "top";
  ctx.textAlign = "left"; ctx.fillText(rows[0].date.toLocaleDateString("pt-BR"), pad.l, height - 20);
  ctx.textAlign = "right"; ctx.fillText(rows[rows.length - 1].date.toLocaleDateString("pt-BR"), width - pad.r, height - 20);
}

// Coletas com falha são excluídas das séries; sem essas faixas, uma queda de horas
// aparece como uma linha perfeitamente contínua.
function drawFailureBands(ctx, pad, plotW, plotH, minTime, span) {
  const failures = state.filtered.filter(row => row.status !== "Sucesso" && row.date);
  if (!failures.length) return;
  const intervalMinutes = number(state.config.collectionIntervalMinutes) || 60;
  const bandWidth = Math.max(3, Math.min(plotW, intervalMinutes * 60000 / span * plotW));
  ctx.save();
  ctx.fillStyle = colors.failure;
  failures.forEach(row => {
    const center = pad.l + (row.date.getTime() - minTime) / span * plotW;
    const start = Math.max(pad.l, center - bandWidth / 2);
    const end = Math.min(pad.l + plotW, center + bandWidth / 2);
    if (end > start) ctx.fillRect(start, pad.t, end - start, plotH);
  });
  ctx.restore();
}

function compact(value) {
  return value >= 1000 ? `${(value / 1000).toFixed(1)}k` : value.toFixed(value < 10 ? 1 : 0);
}

function load() {
  try {
    const raw = window.INTERNET_MONITOR_DATA || [];
    state.config = window.INTERNET_MONITOR_CONFIG || {};
    state.meta = window.INTERNET_MONITOR_META || {};
    state.all = (Array.isArray(raw) ? raw : raw ? [raw] : []).map(normalize).filter(r => r.date).sort((a, b) => a.date - b.date);
    applyRange();
  } catch (error) {
    $("statusPill").textContent = "Falha ao carregar";
    $("statusPill").className = "pill bad";
    $("freshness").textContent = error.message;
  }
}

// Recarregar data.js por injeção de <script> funciona em file://, onde fetch() é
// bloqueado, e preserva o período selecionado, o scroll e a posição da tabela.
function fetchData() {
  return new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = `data.js?t=${Date.now()}`;
    script.onload = () => { script.remove(); resolve(); };
    script.onerror = () => { script.remove(); reject(new Error("Não foi possível ler data.js.")); };
    document.head.appendChild(script);
  });
}

async function refresh(manual) {
  const button = $("refreshButton");
  button.disabled = true;
  button.classList.add("busy");
  try {
    await fetchData();
    load(); // render() reescreve o aviso conforme o estado dos dados.
  } catch (error) {
    if (manual) setNotice(error.message);
  } finally {
    button.disabled = false;
    button.classList.remove("busy");
  }
}

function setNotice(message) {
  const notice = $("notice");
  notice.textContent = message;
  notice.classList.toggle("hidden", !message);
}

document.querySelectorAll(".range-picker button").forEach(button => button.addEventListener("click", () => {
  document.querySelectorAll(".range-picker button").forEach(b => {
    b.classList.remove("active");
    b.setAttribute("aria-selected", "false");
  });
  button.classList.add("active");
  button.setAttribute("aria-selected", "true");
  state.hours = Number(button.dataset.hours);
  applyRange();
}));
$("refreshButton").addEventListener("click", () => refresh(true));
$("onlyErrors").addEventListener("change", () => render());
window.addEventListener("resize", () => render());
load();

// Verificar quatro vezes por intervalo de coleta é suficiente e evita o piscar da
// tela a cada minuto que o reload completo provocava.
const intervalMinutes = number(state.config.collectionIntervalMinutes) || 60;
setInterval(() => refresh(false), Math.max(60000, intervalMinutes * 15000));
