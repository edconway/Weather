// ── Chart renderers ────────────────────────────────────

function _narrow(){ return typeof window!=='undefined'&&window.innerWidth<=480; }
function _mobileChart(){ return typeof window!=='undefined'&&window.innerWidth<=640; }
function _chartPR(){ return 14; }
function _hourStep(){ return _narrow()?12:6; }
function _endLbl(t){
  if(!_mobileChart()) return t;
  const m={'Forecast':'Fcst','5-yr avg':'Avg','Hist. avg':'Hist'};
  return m[t]??t;
}
function _prForEnd(...labels){
  const base=_chartPR();
  const texts=labels.filter(Boolean).map(String).map(_endLbl);
  if(!texts.length) return base;
  const est=Math.max(...texts.map(t=>t.length))*5.5+12;
  return Math.max(base,Math.round(est));
}
function _dims(baseH,pL,pR,pT,pB){
  const W=580;
  if(!_mobileChart()) return{W,H:baseH,pL,pR,pT,pB};
  // Square viewBox on mobile; scale vertical padding only (keep desktop lateral gutters)
  const H=W;
  const s=H/baseH;
  const padScaleY=Math.min(s,1.65);
  return{
    W,H,
    pL,pR,
    pT:Math.round(pT*padScaleY),
    pB:Math.round(pB*padScaleY),
  };
}
function _hourLbl(hr){
  return hr===0?'Midnight':hr===12?'Noon':hr<12?`${hr}am`:`${hr-12}pm`;
}
function _chartDark(){
  if(typeof window==='undefined') return false;
  const t=document.documentElement.dataset.theme;
  if(t==='dark') return true;
  if(t==='light') return false;
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}
function _cc(){
  const s=getComputedStyle(document.documentElement);
  const g=v=>s.getPropertyValue(v).trim();
  return{
    hot:g('--chart-hot'),hotPast:g('--chart-hot-past'),
    cold:g('--chart-cold'),coldPast:g('--chart-cold-past'),
    rain:g('--chart-rain'),rainPast:g('--chart-rain-past'),rainSolid:g('--chart-rain-solid'),
    humid:g('--chart-humid'),humidPast:g('--chart-humid-past'),
    muted:g('--subtle'),ink:g('--text')||'#1a2332',
    dot:_chartDark()?'rgba(238,240,243,.85)':'rgba(15,23,42,.85)',
  };
}

function _nowParts(){
  if(typeof placeNowParts==='function') return placeNowParts();
  const d=new Date();
  const dateStr=localDateStr(d);
  return {year:d.getFullYear(),month:d.getMonth(),day:d.getDate(),hour:d.getHours(),minute:d.getMinutes(),dateStr,hourStr:`${dateStr}T${String(d.getHours()).padStart(2,'0')}:00`};
}

// Past 24 h and next 24 h, in millimetres, aligned with the rain charts.
function hourlyRainWindow(){
  if(!fcData?.hourly?.time) return null;
  const hh=fcData.hourly;
  const nowStr=_nowParts().hourStr;
  let nowIdx=hh.time.findIndex(t=>t>=nowStr);
  if(nowIdx<0) nowIdx=hh.time.length-1;
  const startIdx=Math.max(0,nowIdx-24);
  const endIdx=Math.min(hh.time.length,nowIdx+24);
  const times=hh.time.slice(startIdx,endIdx);
  const precip=(hh.precipitation||[]).slice(startIdx,endIdx).map(v=>v??0);
  const prob=(hh.precipitation_probability||[]).slice(startIdx,endIdx);
  const relNow=nowIdx-startIdx;
  const usual=hourlyRainHistData?.wetHourProbabilityByHour||null;
  const normal=hourlyRainHistData?.avgByHour||null;
  return {times,precip,prob,relNow,n:times.length,usual,normal,startIdx};
}

function _gapAreas(xf,yf,values,normals){
  const below=[], above=[];
  const n=values.length;
  const push=(bag,x0,ya0,yb0,x1,ya1,yb1)=>{
    bag.push(`M${x0.toFixed(1)},${ya0.toFixed(1)} L${x1.toFixed(1)},${ya1.toFixed(1)} L${x1.toFixed(1)},${yb1.toFixed(1)} L${x0.toFixed(1)},${yb0.toFixed(1)} Z`);
  };
  for(let i=0;i<n-1;i++){
    const a0=values[i], b0=normals[i], a1=values[i+1], b1=normals[i+1];
    if(a0==null||b0==null||a1==null||b1==null) continue;
    const d0=a0-b0, d1=a1-b1;
    if(d0===0&&d1===0) continue;
    const x0=xf(i), x1=xf(i+1);
    const ya0=yf(a0), yb0=yf(b0), ya1=yf(a1), yb1=yf(b1);
    if((d0<0&&d1>0)||(d0>0&&d1<0)){
      const t=d0/(d0-d1);
      const xc=x0+(x1-x0)*t;
      const yc=ya0+(ya1-ya0)*t;
      if(d0<0) push(below,x0,ya0,yb0,xc,yc,yc); else push(above,x0,ya0,yb0,xc,yc,yc);
      if(d1<0) push(below,xc,yc,yc,x1,ya1,yb1); else push(above,xc,yc,yc,x1,ya1,yb1);
    } else if(d0<0||d1<0) push(below,x0,ya0,yb0,x1,ya1,yb1);
    else push(above,x0,ya0,yb0,x1,ya1,yb1);
  }
  return {below:below.join(' '), above:above.join(' ')};
}

