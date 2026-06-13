const WMO={
  0:{l:'Clear Sky',i:'☀️'},1:{l:'Mainly Clear',i:'🌤️'},2:{l:'Partly Cloudy',i:'⛅'},3:{l:'Overcast',i:'☁️'},
  45:{l:'Foggy',i:'🌫️'},48:{l:'Icy Fog',i:'🌫️'},
  51:{l:'Light Drizzle',i:'🌦️'},53:{l:'Drizzle',i:'🌦️'},55:{l:'Heavy Drizzle',i:'🌧️'},
  56:{l:'Light Freezing Drizzle',i:'🌨️'},57:{l:'Freezing Drizzle',i:'🌨️'},
  61:{l:'Light Rain',i:'🌧️'},63:{l:'Rain',i:'🌧️'},65:{l:'Heavy Rain',i:'🌧️'},
  66:{l:'Light Freezing Rain',i:'🌨️'},67:{l:'Freezing Rain',i:'🌨️'},
  71:{l:'Light Snow',i:'🌨️'},73:{l:'Snow',i:'❄️'},75:{l:'Heavy Snow',i:'❄️'},77:{l:'Snow Grains',i:'🌨️'},
  80:{l:'Light Showers',i:'🌦️'},81:{l:'Showers',i:'🌧️'},82:{l:'Heavy Showers',i:'⛈️'},
  85:{l:'Snow Showers',i:'🌨️'},86:{l:'Heavy Snow Showers',i:'🌨️'},
  95:{l:'Thunderstorm',i:'⛈️'},96:{l:'Thunderstorm & Hail',i:'⛈️'},99:{l:'Thunderstorm & Heavy Hail',i:'⛈️'}
};
function wmo(c){return WMO[c]||WMO[Math.floor(c/10)*10]||{l:'Unknown',i:'🌡️'}}

// ── Preferences & utilities ────────────────────────────
const PREFS_KEY = 'weather-prefs';

function escapeHtml(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function padDate(n) { return String(n).padStart(2, '0'); }

function localDateStr(d = new Date()) {
  return `${d.getFullYear()}-${padDate(d.getMonth() + 1)}-${padDate(d.getDate())}`;
}

function loadPrefs() {
  try { return JSON.parse(localStorage.getItem(PREFS_KEY)) || {}; }
  catch { return {}; }
}

function savePrefs(partial) {
  try {
    const prefs = { ...loadPrefs(), ...partial };
    localStorage.setItem(PREFS_KEY, JSON.stringify(prefs));
  } catch {}
}

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  savePrefs({ theme });
}

function themeBtnLabel() {
  const t = document.documentElement.dataset.theme || 'auto';
  return t === 'dark' ? '☀️ Light' : t === 'light' ? '🌓 Auto' : '🌙 Dark';
}

function toggleTheme() {
  const cur = document.documentElement.dataset.theme || 'auto';
  const next = cur === 'dark' ? 'light' : cur === 'light' ? 'auto' : 'dark';
  if (next === 'auto') {
    delete document.documentElement.dataset.theme;
    savePrefs({ theme: 'auto' });
  } else {
    applyTheme(next);
  }
  renderHeader();
}

let chartFocusIdx = -1;
let _focusedChart = null;


// ── State ──────────────────────────────────────────────
const _prefs=loadPrefs();
let imp=!!_prefs.imp, fcData, histData, geoName;
let searching=false, searchResults=[], searchFocusIdx=-1, searchTimer=null;
// Source tracking
let myLat=null, myLon=null, myName=null;       // GPS location
let customLat=_prefs.customLat??null, customLon=_prefs.customLon??null, customName=_prefs.customName??null; // searched location
let activeSource=_prefs.activeSource||'geo'; // 'geo' | 'custom'
let ytdData=null, hourlyHistData=null, hourlyRainHistData=null, dailyRainHistData=null, climatologyData=null, hourlyHumidData=null;
let _tempData=null,_rainData=null,_hourlyData=null,_hourlyRainData=null,_dailyRainData=null,_climateData=null,_hourlyHumidData=null,_dailyHumidData=null;

// ── Unit helpers ───────────────────────────────────────
const c2f=c=>c*9/5+32, k2m=k=>k*.621371, mm2in=m=>m*.0393701;
function fT(c){if(c==null)return'—';return imp?`${Math.round(c2f(c))}°F`:`${Math.round(c)}°C`}
function fTn(c){if(c==null)return'—';return imp?Math.round(c2f(c)):Math.round(c)}
function fW(k){if(k==null)return'—';return imp?`${Math.round(k2m(k))} mph`:`${Math.round(k)} km/h`}
function fP(m){if(m==null)return'—';return imp?`${mm2in(m).toFixed(2)}"`:`${(+m).toFixed(1)} mm`}
function nT(c){return imp?c2f(c):c}
function nW(k){return imp?k2m(k):k}
function nP(m){return imp?mm2in(m):m}
function uT(){return imp?'°F':'°C'}
function fDate(d){return d.toLocaleDateString('en-US',{weekday:'long',year:'numeric',month:'long',day:'numeric'})}
function fDay(s){return new Date(s+'T12:00:00').toLocaleDateString('en-US',{weekday:'short'})}
function avg(arr,idx){
  const v=(idx?idx.map(i=>arr[i]):arr).filter(x=>x!=null&&!isNaN(x));
  return v.length?v.reduce((a,b)=>a+b,0)/v.length:null;
}

// ── Render header ──────────────────────────────────────
function renderHeader(){
  const el=document.getElementById('app-hdr');
  if(!el) return;
  if(searching){
    el.innerHTML=`<div class="hdr searching">
      <div class="search-bar">
        ${ICON_SEARCH}
        <input id="srch" type="text" placeholder="Search city or location…"
          autocomplete="off" spellcheck="false">
        <button id="btn-clear" class="search-clear" title="Clear">✕</button>
      </div>
      <button id="btn-cancel" class="cancel-btn">Cancel</button>
    </div>`;
    const inp=document.getElementById('srch');
    if(inp) requestAnimationFrame(()=>inp.focus());
  } else {
    const showToggle=myLat!=null&&customLat!=null;
    const shortCustom=customName?customName.split(',')[0].trim():'Custom';
    el.innerHTML=`<div class="hdr">
      <div id="btn-loc" class="loc" role="button" tabindex="0" title="Search for a location">
        <span class="loc-icon">📍</span>
        <div class="loc-text">
          <h1 class="loc-name">${escapeHtml(geoName)||'—'}</h1>
          <p class="loc-date">${fDate(new Date())}</p>
        </div>
        <span class="loc-search-hint">${ICON_SEARCH}</span>
      </div>
      <div class="hdr-actions">
        <button id="btn-theme" class="toggle" title="Toggle theme">${themeBtnLabel()}</button>
        <button id="btn-unit" class="toggle">Switch to ${imp?'°C':'°F'}</button>
      </div>
    </div>${showToggle?`
    <div class="src-toggle">
      <button id="btn-geo" class="src-btn${activeSource==='geo'?' active':''}">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="${activeSource==='geo'?'currentColor':'none'}" stroke="currentColor" stroke-width="2.5"><circle cx="12" cy="10" r="3"/><path d="M12 2C7.6 2 4 5.6 4 10c0 5.4 8 12 8 12s8-6.6 8-12c0-4.4-3.6-8-8-8z"/></svg>
        My Location
      </button>
      <button id="btn-custom" class="src-btn${activeSource==='custom'?' active':''}">🏙️ ${escapeHtml(shortCustom)}</button>
    </div>`:''}`;
  }
}




