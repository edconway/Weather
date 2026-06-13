// ── Search ─────────────────────────────────────────────
const ICON_SEARCH=`<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>`;

function openSearch(){
  searching=true; searchResults=[]; searchFocusIdx=-1;
  renderHeader();
  requestAnimationFrame(()=>{
    const inp=document.getElementById('srch');
    if(inp) inp.focus();
  });
}

function closeSearch(){
  searching=false; searchResults=[]; searchFocusIdx=-1;
  clearTimeout(searchTimer);
  document.getElementById('search-drop').classList.add('hidden');
  renderHeader();
}

function clearInput(){
  const inp=document.getElementById('srch');
  if(inp){inp.value='';inp.focus();}
  searchResults=[]; searchFocusIdx=-1;
  document.getElementById('search-drop').classList.add('hidden');
}

function onSearchInput(val){
  searchFocusIdx=-1;
  clearTimeout(searchTimer);
  const drop=document.getElementById('search-drop');
  if(!val.trim()){searchResults=[];drop.classList.add('hidden');return;}
  drop.classList.remove('hidden');
  drop.innerHTML='<p class="search-msg">Searching…</p>';
  searchTimer=setTimeout(()=>doSearch(val),300);
}

async function doSearch(query){
  try{
    const r=await fetch(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(query)}&count=6&language=en&format=json`);
    if(!r.ok) throw 0;
    const data=await r.json();
    searchResults=data.results||[];
    renderDrop();
  }catch{
    document.getElementById('search-drop').innerHTML='<p class="search-msg">Search failed — check your connection.</p>';
  }
}

function renderDrop(){
  const drop=document.getElementById('search-drop');
  const inp=document.getElementById('srch');
  if(!drop) return;
  if(!searchResults.length){
    drop.innerHTML=`<p class="search-msg">No results for "${escapeHtml(inp?inp.value:'')}"</p>`;
    return;
  }
  drop.innerHTML=searchResults.map((r,i)=>{
    const detail=[r.admin1,r.country_code].filter(Boolean).join(', ');
    const focused=i===searchFocusIdx?'focused':'';
    return`<div class="search-result ${focused}" data-idx="${i}">
      <div class="sr-left"><span class="sr-pin">${ICON.pin}</span><span class="sr-name">${escapeHtml(r.name)}</span></div>
      <span class="sr-detail">${escapeHtml(detail)}</span>
    </div>`;
  }).join('');
  drop.onclick=e=>{
    const row=e.target.closest('.search-result');
    if(!row) return;
    const r=searchResults[+row.dataset.idx];
    if(r) pickResult(r.latitude,r.longitude,`${r.name}${r.admin1?', '+r.admin1:''}${r.country?', '+r.country:''}`);
  };
}

function onSearchKey(e){
  if(e.key==='Escape'){closeSearch();return;}
  if(e.key==='ArrowDown'){
    e.preventDefault();
    searchFocusIdx=Math.min(searchFocusIdx+1,searchResults.length-1);
    renderDrop(); return;
  }
  if(e.key==='ArrowUp'){
    e.preventDefault();
    searchFocusIdx=Math.max(searchFocusIdx-1,0);
    renderDrop(); return;
  }
  if(e.key==='Enter'&&searchFocusIdx>=0&&searchResults[searchFocusIdx]){
    const r=searchResults[searchFocusIdx];
    pickResult(r.latitude,r.longitude,`${r.name}${r.admin1?', '+r.admin1:''}${r.country?', '+r.country:''}`);
  }
}

// Fire the non-blocking secondary fetches: YTD rainfall (1 req) + merged hourly
// normals (5 reqs). Kept small so we stay well under Open-Meteo's rate limit.
function loadBackground(lat,lon){
  getRainYTD(lat,lon).then(ytd=>{ytdData=ytd;if(fcData)renderContent();}).catch(()=>{});
  getHourlyNormals(lat,lon).then(d=>{
    hourlyHistData=d.temp; hourlyRainHistData=d.rain; hourlyHumidData=d.humidity;
    if(fcData)renderContent();
  }).catch(()=>{});
}

async function pickResult(lat,lon,name){
  closeSearch();
  customLat=lat; customLon=lon; customName=name;
  activeSource='custom'; geoName=name;
  savePrefs({ customLat: lat, customLon: lon, customName: name, activeSource: 'custom' });
  renderHeader(); setLoad('Loading weather…');
  ytdData=null; hourlyHistData=null; hourlyRainHistData=null; dailyRainHistData=null; climatologyData=null; hourlyHumidData=null;
  try{
    const[fc,climate]=await Promise.all([getForecast(lat,lon),getClimatology(lat,lon)]);
    fcData=fc; climatologyData=climate;
    histData=deriveTempBand(climate); dailyRainHistData=deriveDailyRain(climate);
    renderContent();
    document.getElementById('main').classList.remove('hidden');
    document.getElementById('loading').classList.add('hidden');
  }catch(e){showErr(e.message||'Failed to load weather.');return;}
  loadBackground(lat,lon);
}

async function switchSource(src){
  if(activeSource===src) return;
  const lat=src==='geo'?myLat:customLat;
  const lon=src==='geo'?myLon:customLon;
  const name=src==='geo'?myName:customName;
  if(lat==null) return;
  activeSource=src; geoName=name;
  savePrefs({ activeSource: src });
  renderHeader();
  setLoad('Loading weather…');
  ytdData=null; hourlyHistData=null; hourlyRainHistData=null; dailyRainHistData=null; climatologyData=null; hourlyHumidData=null;
  try{
    const[fc,climate]=await Promise.all([getForecast(lat,lon),getClimatology(lat,lon)]);
    fcData=fc; climatologyData=climate;
    histData=deriveTempBand(climate); dailyRainHistData=deriveDailyRain(climate);
    renderContent();
    document.getElementById('main').classList.remove('hidden');
    document.getElementById('loading').classList.add('hidden');
  }catch(e){showErr(e.message||'Failed to load weather.');return;}
  loadBackground(lat,lon);
}

init();
