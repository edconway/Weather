// ── Send to Nuggt — manifest builders & publish ─────────

const NUGGT_SCHEMA = 'https://nuggt.com/schemas/chart-import/v1';

function nuggtApiBase() {
  return window.NUGGT_API_BASE || 'https://nuggt.com';
}

function nuggtPublishKey() {
  return window.NUGGT_PUBLISH_KEY || localStorage.getItem('nuggt-publish-key') || '';
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
  const hr = +iso.slice(11, 13);
  if (hr === 0) return 'Midnight';
  if (hr === 12) return 'Noon';
  return hr < 12 ? `${hr}am` : `${hr - 12}pm`;
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

  const headers = { 'Content-Type': 'application/json' };
  const key = nuggtPublishKey();
  if (key) headers.Authorization = `Bearer ${key}`;

  const label = btn?.textContent || 'Send to Nuggt';
  if (btn) {
    btn.disabled = true;
    btn.textContent = 'Sending…';
  }

  try {
    const res = await fetch(`${nuggtApiBase()}/api/weather-manifest`, {
      method: 'POST',
      headers,
      body: JSON.stringify(manifest),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(detail || `Request failed (${res.status})`);
    }
    const { import_url: importUrl } = await res.json();
    if (!importUrl) throw new Error('No import URL returned');
    window.open(importUrl, '_blank', 'noopener,noreferrer');
  } catch (err) {
    console.error('Send to Nuggt failed:', err);
    alert(
      key
        ? 'Could not send this chart to Nuggt. Please try again.'
        : 'Could not send to Nuggt. A publish key may be required — see nuggt-config.example.js.'
    );
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = label;
    }
  }
}