// ── Render weather content ─────────────────────────────
function uvLabel(u){
  if(u==null)return'—';
  return`${u.toFixed(1)} ${u<=2?'Low':u<=5?'Moderate':u<=7?'High':u<=10?'Very High':'Extreme'}`;
}
function glowColor(code){
  if(code===0||code===1)return'rgba(255,210,80,.45)';
  if(code===2||code===3)return'rgba(140,170,220,.3)';
  if(code>=95)return'rgba(120,80,255,.4)';
  if(code>=71)return'rgba(190,225,255,.3)';
  if(code>=51)return'rgba(60,140,255,.35)';
  return'rgba(102,126,234,.35)';
}
function barHtml(histVal,fcstVal,fmtFn,numFn){
  const h=histVal!=null?numFn(histVal):0;
  const f=fcstVal!=null?numFn(fcstVal):0;
  const mx=Math.max(h,f,.001);
  const hw=Math.round(h/mx*100), fw=Math.round(f/mx*100);
  let delta='';
  if(histVal!=null&&fcstVal!=null){
    const diff=numFn(fcstVal)-numFn(histVal);
    if(Math.abs(diff)<0.4) delta=`<p class="delta delta-eq">≈ near historical average</p>`;
    else{
      const sign=diff>0?'+':'−', abs=Math.abs(diff), val=abs<1?abs.toFixed(1):Math.round(abs);
      delta=`<p class="delta ${diff>0?'delta-hi':'delta-lo'}">${sign}${val} vs historical avg</p>`;
    }
  }
  return`<div class="bar-row">
    <span class="bar-tag">Hist.</span>
    <div class="bar-track"><div class="bar-fill bar-h" data-w="${hw}%"></div></div>
    <span class="bar-num">${histVal!=null?fmtFn(histVal):'—'}</span>
  </div>
  <div class="bar-row">
    <span class="bar-tag">Forecast</span>
    <div class="bar-track"><div class="bar-fill bar-f" data-w="${fw}%"></div></div>
    <span class="bar-num">${fcstVal!=null?fmtFn(fcstVal):'—'}</span>
  </div>${delta}`;
}

function renderContent(){
  if(!fcData||!histData) return;
  const d=fcData.daily, h=histData;
  // With past_days:7 the array starts 7 days ago — find today's index
  const _todayStr=localDateStr();
  const t0=Math.max(0,d.time.findIndex(t=>t===_todayStr));
  const w0=wmo(d.weather_code[t0]);
  const tMax0=d.temperature_2m_max[t0], tMin0=d.temperature_2m_min[t0];
  // Current hour from hourly data
  const _pad=n=>String(n).padStart(2,'0');
  const _nowHourStr=`${_todayStr}T${_pad(new Date().getHours())}:00`;
  const _nowHourIdx=Math.max(0,(fcData.hourly?.time||[]).findIndex(t=>t>=_nowHourStr));
  const tNow=fcData.hourly?.temperature_2m?.[_nowHourIdx]??tMax0;
  const app0=fcData.hourly?.apparent_temperature?.[_nowHourIdx]??d.apparent_temperature_max[t0];
  const pop0=d.precipitation_probability_max[t0];
  const wind0=d.wind_speed_10m_max[t0];
  const uv0=d.uv_index_max[t0];
  const ytdYear=ytdData?.thisYear||new Date().getFullYear();
  const ytdStart=ytdData?.startYear||2000;
  const ytdThrough=ytdData?.latestDate?ytdData.latestDate.slice(5).replace('-','/'):'';
  // Short location name (city only, before first comma)
  const _loc=geoName?.split(',')[0]?.trim()||'';
  const _locFor=_loc?` for ${_loc}`:'';
  // Chart subtitles
  const subHourly=`Hourly temperature${_locFor} · actual & forecast vs ${hourlyHistData?`${hourlyHistData.yearStart}–${hourlyHistData.yearEnd} avg`:'historical avg'}`;
  const subDaily=`14-day high/low${_locFor} · vs 7-day rolling avg ${h.histYearStart}–${h.histYearEnd}`;
  const _thisYr=new Date().getFullYear();
  const subHourlyRain=`Hourly precipitation${_locFor}${hourlyRainHistData?` · vs ${hourlyRainHistData.yearStart}–${hourlyRainHistData.yearEnd} avg`:''}`;
  const subDailyRain=`14-day precipitation${_locFor} · past 7 days actual, next 7 days forecast`;
  const subHourlyHumid=`Hourly humidity${_locFor}${hourlyHumidData?` · vs ${hourlyHumidData.yearStart}–${hourlyHumidData.yearEnd} avg`:''}`;
  const subDailyHumid=`Daily humidity${_locFor} · yesterday + next 3 days${hourlyHumidData?` · vs ${hourlyHumidData.yearStart}–${hourlyHumidData.yearEnd} seasonal avg`:''}`;

  const subRain=ytdData
    ?`Cumulative rainfall${_locFor} · ${ytdYear} actual & 7-day forecast vs ${ytdStart}–${ytdYear-1} avg${ytdThrough?' · through '+ytdThrough:''}`
    :`Cumulative rainfall${_locFor}`;

  // ── Hero anomaly context ──────────────────────────────
  const _histEntry=histData?.dailyAvg?.[7];
  const _tempAnomaly=(()=>{
    if(!_histEntry?.tMax||!_histEntry?.tMin) return '';
    const fMean=(tMax0+tMin0)/2, hMean=(_histEntry.tMax+_histEntry.tMin)/2;
    const delta=fMean-hMean, abs=Math.abs(delta);
    if(abs<1) return 'Near normal';
    const disp=imp?Math.round(abs*9/5):Math.round(abs);
    return `${disp}${uT()} ${delta>0?'warmer':'colder'} than normal`;
  })();
  const _rainAnomaly=(()=>{
    if(!dailyRainHistData?.[0]) return '';
    const dr=dailyRainHistData[0];
    if(dr.forecastMm<0.1) return dr.histMeanMm>=1?'Drier than normal':'Dry day expected';
    if(dr.p90Mm>0&&dr.forecastMm>=dr.p90Mm) return 'Unusually wet';
    if(dr.forecastMm>dr.histMeanMm*1.5&&dr.forecastMm-dr.histMeanMm>=1) return 'Wetter than normal';
    if(dr.histMeanMm>0.5&&dr.forecastMm<dr.histMeanMm*0.5) return 'Drier than normal';
    return 'Near normal rainfall';
  })();

  document.getElementById('content').innerHTML=`
  <section class="hero fu" style="--glow:${glowColor(d.weather_code[t0])}">
    <div class="hero-top">
      <div class="hero-left">
        <div class="hero-temp">${fTn(tNow)}<sup>${uT()}</sup></div>
        <div class="hero-cond">${w0.l}</div>
        <div class="hero-range">
          ${app0!=null?`<span style="color:var(--subtle)">Feels like ${fT(app0)}</span><span style="color:var(--subtle)"> · </span>`:''}
          <span class="hi">↑${fT(tMax0)}</span>
          <span style="color:var(--subtle)"> / </span>
          <span class="lo">↓${fT(tMin0)}</span>
        </div>
      </div>
      ${(_tempAnomaly||_rainAnomaly)?`<div class="hero-anomaly-col">
        ${_tempAnomaly?`<p class="hero-anomaly">${_tempAnomaly}</p>`:''}
        ${_rainAnomaly?`<p class="hero-anomaly">${_rainAnomaly}</p>`:''}
      </div>`:''}
      <div class="hero-icon">${w0.i}</div>
    </div>
    <div class="hero-stats">
      <div class="stat"><span class="stat-ico">🌧️</span><span class="stat-lbl">Rain chance</span><span class="stat-val">${pop0!=null?pop0+'%':'—'}</span></div>
      <div class="stat"><span class="stat-ico">💨</span><span class="stat-lbl">Wind</span><span class="stat-val">${fW(wind0)}</span></div>
      <div class="stat"><span class="stat-ico">🌞</span><span class="stat-lbl">UV Index</span><span class="stat-val">${uvLabel(uv0)}</span></div>
    </div>
  </section>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">48-Hour Temperature</span>
      <p class="sec-sub">${subHourly}</p>
    </div>
    ${makeHourlyTempChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">14-Day Temperature</span>
      <p class="sec-sub">${subDaily}</p>
    </div>
    ${makeTempChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">48-Hour Rainfall</span>
      <p class="sec-sub">${subHourlyRain}</p>
    </div>
    ${makeHourlyRainChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">14-Day Rainfall</span>
      <p class="sec-sub">${subDailyRain}</p>
    </div>
    ${makeDailyRainChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">48-Hour Humidity</span>
      <p class="sec-sub">${subHourlyHumid}</p>
    </div>
    ${makeHourlyHumidChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">Daily Humidity</span>
      <p class="sec-sub">${subDailyHumid}</p>
    </div>
    ${makeDailyHumidChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">Year-to-Date Rainfall</span>
      <p class="sec-sub">${subRain}</p>
    </div>
    ${makeRainYTDChart()}
  </div>

  <div class="chart-card fu">
    <div class="sec-hdr" style="margin-bottom:6px">
      <span class="sec-ttl">Climate Overview</span>
      <p class="sec-sub">${climatologyData?`Avg monthly high/low °${uT().slice(1)} (lines) & total rainfall (bars)${_locFor} · ${climatologyData.yearStart}–${climatologyData.yearEnd}`:`Climate normals${_locFor}`}</p>
    </div>
    ${makeClimateChart()}
  </div>

  <footer class="footer fu">
    <p>Forecast & historical data from <a href="https://open-meteo.com" target="_blank" rel="noopener">Open-Meteo</a> · Geocoding by <a href="https://nominatim.openstreetmap.org" target="_blank" rel="noopener">Nominatim / OSM</a></p>
  </footer>`;
}

