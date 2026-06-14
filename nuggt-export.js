// ── Send to Nuggt — manifest builders & publish ─────────

const NUGGT_SCHEMA = 'https://nuggt.com/schemas/chart-import/v1';

function nuggtApiBase() {
  return window.NUGGT_API_BASE || 'https://nuggt.com';
}

function nuggtPublishKey() {
  const meta = document.querySelector('meta[name="nuggt-publish-key"]');
  return window.NUGGT_PUBLISH_KEY
    || (meta?.content?.trim())
    || localStorage.getItem('nuggt-publish-key')
    || '';
}

function nuggtErrorMessage(err, status, key) {
  if (status === 401) {
    return 'Nuggt rejected the request (401). Set a valid publish key in nuggt-config.js — see nuggt-config.example.js.';
  }
  if (status === 403) {
    return 'Nuggt rejected the request (403). Check that this site\'s origin is listed in MANIFEST_PUBLISH_ORIGINS on the Nuggt server.';
  }
  if (status === 422) {
    return `Nuggt could not validate this chart (${err?.message || '422'}). Check the browser console for details.`;
  }
  if (err?.name === 'TypeError' && /fetch|network/i.test(String(err.message))) {
    return key
      ? 'Network or CORS error contacting Nuggt. Ensure MANIFEST_PUBLISH_ORIGINS includes this site (e.g. https://edconway.github.io).'
      : 'Network or CORS error contacting Nuggt. You likely need a publish key in nuggt-config.js and your origin allowed on the Nuggt server.';
  }
  if (!key) {
    return 'Could not send to Nuggt. Set NUGGT_PUBLISH_KEY in nuggt-config.js (production requires a publish key).';
  }
  return `Could not send to Nuggt. ${err?.message || 'Please try again.'}`;
}

async function nuggtPublish(manifest, key) {
  const base = nuggtApiBase();
  const headers = { 'Content-Type': 'application/json' };
  if (key) headers.Authorization = `Bearer ${key}`;

  const endpoints = ['/api/weather-manifest', '/api/manifests'];
  let lastErr = null;
  let lastStatus = 0;

  for (const path of endpoints) {
    try {
      const res = await fetch(`${base}${path}`, {
        method: 'POST',
        headers,
        body: JSON.stringify(manifest),
      });
      lastStatus = res.status;
      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        let msg = detail;
        try {
          const j = JSON.parse(detail);
          msg = j.detail || j.message || detail;
        } catch {}
        const err = new Error(msg || `Request failed (${res.status})`);
        err.status = res.status;
        lastErr = err;
        if (res.status >= 500) continue;
        throw err;
      }
      const data = await res.json();
      const importUrl = data.import_url || data.importUrl;
      if (!importUrl) throw new Error('No import URL returned');
      return importUrl;
    } catch (err) {
      lastErr = err;
      if (lastStatus >= 500) continue;
      throw err;
    }
  }
  throw lastErr || new Error('Request failed');
}

function nuggtNum(v) {
  if (v == null || typeof v !== 'number' || Number.isNaN(v)) return null;
  return Math.round(v * 100) / 100;
}

function nuggtSeries(values) {
  return values.map(v => {
    const n = nuggtNum(v);
    return n === null ? 0 : n;
  });
}

function nuggtLocSuffix() {
  const loc = geoName?.split(',')[0]?.trim();
  return loc ? ` — ${loc}` : '';
}

function nuggtProvenance() {
  return {
    sourceUrl: 'https://open-meteo.com',
    sourceLabel: 'Open-Meteo',
    license: 'CC BY 4.0',
  };
}

function nuggtManifest(chartMeta, dataExtra) {
  return {
    schema: NUGGT_SCHEMA,
    chart: chartMeta,
    data: { aspect_ratio: '16/9', line_style: 'monotone', ...dataExtra },
    provenance: nuggtProvenance(),
    style: { theme: 'editorial' },
  };
}

function fmtHourLabel(iso) {
  const d = new Date(iso.includes('T') ? iso : iso + 'T12:00:00');
  const hr = d.getHours();
  const day = d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
  const time = hr === 0 ? 'Midnight' : hr === 12 ? 'Noon' : hr < 12 ? `${hr}am` : `${hr - 12}pm`;
  return `${day} ${time}`;
}

function fmtDayLabel(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr.includes('T') ? dateStr : dateStr + 'T12:00:00');
  return d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
}

