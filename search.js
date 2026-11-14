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
  document.getElementById('search-drop')?.classList.add('hidden');
  renderHeader();
}

function clearInput(){
  const inp=document.getElementById('srch');
  if(inp){inp.value='';inp.focus();}
  searchResults=[]; searchFocusIdx=-1;
  document.getElementById('search-drop')?.classList.add('hidden');
}

function searchDrop(){
  const modal=document.getElementById('place-modal');
  if(modal && !modal.classList.contains('hidden')) return document.getElementById('place-results');
  return document.getElementById('search-drop');
}
function onSearchInput(val){
  searchFocusIdx=-1;
  clearTimeout(searchTimer);
  const drop=searchDrop();
  if(!drop) return;
  if(!val.trim()){
    searchResults=[];
    if(document.getElementById('place-modal') && !document.getElementById('place-modal').classList.contains('hidden') && typeof renderPlaceIdle==='function'){
      renderPlaceIdle();
      return;
    }
    drop.classList.add('hidden');
    return;
  }
  drop.classList.remove('hidden');
  drop.innerHTML='<p class="search-msg">Searching…</p>';
  searchTimer=setTimeout(()=>doSearch(val),300);
}

async function doSearch(query){
  try{
    const r=await fetch(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(query)}&count=10&language=en&format=json`);
    if(!r.ok) throw 0;
    const data=await r.json();
    searchResults=dedupePlaces(data.results||[]);
    renderDrop();
  }catch{
    const drop=searchDrop();
    if(drop) drop.innerHTML='<p class="search-msg">Search failed — check your connection.</p>';
  }
}
function dedupePlaces(list){
  const sorted=[...list].sort((a,b)=>(b.population||0)-(a.population||0));
  const out=[];
  sorted.forEach(r=>{
    const dup=out.find(o=>o.name===r.name && (o.admin1||'')===(r.admin1||'') && (o.country||'')===(r.country||'') && typeof kmBetween==='function' && kmBetween({lat:o.latitude,lon:o.longitude},{lat:r.latitude,lon:r.longitude})<=25);
    if(!dup) out.push(r);
  });
  return out;
}
function resultPlace(r){
  const region=r.admin1||'';
  const country=r.country||'';
  const same=region && region.toLowerCase()===String(r.name||'').toLowerCase();
  const label=(!region||same)?r.name:`${r.name}, ${region}`;
  return {lat:r.latitude, lon:r.longitude, name:r.name, region, country, label};
}

function renderDrop(){
  const drop=searchDrop();
  const inp=document.getElementById('srch');
  if(!drop) return;
  drop.classList.remove('hidden');
  if(!searchResults.length){
    drop.innerHTML=`<p class="search-msg">No results for "${escapeHtml(inp?inp.value:'')}"</p>`;
    return;
  }
  drop.innerHTML=searchResults.map((r,i)=>{
    const detail=[r.admin1, r.country].filter(Boolean).join(', ');
    const focused=i===searchFocusIdx?'focused':'';
    return`<button type="button" class="search-result ${focused}" data-idx="${i}">
      <span class="sr-name">${escapeHtml(r.name)}</span>
      <span class="sr-detail">${escapeHtml(detail)}</span>
    </button>`;
  }).join('');
  drop.onclick=e=>{
    const row=e.target.closest('.search-result');
    if(!row) return;
    const r=searchResults[+row.dataset.idx];
    if(r){
      const place=resultPlace(r);
      pickResult(place.lat, place.lon, place.label, place);
    }
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
    const place=resultPlace(r);
    pickResult(place.lat, place.lon, place.label, place);
  }
}

async function pickResult(lat,lon,name,place){
  const picked=place||{lat,lon,name,region:'',country:'',label:name};
  if(typeof rememberPlace==='function') rememberPlace(picked);
  else { customLat=lat; customLon=lon; customName=picked.label||name; }
  if(typeof closePlaces==='function') closePlaces();
  closeSearch();
  const label=picked.label||name;
  if(typeof showSkeleton==='function') showSkeleton(label);
  else setLoad('Loading weather…');
  try{
    const fc=await getForecast(lat,lon);
    beginLocationWeather(fc,lat,lon,label,'custom');
  }catch(e){showErr(e.message||'Failed to load weather.');}
}

async function switchSource(src){
  if(activeSource===src) return;
  const lat=src==='geo'?myLat:customLat;
  const lon=src==='geo'?myLon:customLon;
  const name=src==='geo'?myName:customName;
  if(lat==null) return;
  if(typeof showSkeleton==='function') showSkeleton(name);
  else setLoad('Loading weather…');
  try{
    const fc=await getForecast(lat,lon);
    beginLocationWeather(fc,lat,lon,name,src);
  }catch(e){showErr(e.message||'Failed to load weather.');}
}

init();