function render(){
  renderHeader();
  renderContent();
  document.getElementById('main').classList.remove('hidden');
  document.getElementById('loading').classList.add('hidden');
  document.getElementById('error').classList.add('hidden');
}

function toggleUnit(){imp=!imp; savePrefs({imp}); renderHeader(); renderContent();}

// ── API calls ──────────────────────────────────────────
// Throttled archive fetcher — Open-Meteo rate-limits bursts (HTTP 429),
// so cap concurrency and retry with backoff. Keeps load light & reliable.
const _archiveQueue=[]; let _archiveActive=0; const ARCHIVE_MAX=3;
function archiveFetch(url){
  return new Promise((resolve,reject)=>{
    _archiveQueue.push({url,resolve,reject,tries:0});
    _drainArchive();
  });
}
function _drainArchive(){
  while(_archiveActive<ARCHIVE_MAX && _archiveQueue.length){
    const job=_archiveQueue.shift();
    _archiveActive++;
    fetch(job.url).then(r=>{
      if(r.status===429 && job.tries<4){
        job.tries++;
        const delay=400*Math.pow(2,job.tries); // 800, 1600, 3200, 6400ms
        setTimeout(()=>{_archiveQueue.unshift(job);_drainArchive();},delay);
      } else {
        job.resolve(r);
      }
    }).catch(job.reject).finally(()=>{
      _archiveActive--;
      _drainArchive();
    });
  }
}

async function getPos(){
  return new Promise((res,rej)=>{
    if(!navigator.geolocation)return rej(new Error('Geolocation not supported by this browser.'));
    navigator.geolocation.getCurrentPosition(res,e=>{
      rej(new Error(
        e.code===e.PERMISSION_DENIED?'Location access denied. Please allow location in your browser settings.':
        e.code===e.POSITION_UNAVAILABLE?'Location unavailable.':'Location request timed out.'
      ));
    },{timeout:15000,maximumAge:300000});
  });
}

async function geocode(lat,lon){
  try{
    const r=await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}`,
      {headers:{'Accept-Language':'en','User-Agent':'WeatherApp/1.0 (https://github.com/edconway/Weather)'}});
    if(!r.ok) throw 0;
    const d=await r.json(), a=d.address||{};
    const city=a.city||a.town||a.village||a.municipality||a.county||'';
    const region=a.state||a.country||'';
    return city?`${city}${region?', '+region:''}`:`${lat.toFixed(2)}, ${lon.toFixed(2)}`;
  }catch{return`${lat.toFixed(2)}, ${lon.toFixed(2)}`}
}

async function getForecast(lat,lon){
  const p=new URLSearchParams({
    latitude:lat,longitude:lon,timezone:'auto',forecast_days:7,past_days:7,
    daily:'weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,uv_index_max',
    past_hours:24,forecast_hours:48,
    hourly:'temperature_2m,apparent_temperature,precipitation,precipitation_probability,rain,showers,snowfall,weather_code,relative_humidity_2m'
  });
  const r=await fetch(`https://api.open-meteo.com/v1/forecast?${p}`);
  if(!r.ok) throw new Error('Forecast API error.');
  return r.json();
}