function makeTempChart(){
  if(!fcData) return '';
  if(!histData) return '<p class="search-msg" style="padding:20px 0">Loading historical comparison…</p>';
  const c=_cc();
  const d=fcData.daily;
  // Find today's index in the 14-day array (past_days:7 + forecast_days:7)
  const todayStr=_nowParts().dateStr;
  const todayIdx=Math.max(0,d.time.findIndex(t=>t===todayStr));
  const labels=d.time.map((t,i)=>i===todayIdx?'Today':fDay(t));
  const maxV=d.temperature_2m_max.map(v=>v!=null?nT(v):null);
  const minV=d.temperature_2m_min.map(v=>v!=null?nT(v):null);
  const dailyAvg=histData.dailyAvg||[];
  const bandMaxes=dailyAvg.map(a=>a.tMax!=null?nT(a.tMax):null).filter(v=>v!=null);
  const bandMins=dailyAvg.map(a=>a.tMin!=null?nT(a.tMin):null).filter(v=>v!=null);
  const allV=[...maxV,...minV,...bandMaxes,...bandMins].filter(v=>v!=null&&!isNaN(v));
  if(!allV.length) return '';
  const lo=Math.floor(Math.min(...allV))-2;
  const hi=Math.ceil(Math.max(...allV))+2;
  const{W,H,pL,pR,pT,pB}=_dims(210,46,_prForEnd('High','Low'),24,38);
  const cW=W-pL-pR,cH=H-pT-pB;
  const n=labels.length;
  const xf=i=>pL+i/(n-1)*cW;
  const yf=v=>pT+(1-(v-lo)/(hi-lo))*cH;
  const rng=hi-lo;
  const rawStep=rng/4;
  const mag=Math.pow(10,Math.floor(Math.log10(rawStep||1)));
  const tickStep=[1,2,5,10].map(s=>s*mag).find(s=>rng/s<=6)||Math.ceil(rawStep);
  const ticks=[];
  for(let v=Math.ceil(lo/tickStep)*tickStep;v<=hi;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${v}°</text>`);
  }
  // Rolling-average band — polygon whose edges follow per-day ±3-day avg highs and lows
  const band=(()=>{
    if(!dailyAvg.length) return '';
    const topPts=dailyAvg.map((a,i)=>a.tMax!=null?`${xf(i).toFixed(1)},${yf(nT(a.tMax)).toFixed(1)}`:null).filter(Boolean);
    const botPts=dailyAvg.map((a,i)=>a.tMin!=null?`${xf(i).toFixed(1)},${yf(nT(a.tMin)).toFixed(1)}`:null).filter(Boolean);
    if(!topPts.length||!botPts.length) return '';
    const poly=[...topPts,...[...botPts].reverse()].join(' ');
    // Label near left edge, vertically centred on the band at the first data point
    const f=dailyAvg[0];
    const lblY=f.tMax!=null&&f.tMin!=null?((yf(nT(f.tMax))+yf(nT(f.tMin)))/2).toFixed(1):null;
    const lbl=lblY?`<text x="${pL+4}" y="${(+lblY+4).toFixed(1)}" font-size="11" fill="${c.ink}" opacity="0.8">Normal range</text>`:'';
    return `<polygon points="${poly}" class="ch-band"/>${lbl}`;
  })();
  // Vertical "Today" divider
  const todayX=xf(todayIdx).toFixed(1);
  const todayMark=`<line x1="${todayX}" y1="${pT}" x2="${todayX}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${todayX}" y="${pT-4}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Today</text>`;
  // Lines: past segment (dashed, index 0..todayIdx inclusive for continuity) and forecast segment (solid)
  const pastMxPts=maxV.slice(0,todayIdx+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const pastMnPts=minV.slice(0,todayIdx+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const fcstMxPts=maxV.slice(todayIdx).map((v,i)=>`${xf(todayIdx+i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const fcstMnPts=minV.slice(todayIdx).map((v,i)=>`${xf(todayIdx+i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  // Dots: lighter/smaller for past, normal for forecast; value labels only on forecast
  const mxDots=maxV.map((v,i)=>{
    if(v==null) return '';
    const cx=xf(i).toFixed(1),cy=yf(v).toFixed(1);
    const isPast=i<todayIdx;
    const fill=isPast?c.hotPast:c.hot;
    const lbl=i===todayIdx?`<text x="${cx}" y="${(yf(v)-9).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${isPast?2.8:3.5}" fill="${fill}" stroke="${c.dot}" stroke-width="1.5"/>${lbl}`;
  }).join('');
  const mnDots=minV.map((v,i)=>{
    if(v==null) return '';
    const cx=xf(i).toFixed(1),cy=yf(v).toFixed(1);
    const isPast=i<todayIdx;
    const fill=isPast?c.coldPast:c.cold;
    const lbl=i===todayIdx?`<text x="${cx}" y="${(yf(v)+15).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${isPast?2.8:3.5}" fill="${fill}" stroke="${c.dot}" stroke-width="1.5"/>${lbl}`;
  }).join('');
  const xLbls=labels.map((l,i)=>{
    if(_narrow()&&i%2!==0&&i!==todayIdx) return '';
    return `<text x="${xf(i).toFixed(1)}" y="${H-6}" class="ca" text-anchor="middle">${l}</text>`;
  }).join('');
  _tempData={labels,maxV,minV,dailyAvg,pL,cW,n,todayIdx};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="temp" tabindex="0" role="img">
    ${ticks.join('')}
    ${band}
    ${todayMark}
    <line id="ttg-temp" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${pastMxPts}" class="cl cl-hot" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${pastMnPts}" class="cl cl-cold" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${fcstMxPts}" class="cl cl-hot"/>
    <polyline points="${fcstMnPts}" class="cl cl-cold"/>
    ${mxDots}${mnDots}
    ${xLbls}
  </svg>`;
}

function makeWetBulbChart(){
  if(!fcData) return '';
  if(!histData) return '<p class="search-msg" style="padding:20px 0">Loading historical comparison…</p>';
  const c=_cc();
  const d=fcData.daily;
  const wbMax=d.wet_bulb_temperature_2m_max, wbMin=d.wet_bulb_temperature_2m_min;
  if(!wbMax?.length||!wbMin?.length) return '';
  const todayStr=_nowParts().dateStr;
  const todayIdx=Math.max(0,d.time.findIndex(t=>t===todayStr));
  const labels=d.time.map((t,i)=>i===todayIdx?'Today':fDay(t));
  const maxV=wbMax.map(v=>v!=null?nT(v):null);
  const minV=wbMin.map(v=>v!=null?nT(v):null);
  const dailyAvg=histData.dailyAvg||[];
  const bandMaxes=dailyAvg.map(a=>a.wbMax!=null?nT(a.wbMax):null).filter(v=>v!=null);
  const bandMins=dailyAvg.map(a=>a.wbMin!=null?nT(a.wbMin):null).filter(v=>v!=null);
  const allV=[...maxV,...minV,...bandMaxes,...bandMins].filter(v=>v!=null&&!isNaN(v));
  if(!allV.length) return '';
  const lo=Math.floor(Math.min(...allV))-2;
  const hi=Math.ceil(Math.max(...allV))+2;
  const{W,H,pL,pR,pT,pB}=_dims(210,46,_prForEnd('High','Low'),24,38);
  const cW=W-pL-pR,cH=H-pT-pB;
  const n=labels.length;
  const xf=i=>pL+i/(n-1)*cW;
  const yf=v=>pT+(1-(v-lo)/(hi-lo))*cH;
  const rng=hi-lo;
  const rawStep=rng/4;
  const mag=Math.pow(10,Math.floor(Math.log10(rawStep||1)));
  const tickStep=[1,2,5,10].map(s=>s*mag).find(s=>rng/s<=6)||Math.ceil(rawStep);
  const ticks=[];
  for(let v=Math.ceil(lo/tickStep)*tickStep;v<=hi;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${v}°</text>`);
  }
  const band=(()=>{
    if(!dailyAvg.length) return '';
    const topPts=dailyAvg.map((a,i)=>a.wbMax!=null?`${xf(i).toFixed(1)},${yf(nT(a.wbMax)).toFixed(1)}`:null).filter(Boolean);
    const botPts=dailyAvg.map((a,i)=>a.wbMin!=null?`${xf(i).toFixed(1)},${yf(nT(a.wbMin)).toFixed(1)}`:null).filter(Boolean);
    if(!topPts.length||!botPts.length) return '';
    const poly=[...topPts,...[...botPts].reverse()].join(' ');
    const f=dailyAvg[0];
    const lblY=f.wbMax!=null&&f.wbMin!=null?((yf(nT(f.wbMax))+yf(nT(f.wbMin)))/2).toFixed(1):null;
    const lbl=lblY?`<text x="${pL+4}" y="${(+lblY+4).toFixed(1)}" font-size="11" fill="${c.ink}" opacity="0.8">Normal range</text>`:'';
    return `<polygon points="${poly}" class="ch-band"/>${lbl}`;
  })();
  const todayX=xf(todayIdx).toFixed(1);
  const todayMark=`<line x1="${todayX}" y1="${pT}" x2="${todayX}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${todayX}" y="${pT-4}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Today</text>`;
  const pastMxPts=maxV.slice(0,todayIdx+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const pastMnPts=minV.slice(0,todayIdx+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const fcstMxPts=maxV.slice(todayIdx).map((v,i)=>`${xf(todayIdx+i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const fcstMnPts=minV.slice(todayIdx).map((v,i)=>`${xf(todayIdx+i).toFixed(1)},${yf(v??lo).toFixed(1)}`).join(' ');
  const mxDots=maxV.map((v,i)=>{
    if(v==null) return '';
    const cx=xf(i).toFixed(1),cy=yf(v).toFixed(1);
    const isPast=i<todayIdx;
    const fill=isPast?c.humidPast:c.humid;
    const lbl=i===todayIdx?`<text x="${cx}" y="${(yf(v)-9).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${isPast?2.8:3.5}" fill="${fill}" stroke="${c.dot}" stroke-width="1.5"/>${lbl}`;
  }).join('');
  const mnDots=minV.map((v,i)=>{
    if(v==null) return '';
    const cx=xf(i).toFixed(1),cy=yf(v).toFixed(1);
    const isPast=i<todayIdx;
    const fill=isPast?'rgba(74,175,163,.22)':'rgba(74,175,163,.55)';
    const lbl=i===todayIdx?`<text x="${cx}" y="${(yf(v)+15).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${isPast?2.8:3.5}" fill="${fill}" stroke="${c.dot}" stroke-width="1.5"/>${lbl}`;
  }).join('');
  const xLbls=labels.map((l,i)=>{
    if(_narrow()&&i%2!==0&&i!==todayIdx) return '';
    return `<text x="${xf(i).toFixed(1)}" y="${H-6}" class="ca" text-anchor="middle">${l}</text>`;
  }).join('');
  _wetBulbData={labels,maxV,minV,dailyAvg,pL,cW,n,todayIdx};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="wet-bulb" tabindex="0" role="img">
    ${ticks.join('')}
    ${band}
    ${todayMark}
    <line id="ttg-wet-bulb" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${pastMxPts}" stroke="${c.humid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${pastMnPts}" stroke="${c.humid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="5,4" opacity="0.35"/>
    <polyline points="${fcstMxPts}" stroke="${c.humid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    <polyline points="${fcstMnPts}" stroke="${c.humid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" opacity="0.75"/>
    ${mxDots}${mnDots}
    ${xLbls}
  </svg>`;
}

function makeRainYTDChart(){
  if(!ytdData) return '<p class="search-msg" style="padding:24px 0">Loading year-to-date rainfall…</p>';
  const c=_cc();
  const{labels,cumCurrentYear,cumHistAvg,thisYear}=ytdData;
  const n=labels.length;
  if(!n) return '';
  // Build 7-day forecast extension (days strictly after the last archive date)
  const fcstExtCum=[], fcstDates=[];
  if(fcData?.daily){
    const fd=fcData.daily;
    const si=fd.time.findIndex(t=>t>ytdData.latestDate);
    if(si>=0){
      let cum=cumCurrentYear[n-1];
      fd.time.slice(si,si+7).forEach((date,j)=>{
        cum+=(fd.precipitation_sum[si+j]??0);
        fcstExtCum.push(cum);
        fcstDates.push(date);
      });
    }
  }
  const numFc=fcstExtCum.length;
  const totalN=n+numFc;
  const curV=cumCurrentYear.map(nP);
  const avgV=cumHistAvg.map(nP);
  const fcV=fcstExtCum.map(nP);
  const avgExtV=(ytdData.cumHistAvgExt||[]).slice(0,numFc).map(nP);
  const{W,H,pL,pR,pT,pB}=_dims(222,52,_prForEnd(String(thisYear),'Hist. avg'),20,36);
  const cW=W-pL-pR,cH=H-pT-pB;
  const yMax=Math.max(...curV,...avgV,...(fcV.length?fcV:[0]),...(avgExtV.length?avgExtV:[0]),.01)*1.1;
  // x maps over the full totalN range so forecast extends naturally to the right
  const yearDays=Math.round((Date.UTC(thisYear,11,31)-Date.UTC(thisYear,0,1))/86400000);
  const xf=i=>pL+(i/yearDays)*cW;
  const yf=v=>pT+(1-v/yMax)*cH;
  // Nice Y-axis ticks
  const niceSteps=imp?[0.1,0.25,0.5,1,2,5,10,20,25,50]:[1,2,5,10,20,25,50,100,200,250,500];
  const rawStep=yMax/4;
  const tickStep=niceSteps.find(s=>s>=rawStep*0.7)||Math.ceil(rawStep);
  const fmtY=v=>imp?(v<1?v.toFixed(1):Math.round(v))+'"':(v<10?v.toFixed(0):Math.round(v))+'mm';
  const ticks=[];
  for(let v=0;v<=yMax*1.05;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${fmtY(v)}</text>`);
  }
  // Month boundary markers (based on YTD labels only)
  const monthMarks=[];
  let lastMo=-1;
  labels.forEach((mmdd,i)=>{
    const mo=+mmdd.slice(0,2);
    if(mo!==lastMo){
      monthMarks.push({i,label:new Date(thisYear,mo-1,1).toLocaleString('en-US',{month:'short'})});
      lastMo=mo;
    }
  });
  if(!monthMarks.some(m=>m.label==='Dec')){
    const decI=Math.round((Date.UTC(thisYear,11,1)-Date.UTC(thisYear,0,1))/86400000);
    monthMarks.push({i:decI,label:'Dec'});
  }
  const xGrid=monthMarks.slice(1).map(m=>`<line x1="${xf(m.i).toFixed(1)}" y1="${pT}" x2="${xf(m.i).toFixed(1)}" y2="${pT+cH}" class="cg"/>`).join('');
  const xLabels=monthMarks.map(m=>`<text x="${xf(m.i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${m.label}</text>`).join('');
  const curPts=curV.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const avgPts=avgV.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  // "Today" divider at the point where actual data ends and forecast begins
  const rainTodayX=xf(n-1).toFixed(1);
  const rainTodayMark=numFc>0?`<line x1="${rainTodayX}" y1="${pT}" x2="${rainTodayX}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${rainTodayX}" y="${pT-4}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Today</text>`:''  ;
  // Historical avg extension — connects from last avg point into forecast window
  const avgExtPts=avgExtV.length?[
    `${xf(n-1).toFixed(1)},${yf(avgV[n-1]).toFixed(1)}`,
    ...avgExtV.map((v,i)=>`${xf(n+i).toFixed(1)},${yf(v).toFixed(1)}`)
  ].join(' '):'';
  // Forecast polyline starts at the last actual point for a smooth join
  const fcstPts=fcV.length?[
    `${xf(n-1).toFixed(1)},${yf(curV[n-1]).toFixed(1)}`,
    ...fcV.map((v,i)=>`${xf(n+i).toFixed(1)},${yf(v).toFixed(1)}`)
  ].join(' '):'';
  // End dot and end labels (replacing legend)
  const lx=xf(totalN-1).toFixed(1);
  const endCurY=yf(fcV.length?fcV[fcV.length-1]:curV[n-1]);
  const endAvgY=yf(avgExtV.length?avgExtV[avgExtV.length-1]:avgV[n-1]);
  const ly=endCurY.toFixed(1);
  // Separate labels if they're too close vertically
  const _rSep=endCurY-endAvgY;
  let _ryCur=endCurY, _ryAvg=endAvgY;
  if(Math.abs(_rSep)<13){const bump=(13-Math.abs(_rSep))/2+1;_ryCur+=_rSep>=0?bump:-bump;_ryAvg+=_rSep>=0?-bump:bump;}
  const endLabels='';
  _rainData={labels,curV,avgV,thisYear,pL,cW,n,fcV,numFc,totalN,fcstDates,yearDays};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="rain" tabindex="0" role="img">
    ${ticks.join('')}
    ${xGrid}
    <line id="ttg-rain" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${rainTodayMark}
    <polyline points="${avgPts}" class="cl-ytd-hist"/>
    ${avgExtPts?`<polyline points="${avgExtPts}" class="cl-ytd-hist"/>`:''}
    <polyline points="${curPts}" class="cl-ytd-cur"/>
    ${fcstPts?`<polyline points="${fcstPts}" stroke="${c.rainSolid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="5,4"/>`:''}
    <circle cx="${lx}" cy="${ly}" r="4" fill="${c.rainSolid}" stroke="${c.dot}" stroke-width="1.5"/>
    ${endLabels}
    ${xLabels}
  </svg>`;
}

function makeHourlyTempChart(){
  if(!fcData?.hourly?.time) return '';
  const c=_cc();
  if(!hourlyHistData) return '<p class="search-msg" style="padding:20px 0">Loading hourly history…</p>';
  const hh=fcData.hourly;
  const nowStr=_nowParts().hourStr;
  const rawNow=hh.time.findIndex(t=>t>=nowStr);
  const nowIdx=rawNow<1?1:rawNow;
  // Slice to past 24h + next 24h = 48 hours total
  // (past_days:7 overrides past_hours:24 and returns far more data; clamp explicitly)
  const startIdx=Math.max(0,nowIdx-24);
  const endIdx=Math.min(hh.time.length,nowIdx+24);
  const slicedTime=hh.time.slice(startIdx,endIdx);
  const slicedTemp=hh.temperature_2m.slice(startIdx,endIdx);
  const relNow=nowIdx-startIdx;
  // Map temps and historical avg, carrying last known value over nulls
  let lastT=null, lastA=null;
  const temps=slicedTemp.map(v=>{if(v!=null)lastT=nT(v);return lastT;});
  const histLine=slicedTime.map(t=>{
    const v=hourlyHistData.avgByHour[+t.slice(11,13)];
    if(v!=null)lastA=nT(v); return lastA;
  });
  const allV=[...temps,...histLine].filter(v=>v!=null&&!isNaN(v));
  if(!allV.length) return '';
  const lo=Math.floor(Math.min(...allV))-1, hi=Math.ceil(Math.max(...allV))+1;
  const{W,H,pL,pR,pT,pB}=_dims(198,46,_prForEnd('Forecast','5-yr avg'),20,32);
  const cW=W-pL-pR,cH=H-pT-pB;
  const n=temps.length;
  const xf=i=>pL+i/(n-1)*cW;
  const yf=v=>pT+(1-(v-lo)/(hi-lo))*cH;
  // Y-axis ticks
  const rng=hi-lo, rawStep=rng/3;
  const mag=Math.pow(10,Math.floor(Math.log10(rawStep||1)));
  const tickStep=[1,2,5,10].map(s=>s*mag).find(s=>rng/s<=5)||Math.ceil(rawStep);
  const ticks=[];
  for(let v=Math.ceil(lo/tickStep)*tickStep;v<=hi;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${v}°</text>`);
  }
  const nowX=xf(relNow).toFixed(1);
  const nowMark=`<line x1="${nowX}" y1="${pT}" x2="${nowX}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${nowX}" y="${pT-2}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Now</text>`;
  const histPts=histLine.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const pastPts=temps.slice(0,relNow+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const fcstPts=temps.slice(relNow).map((v,i)=>`${xf(relNow+i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const gaps=_gapAreas(xf,yf,temps,histLine);
  const areas=`${gaps.below?`<path d="${gaps.below}" fill="${c.cold}" opacity="0.13"/>`:''}${gaps.above?`<path d="${gaps.above}" fill="${c.hot}" opacity="0.13"/>`:''}`;
  let gapNote='', best=null;
  temps.forEach((v,i)=>{
    if(v==null||histLine[i]==null) return;
    const g=v-histLine[i];
    if(!best||Math.abs(g)>Math.abs(best.g)) best={i,g};
  });
  _hourlyGap={below:!!gaps.below, above:!!gaps.above};
  if(best&&Math.abs(best.g)>=1){
    const below=best.g<0;
    const y=yf(temps[best.i]);
    const ty=below?y+16:y-8;
    gapNote=`<text x="${xf(best.i).toFixed(1)}" y="${ty.toFixed(1)}" font-size="11" fill="${c.ink}" text-anchor="middle">${Math.round(Math.abs(best.g))}° ${below?'below':'above'} usual</text>`;
  }
  const dots=temps.map((v,i)=>{
    if(v==null) return '';
    const hr=+slicedTime[i].slice(11,13);
    if(hr%6!==0 && i!==relNow) return '';
    const isPast=i<relNow;
    return `<circle cx="${xf(i).toFixed(1)}" cy="${yf(v).toFixed(1)}" r="${i===relNow?3.5:2.6}" fill="${isPast?c.hotPast:c.hot}" stroke="${c.dot}" stroke-width="1.5"/>`;
  }).join('');
  const usedX=new Set();
  const xLbls=slicedTime.map((t,i)=>{
    const hr=+t.slice(11,13);
    if(hr!==0&&hr!==12) return '';
    const xKey=Math.round(xf(i));
    if(usedX.has(xKey)) return ''; usedX.add(xKey);
    const day=hr===0?`<text x="${xf(i).toFixed(1)}" y="${(pT+16).toFixed(1)}" font-size="11" font-weight="650" fill="${c.ink}" text-anchor="middle">${new Date(t.slice(0,10)+'T12:00:00').toLocaleDateString('en-US',{weekday:'short'})}</text>`:'';
    return day+`<text x="${xf(i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${hr===0?'12am':'12pm'}</text>`;
  }).join('');
  _hourlyData={temps,histLine,pL,cW,n,nowIdx:relNow,times:slicedTime};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="hourly" tabindex="0" role="img" aria-label="48-hour temperature against the 5-year average">
    ${ticks.join('')}
    ${areas}
    ${nowMark}
    <line id="ttg-hourly" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${histPts}" class="cl-ytd-hist"/>
    <polyline points="${pastPts}" class="cl cl-hot" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${fcstPts}" class="cl cl-hot"/>
    ${dots}
    ${gapNote}
    ${xLbls}
  </svg>`;
}

function makeHourlyWetBulbChart(){
  if(!fcData?.hourly?.time) return '';
  const c=_cc();
  if(!hourlyWbHistData) return '<p class="search-msg" style="padding:20px 0">Loading wet bulb history…</p>';
  const hh=fcData.hourly;
  const wb=hh.wet_bulb_temperature_2m;
  if(!wb?.length) return '';
  const nowStr=_nowParts().hourStr;
  const rawNow=hh.time.findIndex(t=>t>=nowStr);
  const nowIdx=rawNow<1?1:rawNow;
  const startIdx=Math.max(0,nowIdx-24);
  const endIdx=Math.min(hh.time.length,nowIdx+24);
  const slicedTime=hh.time.slice(startIdx,endIdx);
  const slicedWb=wb.slice(startIdx,endIdx);
  const relNow=nowIdx-startIdx;
  let lastV=null, lastA=null;
  const vals=slicedWb.map(v=>{if(v!=null)lastV=nT(v);return lastV;});
  const histLine=slicedTime.map(t=>{
    const v=hourlyWbHistData.avgByHour[+t.slice(11,13)];
    if(v!=null)lastA=nT(v); return lastA;
  });
  const allV=[...vals,...histLine].filter(v=>v!=null&&!isNaN(v));
  if(!allV.length) return '';
  const lo=Math.floor(Math.min(...allV))-1, hi=Math.ceil(Math.max(...allV))+1;
  const{W,H,pL,pR,pT,pB}=_dims(198,46,_prForEnd('Forecast','5-yr avg'),20,32);
  const cW=W-pL-pR,cH=H-pT-pB;
  const n=vals.length;
  const xf=i=>pL+i/(n-1)*cW;
  const yf=v=>pT+(1-(v-lo)/(hi-lo))*cH;
  const rng=hi-lo, rawStep=rng/3;
  const mag=Math.pow(10,Math.floor(Math.log10(rawStep||1)));
  const tickStep=[1,2,5,10].map(s=>s*mag).find(s=>rng/s<=5)||Math.ceil(rawStep);
  const ticks=[];
  for(let v=Math.ceil(lo/tickStep)*tickStep;v<=hi;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${v}°</text>`);
  }
  const nowX=xf(relNow).toFixed(1);
  const nowMark=`<line x1="${nowX}" y1="${pT}" x2="${nowX}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${nowX}" y="${pT-4}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Now</text>`;
  const histPts=histLine.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const pastPts=vals.slice(0,relNow+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const fcstPts=vals.slice(relNow).map((v,i)=>`${xf(relNow+i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const gaps=_gapAreas(xf,yf,vals,histLine);
  const areas=`${gaps.below?`<path d="${gaps.below}" fill="${c.cold}" opacity="0.13"/>`:''}${gaps.above?`<path d="${gaps.above}" fill="${c.hot}" opacity="0.13"/>`:''}`;
  _wbGap={below:!!gaps.below, above:!!gaps.above};
  let gapNote='', best=null;
  vals.forEach((v,i)=>{
    if(v==null||histLine[i]==null) return;
    const g=v-histLine[i];
    if(!best||Math.abs(g)>Math.abs(best.g)) best={i,g};
  });
  if(best&&Math.abs(best.g)>=1){
    const below=best.g<0;
    const y=yf(vals[best.i]);
    gapNote=`<text x="${xf(best.i).toFixed(1)}" y="${(below?y+16:y-8).toFixed(1)}" font-size="11" fill="${c.ink}" text-anchor="middle">${Math.round(Math.abs(best.g))}° ${below?'below':'above'} usual</text>`;
  }
  const dots=vals.map((v,i)=>{
    if(v==null) return '';
    const hr=+slicedTime[i].slice(11,13);
    if(hr%6!==0 && i!==relNow) return '';
    const isPast=i<relNow;
    return `<circle cx="${xf(i).toFixed(1)}" cy="${yf(v).toFixed(1)}" r="${i===relNow?3.5:2.6}" fill="${isPast?c.humidPast:c.humid}" stroke="${c.dot}" stroke-width="1.5"/>`;
  }).join('');
  const usedX=new Set();
  const xLbls=slicedTime.map((t,i)=>{
    const hr=+t.slice(11,13);
    if(hr!==0&&hr!==12) return '';
    const xKey=Math.round(xf(i));
    if(usedX.has(xKey)) return ''; usedX.add(xKey);
    const day=hr===0?`<text x="${xf(i).toFixed(1)}" y="${(pT+16).toFixed(1)}" font-size="11" font-weight="650" fill="${c.ink}" text-anchor="middle">${new Date(t.slice(0,10)+'T12:00:00').toLocaleDateString('en-US',{weekday:'short'})}</text>`:'';
    return day+`<text x="${xf(i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${hr===0?'12am':'12pm'}</text>`;
  }).join('');
  _hourlyWbData={vals,histLine,pL,cW,n,nowIdx:relNow,times:slicedTime};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="hourly-wb" tabindex="0" role="img" aria-label="48-hour wet bulb against the 5-year average">
    ${ticks.join('')}
    ${areas}
    ${nowMark}
    <line id="ttg-hourly-wb" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${histPts}" class="cl-ytd-hist"/>
    <polyline points="${pastPts}" stroke="${c.humid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${fcstPts}" stroke="${c.humid}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    ${dots}
    ${gapNote}
    ${xLbls}
  </svg>`;
}

function makeHourlyRainChart(){
  const w=hourlyRainWindow();
  if(!w||!w.n) return '';
  if(w.precip.every(v=>(v||0)<0.05)) return '';
  const c=_cc();
  const {times,precip,prob,relNow,n,normal}=w;
  const norms=normal?times.map(t=>normal[+t.slice(11,13)]||0):precip.map(()=>0);
  const yMax=Math.max(...precip, ...norms, 0.5)*1.25;
  const {W,H,pL,pR,pT,pB}=_dims(228,52,14,28,34);
  const stripH=26;
  const plotTop=pT+stripH;
  const cW=W-pL-pR, cH=H-plotTop-pB;
  const slotW=cW/n;
  const barW=Math.max(2,slotW*0.62);
  const xCx=i=>pL+(i+0.5)*slotW;
  const xBL=i=>pL+i*slotW+(slotW-barW)/2;
  const yf=v=>plotTop+(1-Math.min(v,yMax)/yMax)*cH;
  const niceSteps=imp?[0.05,0.1,0.25,0.5,1,2]:[0.2,0.5,1,2,5,10,20];
  const rawStep=yMax/4;
  const tickStep=niceSteps.find(s=>s>=rawStep*0.7)||1;
  const ticks=[];
  for(let v=0;v<=yMax*1.02;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>`+
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${typeof precipReadout==='function'?precipReadout(v):v.toFixed(1)}</text>`);
  }
  const pastLabel=relNow>1?`<text x="${(pL+4).toFixed(1)}" y="${(pT+12).toFixed(1)}" font-size="11" font-weight="650" fill="${c.muted}" text-anchor="start">PAST 24 H · OBSERVED</text>`:'';
  const cells=prob.map((p,i)=>{
    if(i<relNow||p==null) return '';
    const op=(0.06+0.94*(Math.max(0,Math.min(100,p))/100)).toFixed(3);
    return `<rect x="${(pL+i*slotW).toFixed(1)}" y="${pT}" width="${slotW.toFixed(1)}" height="16" fill="${c.rain}" opacity="${op}"/>`;
  }).join('');
  const chanceLabels=(()=>{
    const marks=[];
    for(let i=relNow;i<n;i++){
      const p=prob[i];
      if(p==null) continue;
      const prev=i>relNow?prob[i-1]:null;
      const next=i+1<n?prob[i+1]:null;
      const isFirst=i===relNow;
      const isPeak=p>=40 && (prev==null||p>=prev) && (next==null||p>=next) && (prev==null||next==null||p>prev||p>next);
      if(isFirst||isPeak) marks.push(i);
    }
    let lastX=-999;
    return marks.map(i=>{
      const x=xCx(i);
      if(x-lastX<36) return '';
      lastX=x;
      return `<text x="${x.toFixed(1)}" y="${(pT+28).toFixed(1)}" font-size="11" fill="${c.ink}" text-anchor="middle">${prob[i]}%</text>`;
    }).join('');
  })();
  const nowX=xCx(relNow).toFixed(1);
  const nowMark=`<line x1="${nowX}" y1="${pT}" x2="${nowX}" y2="${(plotTop+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3"/>`+
    `<text x="${nowX}" y="${(pT-6).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Now</text>`;
  const bars=precip.map((v,i)=>{
    const bH=Math.max(0,yf(0)-yf(v));
    if(bH<0.6) return '';
    const fill=i<relNow?c.rainPast:c.rainSolid;
    return `<rect x="${xBL(i).toFixed(1)}" y="${yf(v).toFixed(1)}" width="${barW.toFixed(1)}" height="${bH.toFixed(1)}" fill="${fill}" rx="1"/>`;
  }).join('');
  const normPts=[];
  if(normal){
    for(let i=relNow;i<n;i++){
      const nv=normal[+times[i].slice(11,13)];
      if(nv==null) continue;
      normPts.push(`${xCx(i).toFixed(1)},${yf(nv).toFixed(1)}`);
    }
  }
  const normLine=normPts.length>1?`<polyline points="${normPts.join(' ')}" fill="none" stroke="${c.ink}" stroke-width="1.4" stroke-dasharray="1.5,3" opacity="0.7"/>`:'';
  const usedX=new Set();
  const xLbls=times.map((t,i)=>{
    const hr=+t.slice(11,13);
    if(hr!==0&&hr!==12) return '';
    const xKey=Math.round(xCx(i));
    if(usedX.has(xKey)) return ''; usedX.add(xKey);
    const day=hr===0?`<text x="${xCx(i).toFixed(1)}" y="${(plotTop+14).toFixed(1)}" font-size="11" font-weight="650" fill="${c.ink}" text-anchor="middle">${new Date(t.slice(0,10)+'T12:00:00').toLocaleDateString('en-US',{weekday:'short'})}</text>`:'';
    return day+`<text x="${xCx(i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${hr===0?'12am':'12pm'}</text>`;
  }).join('');
  const usual=w.usual?times.map(t=>Math.round((w.usual[+t.slice(11,13)]||0)*100)):null;
  _hourlyRainData={precip,prob,pL,slotW,n,relNow,times,usual};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="hourly-rain" tabindex="0" role="img" aria-label="48-hour rainfall. Chance and amount are separate. The dotted line is the usual amount.">
    ${pastLabel}${cells}${chanceLabels}
    ${ticks.join('')}
    ${nowMark}
    <line id="ttg-hourly-rain" x1="${pL}" y1="${plotTop}" x2="${pL}" y2="${(plotTop+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${bars}${normLine}${xLbls}
  </svg>`;
}

function makeDailyRainChart(){
  if(!fcData?.daily?.time) return '';
  const c=_cc();
  const daily=fcData.daily;
  const todayStr=_nowParts().dateStr;
  let todayIdx=daily.time.findIndex(t=>t===todayStr);
  if(todayIdx<0) todayIdx=Math.min(7,daily.time.length-1);
  const n=daily.time.length;
  const precip=(daily.precipitation_sum||[]).map(v=>v??0);
  const probs=daily.precipitation_probability_max||[];
  const norms=(dailyRainHistData||[]);
  const byDate={};
  norms.forEach(r=>{ if(r?.date) byDate[r.date]=r; });
  const means=daily.time.map(t=>byDate[t]?.histMeanMm??null);
  const p90=byDate[daily.time[todayIdx]]?.p90Mm??null;
  const yMax=Math.max(...precip, ...means.filter(v=>v!=null), p90||0, 1)*1.25;
  const {W,H,pL,pR,pT,pB}=_dims(200,48,16,22,36);
  const cW=W-pL-pR, cH=H-pT-pB;
  const slotW=cW/n;
  const barW=slotW*0.55;
  const xCx=i=>pL+(i+0.5)*slotW;
  const xBL=i=>pL+i*slotW+(slotW-barW)/2;
  const yf=v=>pT+(1-Math.min(Math.max(v,0),yMax)/yMax)*cH;
  const niceSteps=imp?[0.05,0.1,0.25,0.5,1,2]:[0.5,1,2,5,10,20,50];
  const rawStep=yMax/4;
  const tickStep=niceSteps.find(s=>s>=rawStep*0.7)||1;
  const ticks=[];
  for(let v=0;v<=yMax*1.02;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>`+
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${typeof precipReadout==='function'?precipReadout(v):Math.round(v)}</text>`);
  }
  const todayX=xCx(todayIdx).toFixed(1);
  const todayMark=`<line x1="${todayX}" y1="${pT}" x2="${todayX}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3"/>`+
    `<text x="${todayX}" y="${(pT-3).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">Today</text>`;
  let maxI=0;
  precip.forEach((v,i)=>{ if(v>precip[maxI]) maxI=i; });
  const p90Line=p90!=null&&p90>0?`<line x1="${pL}" y1="${yf(p90).toFixed(1)}" x2="${W-pR}" y2="${yf(p90).toFixed(1)}" stroke="${c.muted}" stroke-width="1.2" stroke-dasharray="2,3"/>`+
    `<text x="${W-pR-2}" y="${(yf(p90)-4).toFixed(1)}" font-size="11" fill="${c.ink}" text-anchor="end">1-in-10 wet day</text>`:'';
  const els=daily.time.map((dateStr,i)=>{
    const mm=precip[i];
    const bx=xBL(i).toFixed(1);
    const bH=Math.max(0,yf(0)-yf(mm));
    const isPast=i<todayIdx;
    const bar=bH>0.6?`<rect x="${bx}" y="${yf(mm).toFixed(1)}" width="${barW.toFixed(1)}" height="${bH.toFixed(1)}" fill="${isPast?c.rainPast:c.rainSolid}" rx="2"/>`:'';
    const base=mm<0.1?`<line x1="${bx}" y1="${yf(0).toFixed(1)}" x2="${(+bx+barW).toFixed(1)}" y2="${yf(0).toFixed(1)}" stroke="${c.muted}" stroke-width="1.5"/>`:'';
    const mean=means[i];
    const tick=mean!=null?`<line x1="${bx}" y1="${yf(mean).toFixed(1)}" x2="${(+bx+barW).toFixed(1)}" y2="${yf(mean).toFixed(1)}" stroke="${c.ink}" stroke-width="1.8"/>`:'';
    const showLbl=i===maxI&&mm>=0.1;
    const num=imp?nP(mm).toFixed(mm>=25?1:2): (mm>=100?String(Math.round(mm)):mm.toFixed(1));
    const valLbl=showLbl?`<text x="${xCx(i).toFixed(1)}" y="${(yf(mm)-6).toFixed(1)}" font-size="11" font-weight="700" fill="${c.ink}" text-anchor="middle">${num}</text>`:'';
    const isToday=i===todayIdx;
    const showDay=isToday||!_narrow()||i%2===0;
    const dayLbl=showDay?(isToday?'Today':fDay(dateStr)):'';
    return bar+base+tick+valLbl+(dayLbl?`<text x="${xCx(i).toFixed(1)}" y="${H-8}" class="ca" font-weight="${isToday?700:400}" text-anchor="middle">${dayLbl}</text>`:'');
  }).join('');
  _dailyRainData={dates:daily.time,precip,probs,means,pL,slotW,n,todayIdx,p90};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="daily-rain" tabindex="0" role="img" aria-label="14-day rainfall. Ticks mark the usual amount. The dotted line is a 1-in-10 wet day.">
    ${ticks.join('')}${p90Line}${todayMark}
    <line id="ttg-daily-rain" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="${c.muted}" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${els}
  </svg>`;
}

function _monthActual(i){
  const row=ytdData?.monthly?.[i];
  if(!row||!row.days) return null;
  return row;
}

function makeClimateChart(){
  if(!climatologyData) return '<p class="search-msg" style="padding:20px 0">Loading climate data…</p>';
  const c=_cc();
  const data=climatologyData.months;
  const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const curMo=_nowParts().month;
  const n=12;
  const {W,H,pL,pR,pT,pB}=_dims(210,46,18,28,28);
  const cW=W-pL-pR, cH=H-pT-pB;
  const actual=data.map((_,i)=>_monthActual(i));
  const highs=[...data.map(d=>d.tMax), ...actual.map(a=>a?.tMax)].filter(v=>v!=null);
  const lows=[...data.map(d=>d.tMin), ...actual.map(a=>a?.tMin)].filter(v=>v!=null);
  if(!highs.length||!lows.length) return '';
  const tLoC=Math.min(...lows)-2, tHiC=Math.max(...highs)+2;
  const dispLo=nT(tLoC), dispHi=nT(tHiC);
  const yf=v=>pT+(1-(nT(v)-dispLo)/(dispHi-dispLo||1))*cH;
  const slotW=cW/n;
  const xCx=i=>pL+(i+0.5)*slotW;
  const tRange=dispHi-dispLo;
  const tStep=[2,5,10,20].find(s=>tRange/s>=2&&tRange/s<=7)||10;
  const ticks=[];
  for(let v=Math.ceil(dispLo/tStep)*tStep;v<=dispHi;v+=tStep){
    const y=(pT+(1-(v-dispLo)/(dispHi-dispLo||1))*cH).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>`+
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${Math.round(v)}°</text>`);
  }
  const top=data.map((d,i)=>d.tMax!=null?`${xCx(i).toFixed(1)},${yf(d.tMax).toFixed(1)}`:null).filter(Boolean);
  const bot=data.map((d,i)=>d.tMin!=null?`${xCx(i).toFixed(1)},${yf(d.tMin).toFixed(1)}`:null).filter(Boolean);
  const band=top.length&&bot.length?`<polygon points="${[...top,...bot.reverse()].join(' ')}" class="ch-band"/>`+
    `<text x="${(pL+8).toFixed(1)}" y="${((yf(data[0].tMax)+yf(data[0].tMin))/2+4).toFixed(1)}" font-size="11" fill="${c.ink}">Normal range</text>`:'';
  const actIdx=actual.map((a,i)=>a&&i<=curMo?i:-1).filter(i=>i>=0);
  const hiPts=actIdx.filter(i=>actual[i].tMax!=null).map(i=>`${xCx(i).toFixed(1)},${yf(actual[i].tMax).toFixed(1)}`).join(' ');
  const loPts=actIdx.filter(i=>actual[i].tMin!=null).map(i=>`${xCx(i).toFixed(1)},${yf(actual[i].tMin).toFixed(1)}`).join(' ');
  const dots=actIdx.map(i=>{
    const a=actual[i];
    const cx=xCx(i).toFixed(1);
    return (a.tMax!=null?`<circle cx="${cx}" cy="${yf(a.tMax).toFixed(1)}" r="3.2" fill="${c.hot}" stroke="${c.dot}" stroke-width="1.4"/>`:'')+
           (a.tMin!=null?`<circle cx="${cx}" cy="${yf(a.tMin).toFixed(1)}" r="3.2" fill="${c.cold}" stroke="${c.dot}" stroke-width="1.4"/>`:'');
  }).join('');
  let note='';
  let best=null;
  actIdx.forEach(i=>{
    const a=actual[i], d=data[i];
    if(a.tMax==null||a.tMin==null||d.tMax==null||d.tMin==null) return;
    const dep=(a.tMax+a.tMin)/2-(d.tMax+d.tMin)/2;
    if(!best||Math.abs(dep)>Math.abs(best.dep)) best={i,dep,a};
  });
  if(best){
    const shown=imp?Math.round(best.dep*9/5):Math.round(best.dep);
    const word=shown>0?`${shown}° above`:shown<0?`${Math.abs(shown)}° below`:'near normal';
    note=`<text x="${xCx(best.i).toFixed(1)}" y="${(yf(best.a.tMax)-10).toFixed(1)}" font-size="11" font-weight="650" fill="${c.ink}" text-anchor="middle">${Math.round(nT(best.a.tMax))}° · ${word}</text>`;
  }
  const xLbls=MON.map((m,i)=>`<text x="${xCx(i).toFixed(1)}" y="${H-6}" class="ca" text-anchor="middle" font-weight="${i===curMo?700:400}">${m}</text>`).join('');
  _climateData={data,actual,pL,slotW,n,kind:'temp'};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="climate" tabindex="0" role="img" aria-label="Monthly temperature. The band is the normal range. Dots are this year.">
    ${ticks.join('')}${band}
    ${hiPts?`<polyline points="${hiPts}" fill="none" stroke="${c.hot}" stroke-width="2"/>`:''}
    ${loPts?`<polyline points="${loPts}" fill="none" stroke="${c.cold}" stroke-width="2"/>`:''}
    ${dots}${note}${xLbls}
  </svg>`;
}

function makeClimateRainChart(){
  if(!climatologyData) return '';
  const c=_cc();
  const data=climatologyData.months;
  const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const curMo=_nowParts().month;
  const n=12;
  const actual=data.map((_,i)=>_monthActual(i));
  const rains=data.map(d=>d.rain||0);
  const acts=actual.map(a=>a?.rain||0);
  const yMax=Math.max(...rains, ...acts, 1)*1.15;
  const {W,H,pL,pR,pT,pB}=_dims(200,46,14,22,28);
  const cW=W-pL-pR, cH=H-pT-pB;
  const slotW=cW/n;
  const barW=slotW*0.28;
  const xN=i=>pL+i*slotW+slotW*0.18;
  const xA=i=>pL+i*slotW+slotW*0.52;
  const yf=v=>pT+(1-Math.min(v,yMax)/yMax)*cH;
  const steps=imp?[0.5,1,2,5]:[10,20,50,100,200];
  const step=steps.find(s=>yMax/s>=2&&yMax/s<=6)||(imp?1:50);
  const ticks=[];
  for(let v=0;v<=yMax;v+=step){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>`+
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${typeof precipReadout==='function'?precipReadout(v):Math.round(v)}</text>`);
  }
  const bars=data.map((d,i)=>{
    const nh=Math.max(0,yf(0)-yf(d.rain||0));
    const normal=nh>0.5?`<rect x="${xN(i).toFixed(1)}" y="${yf(d.rain||0).toFixed(1)}" width="${barW.toFixed(1)}" height="${nh.toFixed(1)}" fill="${c.muted}" opacity="0.45" rx="1"/>`:'';
    const a=actual[i];
    if(!a||a.rain==null||i>curMo) return normal;
    const ah=Math.max(0,yf(0)-yf(a.rain));
    const op=i===curMo?0.55:1;
    const act=ah>0.5?`<rect x="${xA(i).toFixed(1)}" y="${yf(a.rain).toFixed(1)}" width="${barW.toFixed(1)}" height="${ah.toFixed(1)}" fill="${c.rainSolid}" opacity="${op}" rx="1"/>`:'';
    return normal+act;
  }).join('');
  let note='';
  let best=null;
  actual.forEach((a,i)=>{
    if(!a||a.rain==null||i>curMo||data[i].rain==null) return;
    const dep=a.rain-data[i].rain;
    if(!best||Math.abs(dep)>Math.abs(best.dep)) best={i,dep};
  });
  if(best){
    const sign=best.dep>0?'above':'below';
    const txt=`${typeof precipReadout==='function'?precipReadout(Math.abs(best.dep)):Math.round(Math.abs(best.dep))} ${sign}`;
    note=`<text x="${(xA(best.i)+barW/2).toFixed(1)}" y="${(yf(actual[best.i].rain)-6).toFixed(1)}" font-size="11" font-weight="650" fill="${c.ink}" text-anchor="middle">${txt}</text>`;
  }
  const xLbls=MON.map((m,i)=>`<text x="${(pL+(i+0.5)*slotW).toFixed(1)}" y="${H-6}" class="ca" text-anchor="middle" font-weight="${i===curMo?700:400}">${m}</text>`).join('');
  _climateRainData={data,actual,pL,slotW,n};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="climate-rain" tabindex="0" role="img" aria-label="Monthly rainfall. Grey is the normal, colour is this year. The current month is still incomplete.">
    ${ticks.join('')}${bars}${note}${xLbls}
  </svg>`;
}
