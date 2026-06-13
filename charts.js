// ── Chart renderers ────────────────────────────────────

function _narrow(){ return typeof window!=='undefined'&&window.innerWidth<=480; }
function _chartPR(){ return _narrow()?42:14; }
function _hourStep(){ return _narrow()?12:6; }
function _hourLbl(hr){
  return hr===0?'Midnight':hr===12?'Noon':hr<12?`${hr}am`:`${hr-12}pm`;
}

function makeTempChart(){
  if(!fcData||!histData) return '';
  const d=fcData.daily;
  // Find today's index in the 14-day array (past_days:7 + forecast_days:7)
  const todayStr=localDateStr();
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
  const W=580,H=210,pL=46,pR=_chartPR(),pT=24,pB=38;
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
    const lbl=lblY?`<text x="${pL+4}" y="${(+lblY+4).toFixed(1)}" font-size="8.5" fill="#9ba3ae" opacity="0.8">Hist. avg</text>`:'';
    return `<polygon points="${poly}" class="ch-band"/>${lbl}`;
  })();
  // Vertical "Today" divider
  const todayX=xf(todayIdx).toFixed(1);
  const todayMark=`<line x1="${todayX}" y1="${pT}" x2="${todayX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${todayX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Today</text>`;
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
    const fill=isPast?'rgba(255,123,123,0.45)':'#ff7b7b';
    const lbl=!isPast?`<text x="${cx}" y="${(yf(v)-9).toFixed(1)}" class="cv cv-hot" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${isPast?2.8:3.5}" fill="${fill}" stroke="rgba(15,12,41,.9)" stroke-width="1.5"/>${lbl}`;
  }).join('');
  const mnDots=minV.map((v,i)=>{
    if(v==null) return '';
    const cx=xf(i).toFixed(1),cy=yf(v).toFixed(1);
    const isPast=i<todayIdx;
    const fill=isPast?'rgba(116,192,252,0.45)':'#74c0fc';
    const lbl=!isPast?`<text x="${cx}" y="${(yf(v)+15).toFixed(1)}" class="cv cv-cold" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${isPast?2.8:3.5}" fill="${fill}" stroke="rgba(15,12,41,.9)" stroke-width="1.5"/>${lbl}`;
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
    <line id="ttg-temp" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${pastMxPts}" class="cl cl-hot" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${pastMnPts}" class="cl cl-cold" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${fcstMxPts}" class="cl cl-hot"/>
    <polyline points="${fcstMnPts}" class="cl cl-cold"/>
    ${mxDots}${mnDots}
    ${(()=>{
      const hv=maxV[n-1],lv=minV[n-1];
      if(hv==null||lv==null) return '';
      const lx=(xf(n-1)+5).toFixed(1);
      return `<text x="${lx}" y="${(yf(hv)+4).toFixed(1)}" font-size="9" font-weight="700" fill="#c0392b">High</text>` +
             `<text x="${lx}" y="${(yf(lv)+4).toFixed(1)}" font-size="9" font-weight="700" fill="#2980b9">Low</text>`;
    })()}
    ${xLbls}
  </svg>`;
}

function makeRainYTDChart(){
  if(!ytdData) return '<p class="search-msg" style="padding:24px 0">⏳ Loading year-to-date rainfall…</p>';
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
  const W=580,H=222,pL=52,pR=_chartPR(),pT=20,pB=36;
  const cW=W-pL-pR,cH=H-pT-pB;
  const yMax=Math.max(...curV,...avgV,...(fcV.length?fcV:[0]),...(avgExtV.length?avgExtV:[0]),.01)*1.1;
  // x maps over the full totalN range so forecast extends naturally to the right
  const xf=i=>pL+(i/Math.max(totalN-1,1))*cW;
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
  const xGrid=monthMarks.slice(1).map(m=>`<line x1="${xf(m.i).toFixed(1)}" y1="${pT}" x2="${xf(m.i).toFixed(1)}" y2="${pT+cH}" class="cg"/>`).join('');
  const xLabels=monthMarks.map(m=>`<text x="${xf(m.i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${m.label}</text>`).join('');
  const curPts=curV.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const avgPts=avgV.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  // "Today" divider at the point where actual data ends and forecast begins
  const rainTodayX=xf(n-1).toFixed(1);
  const rainTodayMark=numFc>0?`<line x1="${rainTodayX}" y1="${pT}" x2="${rainTodayX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${rainTodayX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Today</text>`:''  ;
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
  const endLabels=`<text x="${+lx+5}" y="${(_ryCur+4).toFixed(1)}" font-size="8.5" font-weight="700" fill="rgba(102,126,234,1)" text-anchor="start">${thisYear}</text>` +
    `<text x="${+lx+5}" y="${(_ryAvg+4).toFixed(1)}" font-size="8.5" fill="#9ba3ae" text-anchor="start">Hist. avg</text>`;
  _rainData={labels,curV,avgV,thisYear,pL,cW,n,fcV,numFc,totalN,fcstDates};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="rain" tabindex="0" role="img">
    ${ticks.join('')}
    ${xGrid}
    <line id="ttg-rain" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${rainTodayMark}
    <polyline points="${avgPts}" class="cl-ytd-hist"/>
    ${avgExtPts?`<polyline points="${avgExtPts}" class="cl-ytd-hist"/>`:''}
    <polyline points="${curPts}" class="cl-ytd-cur"/>
    ${fcstPts?`<polyline points="${fcstPts}" stroke="rgba(102,126,234,.9)" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="5,4"/>`:''}
    <circle cx="${lx}" cy="${ly}" r="4" fill="rgba(102,126,234,.9)" stroke="rgba(15,12,41,.9)" stroke-width="1.5"/>
    ${endLabels}
    ${xLabels}
  </svg>`;
}

function makeHourlyTempChart(){
  if(!fcData?.hourly?.time) return '';
  if(!hourlyHistData) return '<p class="search-msg" style="padding:20px 0">⏳ Loading hourly history…</p>';
  const hh=fcData.hourly;
  const now=new Date();
  const pad=n=>String(n).padStart(2,'0');
  const nowStr=`${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:00`;
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
  const W=580,H=198,pL=46,pR=_chartPR(),pT=20,pB=32;
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
  // Now marker
  const nowX=xf(relNow).toFixed(1);
  const nowMark=`<line x1="${nowX}" y1="${pT}" x2="${nowX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${nowX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Now</text>`;
  // Polylines
  const histPts=histLine.map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const pastPts=temps.slice(0,relNow+1).map((v,i)=>`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  const fcstPts=temps.slice(relNow).map((v,i)=>`${xf(relNow+i).toFixed(1)},${yf(v).toFixed(1)}`).join(' ');
  // Dots at 6-hour marks; value labels on forecast 6h marks only
  const dots=temps.map((v,i)=>{
    if(v==null) return '';
    const hr=+slicedTime[i].slice(11,13);
    const is6h=hr%6===0;
    if(!is6h) return '';
    const isPast=i<relNow;
    const cx=xf(i).toFixed(1),cy=yf(v).toFixed(1);
    const fill=isPast?'rgba(255,100,100,0.45)':'#ff7b7b';
    const r=isPast?2.5:3;
    const lbl=!isPast&&is6h?`<text x="${cx}" y="${(yf(v)-8).toFixed(1)}" class="cv cv-hot" text-anchor="middle">${Math.round(v)}°</text>`:'';
    return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${fill}" stroke="rgba(15,12,41,.9)" stroke-width="1.5"/>${lbl}`;
  }).join('');
  // X-axis labels every 6h
  const usedX=new Set();
  const xLbls=slicedTime.map((t,i)=>{
    const hr=+t.slice(11,13);
    const step=_hourStep();
    if(hr%step!==0) return '';
    const xKey=Math.round(xf(i));
    if(usedX.has(xKey)) return ''; usedX.add(xKey);
    return `<text x="${xf(i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${_hourLbl(hr)}</text>`;
  }).join('');
  // End labels (replacing legend) — separate vertically if lines converge
  const endX=(xf(n-1)+5).toFixed(1);
  const endTmpY=temps[n-1]!=null?yf(temps[n-1]):null;
  const endAvgY=histLine[n-1]!=null?yf(histLine[n-1]):null;
  let _heTmp=endTmpY, _heAvg=endAvgY;
  if(_heTmp!=null&&_heAvg!=null){
    const _heSep=_heTmp-_heAvg;
    if(Math.abs(_heSep)<13){const bump=(13-Math.abs(_heSep))/2+1;_heTmp+=_heSep>=0?bump:-bump;_heAvg+=_heSep>=0?-bump:bump;}
  }
  const endLbls=[
    _heTmp!=null?`<text x="${endX}" y="${(_heTmp+4).toFixed(1)}" font-size="8.5" font-weight="700" fill="#c0392b">Forecast</text>`:'',
    _heAvg!=null?`<text x="${endX}" y="${(_heAvg+4).toFixed(1)}" font-size="8.5" fill="#9ba3ae">5-yr avg</text>`:''
  ].join('');
  _hourlyData={temps,histLine,pL,cW,n,nowIdx:relNow,times:slicedTime};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="hourly" tabindex="0" role="img">
    ${ticks.join('')}
    ${nowMark}
    <line id="ttg-hourly" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${histPts}" class="cl-ytd-hist"/>
    <polyline points="${pastPts}" class="cl cl-hot" stroke-dasharray="5,4" opacity="0.55"/>
    <polyline points="${fcstPts}" class="cl cl-hot"/>
    ${dots}
    ${endLbls}
    ${xLbls}
  </svg>`;
}

function makeHourlyRainChart(){
  if(!fcData?.hourly?.time) return '';
  const hh=fcData.hourly;
  const now=new Date();
  const pad=n=>String(n).padStart(2,'0');
  const nowStr=`${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:00`;
  const rawNow=hh.time.findIndex(t=>t>=nowStr);
  const nowIdx=rawNow<1?1:rawNow;
  // Past 24h actual + next 24h forecast = 48h total, same window as temp chart
  const startIdx=Math.max(0,nowIdx-24);
  const endIdx=Math.min(hh.time.length,nowIdx+24);
  const times=hh.time.slice(startIdx,endIdx);
  const precip=(hh.precipitation||[]).slice(startIdx,endIdx).map(v=>v??0);
  const prob=(hh.precipitation_probability||[]).slice(startIdx,endIdx);
  const n=times.length;
  if(!n) return '';
  const relNow=nowIdx-startIdx;
  const yMax=Math.max(...precip,0.5)*1.25;
  const W=580,H=185,pL=46,pR=_chartPR(),pT=20,pB=36;
  const cW=W-pL-pR,cH=H-pT-pB;
  const slotW=cW/n;
  const barW=Math.max(2,slotW*0.72);
  const xCx=i=>pL+(i+0.5)*slotW;
  const xBL=i=>pL+i*slotW+(slotW-barW)/2;
  const yf=v=>pT+(1-Math.min(v,yMax)/yMax)*cH;
  // Y ticks
  const niceSteps=imp?[0.01,0.05,0.1,0.25,0.5,1,2]:[0.1,0.2,0.5,1,2,5,10];
  const rawStep=yMax/4;
  const tickStep=niceSteps.find(s=>s>=rawStep*0.7)||Math.ceil(rawStep*10)/10;
  const fmtY=v=>imp?(v<0.1?v.toFixed(2):v.toFixed(1))+'"':v<1?v.toFixed(1)+'mm':Math.round(v)+'mm';
  const ticks=[];
  for(let v=0;v<=yMax*1.05;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${fmtY(v)}</text>`);
  }
  // "Now" divider in the middle, same as temp chart
  const nowX=xCx(relNow).toFixed(1);
  const nowMark=`<line x1="${nowX}" y1="${pT}" x2="${nowX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${nowX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Now</text>`;
  // Bars — past faded, forecast solid
  const bars=precip.map((v,i)=>{
    const bx=xBL(i).toFixed(1);
    const bH=Math.max(0,yf(0)-yf(v));
    if(bH<0.5) return '';
    const fill=i<relNow?'rgba(102,126,234,0.3)':'rgba(102,126,234,0.8)';
    return `<rect x="${bx}" y="${yf(v).toFixed(1)}" width="${barW.toFixed(1)}" height="${bH.toFixed(1)}" fill="${fill}" rx="1"/>`;
  }).join('');
  // Probability text above forecast bars only (>=20%)
  const probLbls=prob.map((p,i)=>{
    if(i<relNow||p==null||p<20) return '';
    const ty=(yf(precip[i]??0)-4).toFixed(1);
    return `<text x="${xCx(i).toFixed(1)}" y="${ty}" font-size="7" fill="rgba(41,128,185,0.85)" text-anchor="middle">${p}%</text>`;
  }).join('');
  // X labels every 6h
  const usedX=new Set();
  const xLbls=times.map((t,i)=>{
    const hr=+t.slice(11,13);
    const step=_hourStep();
    if(hr%step!==0) return '';
    const xKey=Math.round(xCx(i)); if(usedX.has(xKey)) return ''; usedX.add(xKey);
    return `<text x="${xCx(i).toFixed(1)}" y="${H-6}" class="ca" text-anchor="middle">${_hourLbl(hr)}</text>`;
  }).join('');
  _hourlyRainData={precip,prob,pL,slotW,n,relNow,times};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="hourly-rain" tabindex="0" role="img">
    ${ticks.join('')}
    ${nowMark}
    <line id="ttg-hourly-rain" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${bars}
    ${xLbls}
  </svg>`;
}

function makeDailyRainChart(){
  if(!fcData?.daily?.time) return '';
  const daily=fcData.daily;
  // With past_days:7, index 7 is today — all 14 days are already in fcData
  const todayIdx=Math.min(7,daily.time.length-1);
  const n=daily.time.length; // 14
  const precip=(daily.precipitation_sum||[]).map(v=>v??0);
  const probs=daily.precipitation_probability_max||[];
  const W=580,H=185,pL=46,pR=_chartPR(),pT=20,pB=38;
  const cW=W-pL-pR,cH=H-pT-pB;
  const yMax=Math.max(...precip,1)*1.2;
  const slotW=cW/n;
  const barW=slotW*0.6;
  const xCx=i=>pL+(i+0.5)*slotW;
  const xBL=i=>pL+i*slotW+(slotW-barW)/2;
  const yf=v=>pT+(1-Math.min(v,yMax)/yMax)*cH;
  // Y ticks
  const niceSteps=imp?[0.05,0.1,0.25,0.5,1,2,5]:[0.5,1,2,5,10,20,50];
  const rawStep=yMax/4;
  const tickStep=niceSteps.find(s=>s>=rawStep*0.7)||1;
  const fmtY=v=>imp?(v<0.1?v.toFixed(2):v.toFixed(1))+'"':(v<1?v.toFixed(1):Math.round(v))+'mm';
  const fmtMm=v=>imp?(v<0.1?'—':v.toFixed(2)+'"'):(v<0.1?'—':v.toFixed(1)+'mm');
  const ticks=[];
  for(let v=0;v<=yMax*1.05;v+=tickStep){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${fmtY(v)}</text>`);
  }
  // Today divider
  const todayX=xCx(todayIdx).toFixed(1);
  const todayMark=`<line x1="${todayX}" y1="${pT}" x2="${todayX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${todayX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Today</text>`;
  // Bars and labels
  const els=daily.time.map((dateStr,i)=>{
    const mm=precip[i], cx=xCx(i).toFixed(1), bx=xBL(i).toFixed(1);
    const bH=Math.max(0,yf(0)-yf(mm));
    const isPast=i<todayIdx;
    const fill=isPast?'rgba(102,126,234,0.3)':'rgba(102,126,234,0.8)';
    const bar=bH>0.5?`<rect x="${bx}" y="${yf(mm).toFixed(1)}" width="${barW.toFixed(1)}" height="${bH.toFixed(1)}" fill="${fill}" rx="2"/>`:''
    const valLbl=mm>=0.1?`<text x="${cx}" y="${(yf(mm)-5).toFixed(1)}" font-size="8" fill="rgba(102,126,234,0.9)" text-anchor="middle">${fmtMm(mm)}</text>`:''
    const isToday=i===todayIdx;
    const showDayLbl=isToday||!_narrow()||i%2===0;
    const dayLbl=showDayLbl?(isToday?'Today':fDay(dateStr)):'';
    const prob=probs[i];
    const probLbl=!isPast&&prob!=null?`<text x="${cx}" y="${H-8}" font-size="7.5" fill="rgba(41,128,185,0.8)" text-anchor="middle">${prob}%</text>`:'';
    return bar+valLbl+
      (dayLbl?`<text x="${cx}" y="${H-22}" class="ca" font-weight="${isToday?700:400}" text-anchor="middle">${dayLbl}</text>`:'')+
      probLbl;
  }).join('');
  _dailyRainData={dates:daily.time,precip,probs,pL,slotW,n,todayIdx};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="daily-rain" tabindex="0" role="img">
    ${ticks.join('')}
    ${todayMark}
    <line id="ttg-daily-rain" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${els}
  </svg>`;
}

function makeHourlyHumidChart(){
  if(!fcData?.hourly?.time) return '';
  if(!hourlyHumidData) return '<p class="search-msg" style="padding:20px 0">⏳ Loading humidity history…</p>';
  const hh=fcData.hourly;
  const now=new Date();
  const pad=n=>String(n).padStart(2,'0');
  const nowStr=`${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:00`;
  const rawNow=hh.time.findIndex(t=>t>=nowStr);
  const nowIdx=rawNow<1?1:rawNow;
  const startIdx=Math.max(0,nowIdx-24), endIdx=Math.min(hh.time.length,nowIdx+24);
  const times=hh.time.slice(startIdx,endIdx);
  const humid=(hh.relative_humidity_2m||[]).slice(startIdx,endIdx);
  const n=times.length; if(!n) return '';
  const relNow=nowIdx-startIdx;
  const histLine=times.map(t=>hourlyHumidData.avgByHour[+t.slice(11,13)]??null);
  // carry forward any nulls
  let lastH=null, lastA=null;
  const hVals=humid.map(v=>{if(v!=null)lastH=v; return lastH;});
  const aVals=histLine.map(v=>{if(v!=null)lastA=v; return lastA;});
  const allV=[...hVals,...aVals].filter(v=>v!=null);
  if(!allV.length) return '';
  const lo=Math.max(0,Math.floor(Math.min(...allV)/10)*10-10);
  const hi=Math.min(100,Math.ceil(Math.max(...allV)/10)*10+5);
  const W=580,H=185,pL=46,pR=_chartPR(),pT=20,pB=32;
  const cW=W-pL-pR,cH=H-pT-pB;
  const xf=i=>pL+i/(n-1)*cW;
  const yf=v=>pT+(1-(v-lo)/(hi-lo))*cH;
  // Y ticks every 10%
  const ticks=[];
  for(let v=Math.ceil(lo/10)*10;v<=hi;v+=10){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${v}%</text>`);
  }
  // Now divider
  const nowX=xf(relNow).toFixed(1);
  const nowMark=`<line x1="${nowX}" y1="${pT}" x2="${nowX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${nowX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Now</text>`;
  // Polylines
  const histPts=aVals.map((v,i)=>v!=null?`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`:null).filter(Boolean).join(' ');
  const pastPts=hVals.slice(0,relNow+1).map((v,i)=>v!=null?`${xf(i).toFixed(1)},${yf(v).toFixed(1)}`:null).filter(Boolean).join(' ');
  const fcstPts=hVals.slice(relNow).map((v,i)=>v!=null?`${xf(relNow+i).toFixed(1)},${yf(v).toFixed(1)}`:null).filter(Boolean).join(' ');
  // End labels
  const endX=(xf(n-1)+5).toFixed(1);
  const eFC=hVals[n-1], eHI=aVals[n-1];
  let yFC=eFC!=null?yf(eFC):null, yHI=eHI!=null?yf(eHI):null;
  if(yFC!=null&&yHI!=null&&Math.abs(yFC-yHI)<12){const b=(12-Math.abs(yFC-yHI))/2+1;yFC+=(yFC>=yHI?b:-b);yHI+=(yHI>yFC?b:-b);}
  const endLbls=(yFC!=null?`<text x="${endX}" y="${(yFC+4).toFixed(1)}" font-size="8.5" font-weight="700" fill="#4bc6b9">Forecast</text>`:'')+
    (yHI!=null?`<text x="${endX}" y="${(yHI+4).toFixed(1)}" font-size="8.5" fill="#9ba3ae">5-yr avg</text>`:'');
  // X labels every 6h
  const usedX=new Set();
  const xLbls=times.map((t,i)=>{
    const hr=+t.slice(11,13);
    const step=_hourStep();
    if(hr%step!==0) return '';
    const xk=Math.round(xf(i)); if(usedX.has(xk))return ''; usedX.add(xk);
    return `<text x="${xf(i).toFixed(1)}" y="${H-4}" class="ca" text-anchor="middle">${_hourLbl(hr)}</text>`;
  }).join('');
  _hourlyHumidData={hVals,aVals,pL,cW,n,relNow,times};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="hourly-humid" tabindex="0" role="img">
    ${ticks.join('')}
    ${nowMark}
    <line id="ttg-hourly-humid" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    <polyline points="${histPts}" class="cl-ytd-hist"/>
    <polyline points="${pastPts}" fill="none" stroke="rgba(75,198,185,0.5)" stroke-width="2" stroke-dasharray="5,4" stroke-linejoin="round" stroke-linecap="round"/>
    <polyline points="${fcstPts}" fill="none" stroke="#4bc6b9" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
    ${endLbls}
    ${xLbls}
  </svg>`;
}

function makeDailyHumidChart(){
  if(!fcData?.hourly?.time) return '';
  if(!hourlyHumidData) return '<p class="search-msg" style="padding:20px 0">⏳ Loading humidity history…</p>';
  const hh=fcData.hourly;
  // Build day→hourly values map from the full hourly array
  const dayMap={};
  hh.time.forEach((t,i)=>{
    const d=t.slice(0,10);
    if(!dayMap[d]) dayMap[d]=[];
    const v=hh.relative_humidity_2m?.[i];
    if(v!=null) dayMap[d].push(v);
  });
  const avg=arr=>arr.length?arr.reduce((a,b)=>a+b,0)/arr.length:null;
  // 4 bars only: yesterday, today, tomorrow, day+2
  const todayIdx=Math.min(7,fcData.daily.time.length-1);
  const sliceStart=Math.max(0,todayIdx-1);
  const dates=fcData.daily.time.slice(sliceStart,sliceStart+4);
  const n=dates.length;
  const relToday=todayIdx-sliceStart; // position of "today" within the 4-bar slice
  const dailyMean=dates.map(d=>{
    const vals=dayMap[d]||[];
    return vals.length>=6?avg(vals):null;
  });
  // Historical mean = seasonal baseline from hourly normals
  const histAvgs=hourlyHumidData.avgByHour.filter(v=>v!=null);
  const histMean=histAvgs.length?histAvgs.reduce((a,b)=>a+b,0)/histAvgs.length:null;
  const allV=dailyMean.filter(v=>v!=null);
  if(!allV.length) return '';
  const lo=Math.max(0,Math.floor(Math.min(...allV,(histMean??100))/10)*10-10);
  const hi=Math.min(100,Math.ceil(Math.max(...allV,(histMean??0))/10)*10+5);
  const W=580,H=185,pL=46,pR=_chartPR(),pT=20,pB=38;
  const cW=W-pL-pR,cH=H-pT-pB;
  const slotW=cW/n;
  const barW=slotW*0.6;
  const xCx=i=>pL+(i+0.5)*slotW;
  const xBL=i=>pL+i*slotW+(slotW-barW)/2;
  const yf=v=>pT+(1-(v-lo)/(hi-lo))*cH;
  const ticks=[];
  for(let v=Math.ceil(lo/10)*10;v<=hi;v+=10){
    const y=yf(v).toFixed(1);
    ticks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${v}%</text>`);
  }
  // Seasonal avg reference line
  const histY=histMean!=null?yf(histMean).toFixed(1):null;
  const histLine=histY?`<line x1="${pL}" y1="${histY}" x2="${W-pR}" y2="${histY}" class="cl-ytd-hist"/>` +
    `<text x="${(W-pR+5).toFixed(1)}" y="${(+histY+4).toFixed(1)}" font-size="8.5" fill="#9ba3ae">Avg</text>`:'';
  // Today divider
  const todayX=xCx(relToday).toFixed(1);
  const todayMark=`<line x1="${todayX}" y1="${pT}" x2="${todayX}" y2="${(pT+cH).toFixed(1)}" stroke="#9ba3ae" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>` +
    `<text x="${todayX}" y="${pT-4}" font-size="8" font-weight="700" fill="#9ba3ae" text-anchor="middle">Today</text>`;
  const els=dates.map((dateStr,i)=>{
    const mm=dailyMean[i];
    const isPast=i<relToday, isToday=i===relToday;
    const bx=xBL(i).toFixed(1), cx=xCx(i).toFixed(1);
    const dayLabel=(!isToday&&_narrow()&&i%2!==0)?'':`<text x="${cx}" y="${H-22}" class="ca" font-weight="${isToday?700:400}" text-anchor="middle">${isToday?'Today':fDay(dateStr)}</text>`;
    if(mm==null) return ''; // skip days with insufficient data
    const bH=Math.max(0,yf(lo)-yf(mm));
    const fill=isPast?'rgba(75,198,185,0.3)':'rgba(75,198,185,0.8)';
    const bar=bH>0.5?`<rect x="${bx}" y="${yf(mm).toFixed(1)}" width="${barW.toFixed(1)}" height="${bH.toFixed(1)}" fill="${fill}" rx="2"/>`:''
    return bar+dayLabel;
  }).join('');
  _dailyHumidData={dailyMean,histMean,dates,pL,slotW,n,todayIdx:relToday};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="daily-humid" tabindex="0" role="img">
    ${ticks.join('')}
    ${todayMark}
    ${histLine}
    <line id="ttg-daily-humid" x1="${pL}" y1="${pT}" x2="${pL}" y2="${(pT+cH).toFixed(1)}" stroke="rgba(255,255,255,.18)" stroke-width="1" stroke-dasharray="3,3" visibility="hidden"/>
    ${els}
  </svg>`;
}

function makeClimateChart(){
  if(!climatologyData) return '<p class="search-msg" style="padding:20px 0">⏳ Loading climate data…</p>';
  const{months:data,yearStart,yearEnd}=climatologyData;
  const MON=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const curMo=new Date().getMonth();
  const n=12;
  const W=580,H=200,pL=46,pR=_narrow()?58:54,pT=24,pB=28;
  const cW=W-pL-pR,cH=H-pT-pB;
  // Temperature axis (left) — store in °C, display in user units
  const tMaxes=data.map(d=>d.tMax).filter(v=>v!=null);
  const tMins=data.map(d=>d.tMin).filter(v=>v!=null);
  const tLoC=Math.min(...tMins)-2, tHiC=Math.max(...tMaxes)+2;
  const dispLoT=nT(tLoC), dispHiT=nT(tHiC);
  const yfT=v=>pT+(1-(nT(v)-dispLoT)/(dispHiT-dispLoT))*cH;
  // Rainfall axis (right)
  const rains=data.map(d=>d.rain).filter(v=>v!=null);
  const rMaxMm=Math.max(...rains,imp?25.4:10)*1.15;
  const dispR=v=>imp?(v*0.0393701).toFixed(1)+'"':Math.round(v)+'mm';
  const yfR=v=>pT+(1-v/rMaxMm)*cH;
  const slotW=cW/n;
  const barW=slotW*0.65;
  const xCx=i=>pL+(i+0.5)*slotW;
  const xBL=i=>pL+i*slotW+(slotW-barW)/2;
  // Left (temp) axis ticks
  const tRange=dispHiT-dispLoT;
  const tStepOpts=imp?[5,10,20]:[2,5,10,20];
  const tStep=tStepOpts.find(s=>tRange/s>=2&&tRange/s<=7)||10;
  const tTicks=[];
  for(let v=Math.ceil(dispLoT/tStep)*tStep;v<=dispHiT;v+=tStep){
    const y=(pT+(1-(v-dispLoT)/(dispHiT-dispLoT))*cH).toFixed(1);
    tTicks.push(`<line x1="${pL}" y1="${y}" x2="${W-pR}" y2="${y}" class="cg"/>` +
      `<text x="${pL-5}" y="${+y+4}" class="ca" text-anchor="end">${Math.round(v)}°</text>`);
  }
  // Right (rain) axis ticks
  const rStepOpts=imp?[0.5,1,2,5]:[10,20,50,100,200];
  const rStep=rStepOpts.find(s=>rMaxMm/s>=2&&rMaxMm/s<=6)||(imp?1:20);
  const rTicks=[];
  for(let v=0;v<=rMaxMm;v+=rStep){
    const y=yfR(v).toFixed(1);
    rTicks.push(`<text x="${W-pR+6}" y="${+y+4}" class="ca" text-anchor="start">${dispR(v)}</text>`);
  }
  // Current month highlight
  const curHL=`<rect x="${xBL(curMo).toFixed(1)}" y="${pT}" width="${barW.toFixed(1)}" height="${cH}" fill="rgba(255,200,50,0.09)" rx="1"/>`;
  // Rainfall bars
  const bars=data.map((d,i)=>{
    if(d.rain==null) return '';
    const bH=Math.max(0,yfR(0)-yfR(d.rain));
    if(bH<0.5) return '';
    return `<rect x="${xBL(i).toFixed(1)}" y="${yfR(d.rain).toFixed(1)}" width="${barW.toFixed(1)}" height="${bH.toFixed(1)}" fill="rgba(102,126,234,0.45)" rx="2"/>`;
  }).join('');
  // Temperature polylines
  const hotPts=data.map((d,i)=>d.tMax!=null?`${xCx(i).toFixed(1)},${yfT(d.tMax).toFixed(1)}`:null).filter(Boolean).join(' ');
  const coldPts=data.map((d,i)=>d.tMin!=null?`${xCx(i).toFixed(1)},${yfT(d.tMin).toFixed(1)}`:null).filter(Boolean).join(' ');
  // Dots at each month
  const dots=data.map((d,i)=>{
    const cx=xCx(i).toFixed(1), r=i===curMo?4:3;
    return (d.tMax!=null?`<circle cx="${cx}" cy="${yfT(d.tMax).toFixed(1)}" r="${r}" fill="#ff7b7b" stroke="rgba(15,12,41,.9)" stroke-width="1.5"/>`:'') +
           (d.tMin!=null?`<circle cx="${cx}" cy="${yfT(d.tMin).toFixed(1)}" r="${r}" fill="#74c0fc" stroke="rgba(15,12,41,.9)" stroke-width="1.5"/>`:'');
  }).join('');
  // End-of-line labels
  const endX=(xCx(11)+5).toFixed(1);
  const lastHot=data[11]?.tMax, lastCold=data[11]?.tMin;
  const endLbls=(lastHot!=null?`<text x="${endX}" y="${(yfT(lastHot)+4).toFixed(1)}" font-size="8.5" font-weight="600" fill="#c0392b">High</text>`:'')+
    (lastCold!=null?`<text x="${endX}" y="${(yfT(lastCold)+4).toFixed(1)}" font-size="8.5" font-weight="600" fill="#4a9eda">Low</text>`:'');
  // X axis
  const xLbls=MON.map((m,i)=>
    `<text x="${xCx(i).toFixed(1)}" y="${H-6}" class="ca" text-anchor="middle" font-weight="${i===curMo?700:400}">${m}</text>`
  ).join('');
  _climateData={data,pL,slotW,n};
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg" data-chart="climate" tabindex="0" role="img">
    ${tTicks.join('')}
    ${rTicks.join('')}
    ${curHL}
    ${bars}
    <polyline points="${hotPts}" fill="none" stroke="#ff7b7b" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
    <polyline points="${coldPts}" fill="none" stroke="#74c0fc" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
    ${dots}
    ${endLbls}
    ${xLbls}
  </svg>`;
}