async function getRainYTD(lat,lon){
  const now=new Date();
  const thisYear=now.getFullYear();
  const pad=n=>String(n).padStart(2,'0');
  const todayStr=`${thisYear}-${pad(now.getMonth()+1)}-${pad(now.getDate())}`;
  const startYear=2000;
  const p=new URLSearchParams({
    latitude:lat,longitude:lon,timezone:'auto',
    start_date:`${startYear}-01-01`,end_date:todayStr,
    daily:'precipitation_sum'
  });
  const r=await archiveFetch(`https://archive-api.open-meteo.com/v1/archive?${p}`);
  if(!r.ok) throw new Error('YTD API error.');
  const data=await r.json();
  // Group by year -> MM-DD -> precip value
  const byYear={};
  data.daily.time.forEach((t,i)=>{
    const yr=+t.slice(0,4), mmdd=t.slice(5);
    if(!byYear[yr]) byYear[yr]={};
    byYear[yr][mmdd]=data.daily.precipitation_sum[i]??0;
  });
  // Build MM-DD labels from Jan 1 to today
  const labels=[];
  const d=new Date(thisYear,0,1);
  while(d<=now){
    labels.push(`${pad(d.getMonth()+1)}-${pad(d.getDate())}`);
    d.setDate(d.getDate()+1);
  }
  // Current year running cumulative
  const curData=byYear[thisYear]||{};
  let s=0;
  const cumCurrentYear=labels.map(mmdd=>{s+=curData[mmdd]||0;return s;});
  // Historical average running cumulative
  const histYears=Object.keys(byYear).map(Number).filter(y=>y>=startYear&&y<thisYear);
  const histCumByYear={};
  histYears.forEach(y=>{
    let hs=0;
    histCumByYear[y]=labels.map(mmdd=>{hs+=byYear[y][mmdd]||0;return hs;});
  });
  const cumHistAvg=labels.map((_,i)=>{
    const vals=histYears.map(y=>histCumByYear[y][i]);
    return vals.reduce((a,b)=>a+b,0)/(vals.length||1);
  });
  // latestDate = last date that actually has archive data (≤ today)
  const latestDate=data.daily.time.filter(t=>t<=todayStr).pop()||todayStr;
  // Build 7-day historical avg extension for the forecast window.
  // Uses the extended byYear data (those future MM-DD values now exist for historical years).
  const latestDateObj=new Date(latestDate+'T12:00:00');
  let extCum=cumHistAvg[cumHistAvg.length-1];
  const cumHistAvgExt=[];
  for(let k=1;k<=7;k++){
    const tmp=new Date(latestDateObj); tmp.setDate(tmp.getDate()+k);
    if(tmp.getFullYear()>thisYear) break;
    const mmdd=`${pad(tmp.getMonth()+1)}-${pad(tmp.getDate())}`;
    const vals=histYears.map(y=>byYear[y]?.[mmdd]??0);
    extCum+=vals.reduce((a,b)=>a+b,0)/(vals.length||1);
    cumHistAvgExt.push(extCum);
  }
  return{labels,cumCurrentYear,cumHistAvg,cumHistAvgExt,thisYear,startYear,histYears:histYears.length,latestDate};
}

// Merged hourly normals — fetches BOTH temperature & precipitation per request
// (5 requests total, down from 10). Returns temp-shaped and rain-shaped objects.
async function getHourlyNormals(lat,lon){
  const now=new Date();
  const pad=n=>String(n).padStart(2,'0');
  const thisYear=now.getFullYear();
  const mo=now.getMonth(), dy=now.getDate();
  const fetches=[];
  for(let i=1;i<=5;i++){
    const yr=thisYear-i;
    const s=new Date(yr,mo,dy-7), e=new Date(yr,mo,dy+7);
    const p=new URLSearchParams({
      latitude:lat,longitude:lon,timezone:'auto',
      start_date:`${s.getFullYear()}-${pad(s.getMonth()+1)}-${pad(s.getDate())}`,
      end_date:`${e.getFullYear()}-${pad(e.getMonth()+1)}-${pad(e.getDate())}`,
      hourly:'temperature_2m,precipitation,relative_humidity_2m'
    });
    fetches.push(archiveFetch(`https://archive-api.open-meteo.com/v1/archive?${p}`)
      .then(r=>r.ok?r.json():null).catch(()=>null));
  }
  const results=await Promise.all(fetches);
  // Temperature accumulators
  const tSums=new Array(24).fill(0), tCounts=new Array(24).fill(0);
  // Precip accumulators
  const rSums=new Array(24).fill(0), rCounts=new Array(24).fill(0), wetCounts=new Array(24).fill(0);
  const rVals=Array.from({length:24},()=>[]);
  // Humidity accumulators
  const hSums=new Array(24).fill(0), hCounts=new Array(24).fill(0);
  results.forEach(data=>{
    if(!data?.hourly?.time) return;
    data.hourly.time.forEach((t,i)=>{
      const hr=+t.slice(11,13);
      const tv=data.hourly.temperature_2m?.[i];
      if(tv!=null){tSums[hr]+=tv;tCounts[hr]++;}
      const rv=data.hourly.precipitation?.[i];
      if(rv!=null){rSums[hr]+=rv;rCounts[hr]++;if(rv>=0.1)wetCounts[hr]++;rVals[hr].push(rv);}
      const hv=data.hourly.relative_humidity_2m?.[i];
      if(hv!=null){hSums[hr]+=hv;hCounts[hr]++;}
    });
  });
  const temp={avgByHour:tSums.map((s,h)=>tCounts[h]?s/tCounts[h]:null),yearStart:thisYear-5,yearEnd:thisYear-1};
  const rain={
    avgByHour:rSums.map((s,h)=>rCounts[h]?s/rCounts[h]:0),
    wetHourProbabilityByHour:rCounts.map((c,h)=>c?wetCounts[h]/c:0),
    p90ByHour:rVals.map(vals=>{if(!vals.length)return 0;const s=[...vals].sort((a,b)=>a-b);return s[Math.floor(s.length*0.9)]??0;}),
    yearStart:thisYear-5,yearEnd:thisYear-1
  };
  const humidity={avgByHour:hSums.map((s,h)=>hCounts[h]?s/hCounts[h]:null),yearStart:thisYear-5,yearEnd:thisYear-1};
  return{temp,rain,humidity};
}



function classifyRain(forecastMm,histMeanMm,p90Mm){
  if(forecastMm<0.1) return histMeanMm>=1?{text:'Dry',color:'#2980b9'}:{text:'Dry',color:'#9ba3ae'};
  if(p90Mm>0&&forecastMm>=p90Mm) return{text:'Heavy',color:'#c0392b'};
  if(forecastMm>histMeanMm*1.5&&forecastMm-histMeanMm>=1) return{text:'Wetter',color:'#2980b9'};
  if(histMeanMm>0.5&&forecastMm<histMeanMm*0.5) return{text:'Drier',color:'#9ba3ae'};
  return{text:'Near avg',color:'#6c7079'};
}