function buildNuggtManifest(chartId) {
  const u = uT();
  const loc = nuggtLocSuffix();

  if (chartId === 'temp' && _tempData) {
    const { labels, maxV, minV } = _tempData;
    return nuggtManifest(
      {
        title: `14-Day Temperature${loc}`.slice(0, 200),
        description: 'Daily high and low · forecast vs historical band',
        type: 'line',
        tags: ['weather', 'temperature'],
      },
      {
        labels,
        datasets: [
          { name: `High (${u})`, data: nuggtSeries(maxV) },
          { name: `Low (${u})`, data: nuggtSeries(minV) },
        ],
      }
    );
  }

  if (chartId === 'hourly' && _hourlyData) {
    const { temps, histLine, times } = _hourlyData;
    const labels = times.map(fmtHourLabel);
    return nuggtManifest(
      {
        title: `48-Hour Temperature${loc}`.slice(0, 200),
        description: 'Hourly actual & forecast vs historical average',
        type: 'line',
        tags: ['weather', 'temperature'],
      },
      {
        labels,
        datasets: [
          { name: `Temperature (${u})`, data: nuggtSeries(temps) },
          { name: `Historical avg (${u})`, data: nuggtSeries(histLine) },
        ],
      }
    );
  }

  if (chartId === 'hourly-rain' && _hourlyRainData) {
    const { precip, times } = _hourlyRainData;
    const labels = times.map(fmtHourLabel);
    const rainUnit = imp ? 'in' : 'mm';
    return nuggtManifest(
      {
        title: `48-Hour Rainfall${loc}`.slice(0, 200),
        description: 'Hourly precipitation',
        type: 'bar',
        tags: ['weather', 'rainfall'],
      },
      {
        labels,
        datasets: [{ name: `Rainfall (${rainUnit})`, data: nuggtSeries(precip) }],
      }
    );
  }

  if (chartId === 'daily-rain' && _dailyRainData) {
    const { dates, precip } = _dailyRainData;
    const labels = dates.map(fmtDayLabel);
    const rainUnit = imp ? 'in' : 'mm';
    return nuggtManifest(
      {
        title: `14-Day Rainfall${loc}`.slice(0, 200),
        description: 'Daily precipitation total',
        type: 'bar',
        tags: ['weather', 'rainfall'],
      },
      {
        labels,
        datasets: [{ name: `Rainfall (${rainUnit})`, data: nuggtSeries(precip) }],
      }
    );
  }

  if (chartId === 'hourly-humid' && _hourlyHumidData) {
    const { hVals, aVals, times } = _hourlyHumidData;
    const labels = times.map(fmtHourLabel);
    return nuggtManifest(
      {
        title: `48-Hour Humidity${loc}`.slice(0, 200),
        description: 'Relative humidity vs historical average',
        type: 'line',
        tags: ['weather', 'humidity'],
      },
      {
        labels,
        datasets: [
          { name: 'Humidity (%)', data: nuggtSeries(hVals) },
          { name: 'Historical avg (%)', data: nuggtSeries(aVals) },
        ],
      }
    );
  }

  if (chartId === 'daily-humid' && _dailyHumidData) {
    const { dailyMean, dates } = _dailyHumidData;
    const labels = dates.map(fmtDayLabel);
    return nuggtManifest(
      {
        title: `Daily Humidity${loc}`.slice(0, 200),
        description: 'Mean daily relative humidity',
        type: 'bar',
        tags: ['weather', 'humidity'],
      },
      {
        labels,
        datasets: [{ name: 'Humidity (%)', data: nuggtSeries(dailyMean) }],
      }
    );
  }

  if (chartId === 'rain' && _rainData && ytdData) {
    const { labels, curV, avgV, fcV, thisYear, fcstDates } = _rainData;
    const rainUnit = imp ? 'in' : 'mm';
    const histLabels = labels.map(mmdd => {
      const [mo, dy] = mmdd.split('-');
      return new Date(thisYear, +mo - 1, +dy).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    });
    const fcLabels = (fcstDates || []).map(fmtDayLabel);
    const allLabels = [...histLabels, ...fcLabels];
    const lastAvg = avgV[avgV.length - 1] ?? 0;
    const curData = fcV?.length ? [...curV, ...fcV] : [...curV];
    const avgData = fcV?.length
      ? [...avgV, ...Array(fcV.length).fill(lastAvg)]
      : [...avgV];
    return nuggtManifest(
      {
        title: `Year-to-Date Rainfall${loc}`.slice(0, 200),
        description: `${thisYear} cumulative rainfall vs historical average`,
        type: 'line',
        tags: ['weather', 'rainfall'],
      },
      {
        labels: allLabels,
        datasets: [
          { name: `${thisYear} (${rainUnit})`, data: nuggtSeries(curData) },
          { name: `Historical avg (${rainUnit})`, data: nuggtSeries(avgData) },
        ],
      }
    );
  }

  if (chartId === 'climate' && _climateData && climatologyData) {
    const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const rows = _climateData.data;
    const rainUnit = imp ? 'in' : 'mm';
    return nuggtManifest(
      {
        title: `Climate Overview${loc}`.slice(0, 200),
        description: `Monthly normals ${climatologyData.yearStart}–${climatologyData.yearEnd}`,
        type: 'dual_axis',
        tags: ['weather', 'climate'],
      },
      {
        labels: MON,
        datasets: [
          { name: `Avg high (${u})`, data: nuggtSeries(rows.map(d => d.tMax != null ? nT(d.tMax) : null)), yAxis: 'left' },
          { name: `Avg low (${u})`, data: nuggtSeries(rows.map(d => d.tMin != null ? nT(d.tMin) : null)), yAxis: 'left' },
          { name: `Avg rainfall (${rainUnit})`, data: nuggtSeries(rows.map(d => d.rain != null ? nP(d.rain) : null)), yAxis: 'right' },
        ],
        leftAxisLabel: `Temperature (${u})`,
        rightAxisLabel: `Rainfall (${rainUnit})`,
      }
    );
  }

  return null;
}

function nuggtBtn(chartId) {
  return `<button type="button" class="send-to-nuggt" data-nuggt-chart="${chartId}" title="Open this chart in Nuggt to edit and publish">Send to Nuggt</button>`;
}

async function sendToNuggt(chartId, btn) {
  const manifest = buildNuggtManifest(chartId);
  if (!manifest) {
    alert('Chart data is not ready yet. Please wait for loading to finish.');
    return;
  }

  const key = nuggtPublishKey();

  const label = btn?.textContent || 'Send to Nuggt';
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Sending…';
  }

  try {
    const importUrl = await nuggtPublish(manifest, key);
    window.open(importUrl, '_blank', 'noopener,noreferrer');
  } catch (err) {
    console.error('Send to Nuggt failed:', err);
    alert(nuggtErrorMessage(err, err.status || 0, key));
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = label;
    }
  }
}