// ── Humidity charts ────────────────────────────────────




// ── Climatology ────────────────────────────────────────
async function getClimatology(lat,lon){
  // ONE archive request fetches 10 years of daily temp+precip. From this single
  // dataset we derive: monthly climate normals, the 14-day temp band, and daily
  // rain normals — avoiding ~10 extra requests that previously triggered rate limits.
  const thisYear=new Date().getFullYear();
  const startYear=thisYear-10;
  const p=new URLSearchParams({
    latitude:lat,longitude:lon,timezone:'auto',
    start_date:`${startYear}-01-01`,
    end_date:`${thisYear-1}-12-31`,
    daily:'temperature_2m_max,temperature_2m_min,precipitation_sum'
  });
  const r=await archiveFetch(`https://archive-api.open-meteo.com/v1/archive?${p}`);
  if(!r.ok) throw new Error('Climate fetch failed');
  const data=await r.json();
  if(!data.daily?.time) return null;
  const arrAvg=arr=>arr.length?arr.reduce((a,b)=>a+b,0)/arr.length:null;
  // Monthly aggregation for the climate chart
  const byMonthYear={};
  // Per-calendar-day lookups (MM-DD) for deriving rolling temp & rain normals
  const byMMDD={}; // {mmdd:{maxes:[],mins:[],rains:[]}}
  data.daily.time.forEach((t,i)=>{
    const mx=data.daily.temperature_2m_max[i];
    const mn=data.daily.temperature_2m_min[i];
    const rn=data.daily.precipitation_sum[i];
    const mKey=t.slice(0,7), mmdd=t.slice(5);
    if(!byMonthYear[mKey]) byMonthYear[mKey]={tMax:[],tMin:[],rain:0};
    if(mx!=null) byMonthYear[mKey].tMax.push(mx);
    if(mn!=null) byMonthYear[mKey].tMin.push(mn);
    if(rn!=null) byMonthYear[mKey].rain+=rn;
    if(!byMMDD[mmdd]) byMMDD[mmdd]={maxes:[],mins:[],rains:[]};
    if(mx!=null) byMMDD[mmdd].maxes.push(mx);
    if(mn!=null) byMMDD[mmdd].mins.push(mn);
    if(rn!=null) byMMDD[mmdd].rains.push(rn);
  });
  const byMonth=Array.from({length:12},()=>({tMax:[],tMin:[],rain:[]}));
  Object.entries(byMonthYear).forEach(([key,v])=>{
    const mo=+key.slice(5,7)-1;
    if(v.tMax.length) byMonth[mo].tMax.push(arrAvg(v.tMax));
    if(v.tMin.length) byMonth[mo].tMin.push(arrAvg(v.tMin));
    byMonth[mo].rain.push(v.rain);
  });
  return{
    months:byMonth.map(m=>({tMax:arrAvg(m.tMax),tMin:arrAvg(m.tMin),rain:arrAvg(m.rain)})),
    byMMDD,
    yearStart:startYear,yearEnd:thisYear-1
  };
}

// Calendar-day distance between two MM-DD strings, year-wrap aware
function _mmddDist(a,b){
  const da=new Date(2020,+a.slice(0,2)-1,+a.slice(3));
  const db=new Date(2020,+b.slice(0,2)-1,+b.slice(3));
  let d=Math.round((da-db)/86400000);
  if(d>182) d-=365; if(d<-182) d+=365;
  return Math.abs(d);
}

// Derive 14-day temp band (today-7 … today+6) from climatology's daily lookups.
// Replaces the old getHistorical (which fired 5 separate archive requests).
function deriveTempBand(climate){
  if(!climate?.byMMDD) return null;
  const now=new Date(), pad=n=>String(n).padStart(2,'0');
  const thisYear=now.getFullYear(), mo=now.getMonth(), dy=now.getDate();
  const arrAvg=arr=>arr.length?arr.reduce((a,b)=>a+b,0)/arr.length:null;
  const entries=Object.entries(climate.byMMDD);
  const dailyAvg=[];
  for(let i=-7;i<=6;i++){
    const tmp=new Date(thisYear,mo,dy+i);
    const mmdd=`${pad(tmp.getMonth()+1)}-${pad(tmp.getDate())}`;
    const maxes=[],mins=[];
    entries.forEach(([am,v])=>{
      if(_mmddDist(mmdd,am)<=3){maxes.push(...v.maxes);mins.push(...v.mins);}
    });
    dailyAvg.push({tMax:arrAvg(maxes),tMin:arrAvg(mins)});
  }
  return{
    dailyAvg,
    tMax:dailyAvg[7]?.tMax??null, tMin:dailyAvg[7]?.tMin??null,
    precip:null, wind:null, nextMonth:null,
    month:now.toLocaleString('en-US',{month:'long'}),
    histYearStart:climate.yearStart, histYearEnd:climate.yearEnd
  };
}

// Derive per-forecast-day rain normals from climatology's daily lookups.
// Replaces the old getDailyRainHistorical (which fired 5 separate archive requests).
function deriveDailyRain(climate){
  if(!climate?.byMMDD||!fcData?.daily) return null;
  const t0=Math.min(7,fcData.daily.time.length-1);
  const fcDates=fcData.daily.time.slice(t0,t0+7);
  const entries=Object.entries(climate.byMMDD);
  const arrAvg=arr=>arr.length?arr.reduce((a,b)=>a+b,0)/arr.length:0;
  const arrMedian=arr=>{if(!arr.length)return 0;const s=[...arr].sort((a,b)=>a-b),m=Math.floor(s.length/2);return s.length%2?s[m]:(s[m-1]+s[m])/2;};
  const arrP90=arr=>{if(!arr.length)return 0;const s=[...arr].sort((a,b)=>a-b);return s[Math.floor(s.length*0.9)]??0;};
  return fcDates.map((dateStr,idx)=>{
    const mmdd=dateStr.slice(5);
    const vals=[];
    entries.forEach(([am,v])=>{ if(_mmddDist(mmdd,am)<=3) vals.push(...v.rains); });
    return{
      date:dateStr,
      forecastMm:fcData.daily.precipitation_sum[t0+idx]??0,
      probabilityMax:fcData.daily.precipitation_probability_max[t0+idx]??null,
      histMeanMm:arrAvg(vals),
      histMedianMm:arrMedian(vals),
      wetDayProbability:vals.length?vals.filter(v=>v>=0.1).length/vals.length:0,
      p90Mm:arrP90(vals)
    };
  });
}



// ── UI state helpers ───────────────────────────────────
function showErr(msg){
  document.getElementById('loading').classList.add('hidden');
  document.getElementById('main').classList.add('hidden');
  document.getElementById('error').classList.remove('hidden');
  document.getElementById('err-msg').textContent=msg;
}

function setLoad(msg){
  document.getElementById('load-msg').textContent=msg;
  document.getElementById('loading').classList.remove('hidden');
  document.getElementById('main').classList.add('hidden');
  document.getElementById('error').classList.add('hidden');
}

// ── Delegated event listeners ──────────────────────────
(function(){
  // Header — one permanent listener handles all dynamic buttons
  const hdr=document.getElementById('app-hdr');
  hdr.addEventListener('click',e=>{
    const t=e.target;
    if(t.closest('#btn-loc')){openSearch();return;}
    if(t.closest('#btn-cancel')){closeSearch();return;}
    if(t.closest('#btn-clear')){clearInput();return;}
    if(t.closest('#btn-theme')){toggleTheme();return;}
    if(t.closest('#btn-unit')){toggleUnit();return;}
    if(t.closest('#btn-geo')){switchSource('geo');return;}
    if(t.closest('#btn-custom')){switchSource('custom');return;}
  });
  hdr.addEventListener('keydown',e=>{
    if(e.target.closest('#btn-loc')&&e.key==='Enter'){openSearch();return;}
    if(e.target.id==='srch') onSearchKey(e);
  });
  hdr.addEventListener('input',e=>{
    if(e.target.id==='srch') onSearchInput(e.target.value);
  });

  // Close search on outside click (ignore detached targets — they were replaced by renderHeader)
  document.addEventListener('click',e=>{
    if(!searching) return;
    if(!document.contains(e.target)) return;
    const wrap=document.querySelector('.hdr-wrap');
    if(wrap&&!wrap.contains(e.target)) closeSearch();
  });


  function chartStep(chartType, dir) {
    const dataMap = {
      temp: _tempData, rain: _rainData, hourly: _hourlyData,
      'hourly-rain': _hourlyRainData, 'daily-rain': _dailyRainData,
      'hourly-humid': _hourlyHumidData, 'daily-humid': _dailyHumidData,
      climate: _climateData
    };
    const d = dataMap[chartType];
    if (!d) return;
    const n = d.n ?? d.totalN ?? 12;
    chartFocusIdx = Math.max(0, Math.min(n - 1, chartFocusIdx + dir));
    const svg = _focusedChart;
    if (!svg) return;
    const vb = svg.viewBox.baseVal;
    const pL = d.pL ?? 46;
    const cW = d.cW ?? (vb.width - pL - 14);
    const slotW = d.slotW;
    let svgX;
    if (slotW) svgX = pL + (chartFocusIdx + 0.5) * slotW;
    else svgX = pL + (chartFocusIdx / Math.max(n - 1, 1)) * cW;
    const rect = svg.getBoundingClientRect();
    const cx = rect.left + (svgX / vb.width) * rect.width;
    const cy = rect.top + rect.height / 2;
    showTT(svgX, chartType, cx, cy);
  }

  function bindChartAccessibility() {
    document.querySelectorAll('svg[data-chart]').forEach(svg => {
      if (svg.dataset.a11yBound) return;
      svg.dataset.a11yBound = '1';
      svg.setAttribute('tabindex', '0');
      svg.setAttribute('role', 'img');
      const labels = {
        temp: '14-day temperature chart', rain: 'Year-to-date rainfall chart',
        hourly: '48-hour temperature chart', 'hourly-rain': '48-hour rainfall chart',
        'daily-rain': '14-day rainfall chart', 'hourly-humid': '48-hour humidity chart',
        'daily-humid': 'Daily humidity chart', climate: 'Climate overview chart'
      };
      svg.setAttribute('aria-label', labels[svg.dataset.chart] || 'Weather chart');
      svg.addEventListener('focus', () => {
        _focusedChart = svg;
        chartFocusIdx = 0;
        chartStep(svg.dataset.chart, 0);
      });
      svg.addEventListener('blur', () => { _focusedChart = null; hideTT(); });
      svg.addEventListener('keydown', e => {
        if (e.key === 'ArrowLeft') { e.preventDefault(); chartStep(svg.dataset.chart, -1); }
        else if (e.key === 'ArrowRight') { e.preventDefault(); chartStep(svg.dataset.chart, 1); }
        else if (e.key === 'Escape') { hideTT(); svg.blur(); }
      });
    });
  }

  const _origRenderContent = renderContent;
  renderContent = function() {
    _origRenderContent();
    bindChartAccessibility();
  };

  // Tooltip helpers
  function showTT(svgX,chartType,cx,cy){
    const tt=document.getElementById('tt');
    if(!tt) return;
    let html='';
    if(chartType==='temp'&&_tempData){
      const{labels,maxV,minV,dailyAvg,pL,cW,n,todayIdx}=_tempData;
      const i=Math.max(0,Math.min(n-1,Math.round((svgX-pL)/cW*(n-1))));
      const u=uT();
      const hi=maxV[i]!=null?Math.round(maxV[i]):'—';
      const lo=minV[i]!=null?Math.round(minV[i]):'—';
      const da=dailyAvg?.[i];
      const hr=da?.tMax!=null&&da?.tMin!=null?`${Math.round(nT(da.tMin))}–${Math.round(nT(da.tMax))}°`:'—';
      const isActual=todayIdx!=null&&i<todayIdx;
      const tag=isActual?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · actual</span>':'';
      const gx=(pL+i/(n-1)*cW).toFixed(1);
      document.getElementById('ttg-temp')?.setAttribute('x1',gx);
      document.getElementById('ttg-temp')?.setAttribute('x2',gx);
      document.getElementById('ttg-temp')?.setAttribute('visibility','visible');
      html=`<div class="tt-title">${labels[i]}${tag}</div>
        <div class="tt-row"><span class="tt-lbl">High</span><span class="tt-hot">${hi}${hi!=='—'?u:''}</span></div>
        <div class="tt-row"><span class="tt-lbl">Low</span><span class="tt-cold">${lo}${lo!=='—'?u:''}</span></div>
        <div class="tt-row"><span class="tt-lbl">Hist. range</span><span class="tt-muted">${hr}</span></div>`;
    } else if(chartType==='rain'&&_rainData){
      const{labels,curV,avgV,thisYear,pL,cW,n,fcV,numFc,totalN,fcstDates}=_rainData;
      const tN=totalN||n;
      const i=Math.max(0,Math.min(tN-1,Math.round((svgX-pL)/cW*(tN-1))));
      const isFc=i>=n&&fcV&&(i-n)<fcV.length;
      const fmt=v=>imp?(v<1?v.toFixed(2):v.toFixed(1))+'"':(v<10?v.toFixed(1):Math.round(v))+'mm';
      let dl;
      if(isFc){
        dl=new Date(fcstDates[i-n]+'T12:00:00').toLocaleDateString('en-US',{month:'short',day:'numeric'});
      } else {
        const mmdd=labels[i];
        dl=new Date(thisYear,+mmdd.slice(0,2)-1,+mmdd.slice(3)).toLocaleDateString('en-US',{month:'short',day:'numeric'});
      }
      const c=isFc?fcV[i-n]:curV[i];
      const a=isFc?null:avgV[i];
      const gx=(pL+i/Math.max(tN-1,1)*cW).toFixed(1);
      document.getElementById('ttg-rain')?.setAttribute('x1',gx);
      document.getElementById('ttg-rain')?.setAttribute('x2',gx);
      document.getElementById('ttg-rain')?.setAttribute('visibility','visible');
      const tag=isFc?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · forecast</span>':'';
      if(isFc){
        html=`<div class="tt-title">${dl} YTD${tag}</div>
          <div class="tt-row"><span class="tt-lbl">${thisYear} (proj.)</span><span class="tt-cur">${fmt(c)}</span></div>`;
      } else {
        const d=c-a, dc=d>0.05?'tt-pos':d<-0.05?'tt-neg':'tt-muted';
        html=`<div class="tt-title">${dl} YTD</div>
          <div class="tt-row"><span class="tt-lbl">${thisYear}</span><span class="tt-cur">${fmt(c)}</span></div>
          <div class="tt-row"><span class="tt-lbl">Hist. avg</span><span class="tt-muted">${fmt(a)}</span></div>
          <div class="tt-row"><span class="tt-lbl">Delta</span><span class="${dc}">${(d>=0?'+':'')+fmt(Math.abs(d))}</span></div>`;
      }
    } else if(chartType==='hourly'&&_hourlyData){
      const{temps,histLine,pL,cW,n,nowIdx,times}=_hourlyData;
      const i=Math.max(0,Math.min(n-1,Math.round((svgX-pL)/cW*(n-1))));
      const t=times[i];
      const hr=+t.slice(11,13);
      const isPast=i<nowIdx;
      const tag=isPast?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · actual</span>':'';
      const lbl=hr===0?'Midnight':hr===12?'Noon':hr<12?`${hr}am`:`${hr-12}pm`;
      const dateStr=new Date(t.replace('T',' ')).toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'});
      const u=uT();
      const tv=temps[i]!=null?Math.round(temps[i]):'—';
      const hv=histLine[i]!=null?Math.round(histLine[i]):'—';
      const gx=(pL+i/(n-1)*cW).toFixed(1);
      document.getElementById('ttg-hourly')?.setAttribute('x1',gx);
      document.getElementById('ttg-hourly')?.setAttribute('x2',gx);
      document.getElementById('ttg-hourly')?.setAttribute('visibility','visible');
      html=`<div class="tt-title">${dateStr} ${lbl}${tag}</div>
        <div class="tt-row"><span class="tt-lbl">Temp</span><span class="tt-hot">${tv}${tv!=='—'?u:''}</span></div>
        <div class="tt-row"><span class="tt-lbl">5-yr avg</span><span class="tt-muted">${hv}${hv!=='—'?u:''}</span></div>`;
    } else if(chartType==='hourly-rain'&&_hourlyRainData){
      const{precip,prob,pL,slotW,n,relNow,times}=_hourlyRainData;
      const i=Math.max(0,Math.min(n-1,Math.floor((svgX-pL)/slotW)));
      const t=times[i], hr=+t.slice(11,13), isPast=relNow!=null&&i<relNow;
      const tag=isPast?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · actual</span>':'';
      const lbl=hr===0?'Midnight':hr===12?'Noon':hr<12?`${hr}am`:`${hr-12}pm`;
      const dl=new Date(t.slice(0,10)+'T12:00:00').toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'});
      const fmtMm=v=>imp?(v<0.01?'—':v.toFixed(2)+'"'):(v<0.1?'—':v.toFixed(1)+'mm');
      const pv=precip[i]??0;
      const pct=prob[i]!=null?`${prob[i]}%`:'—';
      const gx=(pL+(i+0.5)*slotW).toFixed(1);
      document.getElementById('ttg-hourly-rain')?.setAttribute('x1',gx);
      document.getElementById('ttg-hourly-rain')?.setAttribute('x2',gx);
      document.getElementById('ttg-hourly-rain')?.setAttribute('visibility','visible');
      html=`<div class="tt-title">${dl} ${lbl}${tag}</div>
        <div class="tt-row"><span class="tt-lbl">Precip</span><span class="tt-cur">${fmtMm(pv)}</span></div>
        ${!isPast&&pct!=='—'?`<div class="tt-row"><span class="tt-lbl">Probability</span><span class="tt-muted">${pct}</span></div>`:''}`;
    } else if(chartType==='daily-rain'&&_dailyRainData){
      const{dates,precip,probs,pL,slotW,n,todayIdx}=_dailyRainData;
      const i=Math.max(0,Math.min(n-1,Math.floor((svgX-pL)/slotW)));
      const isPast=i<todayIdx, isToday=i===todayIdx;
      const tag=isPast?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · actual</span>':'';
      const dl=isToday?'Today':new Date(dates[i]+'T12:00:00').toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'});
      const fmtMm=v=>imp?(v<0.1?'—':v.toFixed(2)+'"'):(v<0.1?'—':v.toFixed(1)+'mm');
      const mm=precip[i]??0, prob=probs[i];
      const gx=(pL+(i+0.5)*slotW).toFixed(1);
      document.getElementById('ttg-daily-rain')?.setAttribute('x1',gx);
      document.getElementById('ttg-daily-rain')?.setAttribute('x2',gx);
      document.getElementById('ttg-daily-rain')?.setAttribute('visibility','visible');
      html=`<div class="tt-title">${dl}${tag}</div>
        <div class="tt-row"><span class="tt-lbl">${isPast?'Actual':'Forecast'}</span><span class="tt-cur">${fmtMm(mm)}</span></div>
        ${!isPast&&prob!=null?`<div class="tt-row"><span class="tt-lbl">Probability</span><span class="tt-muted">${prob}%</span></div>`:''}`;
    } else if(chartType==='hourly-humid'&&_hourlyHumidData){
      const{hVals,aVals,pL,cW,n,relNow,times}=_hourlyHumidData;
      const i=Math.max(0,Math.min(n-1,Math.round((svgX-pL)/cW*(n-1))));
      const t=times[i], hr=+t.slice(11,13), isPast=i<relNow;
      const tag=isPast?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · actual</span>':'';
      const lbl=hr===0?'Midnight':hr===12?'Noon':hr<12?`${hr}am`:`${hr-12}pm`;
      const dl=new Date(t.slice(0,10)+'T12:00:00').toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'});
      const hv=hVals[i], av=aVals[i];
      const gx=(pL+i/(n-1)*cW).toFixed(1);
      document.getElementById('ttg-hourly-humid')?.setAttribute('x1',gx);
      document.getElementById('ttg-hourly-humid')?.setAttribute('x2',gx);
      document.getElementById('ttg-hourly-humid')?.setAttribute('visibility','visible');
      html=`<div class="tt-title">${dl} ${lbl}${tag}</div>
        <div class="tt-row"><span class="tt-lbl">Humidity</span><span class="tt-cur">${hv!=null?Math.round(hv)+'%':'—'}</span></div>
        ${av!=null?`<div class="tt-row"><span class="tt-lbl">5-yr avg</span><span class="tt-muted">${Math.round(av)}%</span></div>`:''}`;
    } else if(chartType==='daily-humid'&&_dailyHumidData){
      const{dailyMean,histMean,dates,pL,slotW,n,todayIdx}=_dailyHumidData;
      const i=Math.max(0,Math.min(n-1,Math.floor((svgX-pL)/slotW)));
      const isPast=i<todayIdx, isToday=i===todayIdx;
      const tag=isPast?'<span style="color:var(--muted);font-weight:400;font-size:.68rem"> · actual</span>':'';
      const dl=isToday?'Today':new Date(dates[i]+'T12:00:00').toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'});
      const mm=dailyMean[i];
      const gx=(pL+(i+0.5)*slotW).toFixed(1);
      document.getElementById('ttg-daily-humid')?.setAttribute('x1',gx);
      document.getElementById('ttg-daily-humid')?.setAttribute('x2',gx);
      document.getElementById('ttg-daily-humid')?.setAttribute('visibility','visible');
      html=`<div class="tt-title">${dl}${tag}</div>
        <div class="tt-row"><span class="tt-lbl">Mean humidity</span><span class="tt-cur">${mm!=null?Math.round(mm)+'%':'—'}</span></div>
        ${histMean!=null?`<div class="tt-row"><span class="tt-lbl">Seasonal avg</span><span class="tt-muted">${Math.round(histMean)}%</span></div>`:''}`;
    } else if(chartType==='climate'&&_climateData){
      const{data,pL,slotW,n}=_climateData;
      const i=Math.max(0,Math.min(n-1,Math.floor((svgX-pL)/slotW)));
      const MON=['January','February','March','April','May','June','July','August','September','October','November','December'];
      const d=data[i];
      const fmtT=v=>v!=null?`${Math.round(nT(v))}${uT()}`:'—';
      const fmtR=v=>v!=null?(imp?(v*0.0393701).toFixed(1)+'"':Math.round(v)+'mm'):'—';
      html=`<div class="tt-title">${MON[i]}</div>
        <div class="tt-row"><span class="tt-lbl">Avg high</span><span class="tt-hot">${fmtT(d.tMax)}</span></div>
        <div class="tt-row"><span class="tt-lbl">Avg low</span><span class="tt-cold">${fmtT(d.tMin)}</span></div>
        <div class="tt-row"><span class="tt-lbl">Avg rainfall</span><span class="tt-muted">${fmtR(d.rain)}</span></div>`;
    } else return;
    tt.innerHTML=html;
    const tW=170,mg=14;
    let tx=cx+mg, ty=cy-100;
    if(tx+tW>window.innerWidth) tx=cx-tW-mg;
    if(ty<8) ty=cy+mg;
    tt.style.left=tx+'px'; tt.style.top=ty+'px';
    tt.classList.remove('hidden');
  }
  function hideTT(){
    document.getElementById('tt')?.classList.add('hidden');
    document.getElementById('ttg-temp')?.setAttribute('visibility','hidden');
    document.getElementById('ttg-rain')?.setAttribute('visibility','hidden');
    document.getElementById('ttg-hourly')?.setAttribute('visibility','hidden');
    document.getElementById('ttg-hourly-rain')?.setAttribute('visibility','hidden');
    document.getElementById('ttg-daily-rain')?.setAttribute('visibility','hidden');
    document.getElementById('ttg-hourly-humid')?.setAttribute('visibility','hidden');
    document.getElementById('ttg-daily-humid')?.setAttribute('visibility','hidden');
  }
  const content=document.getElementById('content');
  content.addEventListener('mousemove',e=>{
    const svg=e.target.closest('svg[data-chart]');
    if(!svg){hideTT();return;}
    const rect=svg.getBoundingClientRect();
    const vb=svg.viewBox.baseVal;
    const svgX=(e.clientX-rect.left)/rect.width*vb.width;
    showTT(svgX,svg.dataset.chart,e.clientX,e.clientY);
  });
  content.addEventListener('mouseleave',hideTT);
})();

// ── Boot ───────────────────────────────────────────────
function showSearchFirst(hint){
  document.getElementById('loading').classList.add('hidden');
  document.getElementById('error').classList.add('hidden');
  document.getElementById('main').classList.remove('hidden');
  geoName='';
  searching=true;
  renderHeader();
  document.getElementById('content').innerHTML=`
    <div class="empty-state">
      <div class="empty-ico">🌍</div>
      <p class="empty-title">Search for a city to get started</p>
      <p class="empty-sub">${hint||'Type any city name in the search bar above'}</p>
    </div>`;
  requestAnimationFrame(()=>{const i=document.getElementById('srch');if(i)i.focus();});
}

async function loadWeather(lat, lon, name, source) {
  activeSource = source;
  geoName = name;
  if (source === 'geo') { myLat = lat; myLon = lon; myName = name; }
  savePrefs({ activeSource, customLat, customLon, customName, imp });
  setLoad('Loading weather data…');
  ytdData = null; hourlyHistData = null; hourlyRainHistData = null;
  dailyRainHistData = null; climatologyData = null; hourlyHumidData = null;
  const [fc, climate] = await Promise.all([getForecast(lat, lon), getClimatology(lat, lon)]);
  fcData = fc; climatologyData = climate;
  histData = deriveTempBand(climate); dailyRainHistData = deriveDailyRain(climate);
  render();
  loadBackground(lat, lon);
}

async function init(){
  const prefs = loadPrefs();
  if (prefs.theme && prefs.theme !== 'auto') applyTheme(prefs.theme);

  // Restore last viewed location if available
  if (prefs.customLat != null && prefs.activeSource === 'custom') {
    try {
      await loadWeather(prefs.customLat, prefs.customLon, prefs.customName, 'custom');
      return;
    } catch (e) {
      showErr(e.message || 'Failed to load saved location.');
      return;
    }
  }

  setLoad('Getting your location…');
  try {
    const pos = await getPos();
    const { latitude: lat, longitude: lon } = pos.coords;
    const name = await geocode(lat, lon);
    await loadWeather(lat, lon, name, 'geo');
  } catch (e) {
    if (!fcData) showSearchFirst(e.message);
    else showErr(e.message || 'Unexpected error.');
  }
}
