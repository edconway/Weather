// Presentation for the UX review: one scrolling page, charts against what is normal.
// Apple Weather minute data is not available without a key. Rain timing uses
// Open-Meteo 15-minute blocks when that feed returns, and hourly totals otherwise.

let wbExpanded=false;
let _screenKey='';
const readoutBase={};
const MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December'];
const HOW={
  hourly:'Each hour is the observed or forecast temperature, compared with the average of that same hour over the last five years.',
  temp:'The day’s high and low are compared with the midpoint of the normal high and low for that date. The band is a 7-day rolling normal.',
  'hourly-wb':'Wet bulb is the temperature a wet thermometer would read. It is compared with the average of that hour over the last five years.',
  'wet-bulb':'Daily wet-bulb high and low against the normal range for those dates.',
  'hourly-rain':'Amount and chance are drawn as two strips so they do not share a scale. The dotted line is the usual amount for that hour. Past hours are observed.',
  'daily-rain':'Each bar is the day’s rainfall. The tick is the usual amount for that date. The dotted line is today’s 1-in-10 wet day.',
  rain:'The line is cumulative rainfall since 1 January, against the average of the same calendar day in earlier years. The dashed part is the forecast.',
  climate:'The band is the normal monthly high and low. Dots, when they have loaded, are this year’s monthly means through the current month.',
  'climate-rain':'Grey bars are the normal monthly rainfall. Coloured bars are this year. The current month is incomplete, so it is drawn lighter.'
};

function alertPrefs(){
  const p=loadPrefs();
  return {start:!!p.alertStart, heavy:!!p.alertHeavy, dismissed:!!p.alertOfferDismissed};
}
function shortLabel(full){
  if(!full) return '';
  const parts=String(full).split(',').map(s=>s.trim()).filter(Boolean);
  if(parts.length>=2 && parts[0].toLowerCase()===parts[1].toLowerCase()) return parts[0];
  if(parts.length>=2) return `${parts[0]}, ${parts[1]}`;
  return parts[0]||String(full);
}
function savedList(){
  const p=loadPrefs();
  let list=Array.isArray(p.savedLocations)?p.savedLocations.filter(x=>x&&x.lat!=null):[];
  if(!list.length && p.customLat!=null && p.customName){
    list=[{lat:+p.customLat,lon:+p.customLon,name:String(p.customName),region:'',country:'',label:shortLabel(p.customName)}];
  }
  return list.slice(0,8);
}
function kmBetween(a,b){
  if(!a||!b||a.lat==null||b.lat==null) return Infinity;
  const R=6371, p=Math.PI/180;
  const dLat=(b.lat-a.lat)*p, dLon=(b.lon-a.lon)*p;
  const s=Math.sin(dLat/2)**2+Math.cos(a.lat*p)*Math.cos(b.lat*p)*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.min(1,Math.sqrt(s)));
}
function rememberPlace(p){
  if(!p||p.lat==null) return;
  const list=[p, ...savedList().filter(x=>kmBetween(x,p)>2)].slice(0,8);
  customLat=p.lat; customLon=p.lon; customName=p.label||p.name;
  savePrefs({savedLocations:list, customLat:p.lat, customLon:p.lon, customName:customName});
}
function todayIdx(){
  const s=placeNowParts().dateStr;
  const i=(fcData?.daily?.time||[]).findIndex(t=>t===s);
  return i<0?0:i;
}
function nowHourIdx(){
  const hh=fcData?.hourly;
  if(!hh?.time?.length) return 0;
  const i=hh.time.findIndex(t=>t>=placeNowParts().hourStr);
  return i<0?hh.time.length-1:i;
}
function placeIsDay(){
  const v=fcData?.hourly?.is_day?.[nowHourIdx()];
  if(v==null){ const h=placeNowParts().hour; return h>=6 && h<20; }
  return v===1;
}
function conditionName(code){
  const c=code??0;
  if(c===0) return 'Clear';
  if(c===1) return 'Mainly clear';
  if(c===2) return 'Partly cloudy';
  if(c===3) return 'Overcast';
  if(c===45||c===48) return 'Fog';
  if(c>=51&&c<=57) return 'Drizzle';
  if(c>=61&&c<=67) return 'Rain';
  if(c>=71&&c<=77) return 'Snow';
  if(c>=80&&c<=82) return 'Showers';
  if(c>=85&&c<=86) return 'Snow showers';
  if(c>=96) return 'Hail';
  if(c>=95) return 'Thunderstorm';
  return wmo(c).l;
}
function skyName(code, day){
  let k='clear';
  if(code===45||code===48) k='fog';
  else if(code>=95) k='storm';
  else if((code>=71&&code<=77)||code===85||code===86) k='snow';
  else if(code>=51) k='rain';
  else if(code>=2) k='cloud';
  return `${k}-${day?'day':'night'}`;
}
function monthPart(day){ return day<=10?'early':day<=20?'mid':'late'; }
function dayPart(hour){
  if(hour>=5&&hour<12) return 'morning';
  if(hour>=12&&hour<18) return 'afternoon';
  if(hour>=18&&hour<22) return 'evening';
  return 'overnight';
}
function weekdayName(dateStr, kind){
  const [Y,M,D]=dateStr.split('-').map(Number);
  return new Date(Date.UTC(Y,M-1,D)).toLocaleDateString('en-US',{weekday:kind||'long', timeZone:'UTC'});
}
function hourClock(hr){
  if(hr===0||hr===24) return '12am';
  if(hr===12) return '12pm';
  return hr<12?`${hr}am`:`${hr-12}pm`;
}
function clock12(utc){
  const off=(fcData?.utc_offset_seconds||0)*1000;
  const d=new Date(utc+off);
  return hourClock(d.getUTCHours()).replace(/(am|pm)$/, (m,ap)=>d.getUTCMinutes()?`:${padDate(d.getUTCMinutes())}${ap}`:ap);
}
function degFrom(deltaC){
  const near=Math.abs(deltaC)<1;
  const shown=imp?Math.round(deltaC*9/5):Math.round(deltaC);
  const abs=Math.abs(shown);
  if(near||abs<1) return {near:true, text:'near normal', abs:0, warmer:deltaC>0};
  return {near:false, text:`${abs}° ${shown>0?'warmer':'colder'}`, abs, warmer:shown>0};
}
function dayAnomC(i){
  const d=fcData?.daily;
  if(!d) return null;
  const hi=d.temperature_2m_max?.[i], lo=d.temperature_2m_min?.[i];
  const band=(histData?.dailyAvg||[]).find(a=>a.date===d.time[i]);
  if(hi==null||lo==null||!band||band.tMax==null||band.tMin==null) return null;
  return (hi+lo)/2-(band.tMax+band.tMin)/2;
}
function tempParts(c){
  if(c==null||isNaN(+c)) return {num:'—', unit:''};
  return {num:String(fTn(c)), unit:imp?'°F':'°C'};
}
function approxMm(mm){
  if(mm==null||isNaN(+mm)) return '';
  const p=precipParts(mm);
  return `~${p.num}${p.unit}`;
}
function uvBits(u){
  if(u==null||isNaN(+u)) return '—';
  const n=+u;
  const w=n<=2?'Low':n<=5?'Moderate':n<=7?'High':n<=10?'Very high':'Extreme';
  return `${w} · ${n.toFixed(1)}`;
}
function precipWord(hourIdx){
  const hh=fcData?.hourly||{};
  const code=hh.weather_code?.[hourIdx];
  if(code>=96) return 'Hail';
  if(code===56||code===57||code===66||code===67) return 'Sleet';
  const snow=hh.snowfall?.[hourIdx]||0;
  const rain=(hh.rain?.[hourIdx]||0)+(hh.showers?.[hourIdx]||0);
  if((snow>rain && snow>=0.05) || (code>=71 && code<=86)) return 'Snow';
  return 'Rain';
}

function minuteBlocks(){
  const m=fcData?.minutely_15;
  if(!m?.time?.length) return null;
  const off=(fcData.utc_offset_seconds||0)*1000;
  const now=Date.now();
  const parsed=m.time.map((t,i)=>{
    const [ds,hs]=t.split('T');
    const [Y,Mo,D]=ds.split('-').map(Number);
    const [h,mi]=(hs||'0:0').split(':').map(Number);
    const utc=Date.UTC(Y,Mo-1,D,h,mi)-off;
    const mm=+m.precipitation?.[i]||0;
    const snow=+m.snowfall?.[i]||0;
    const rain=+m.rain?.[i]||0;
    const rate=mm*4;
    return {t,utc,end:utc+15*60000,mm,snow,rain,rate,wet:rate>=0.2};
  });
  const start=parsed.findIndex(b=>b.end>now);
  if(start<0) return null;
  const blocks=parsed.slice(start, start+8);
  return blocks.length?blocks:null;
}
function minuteStory(blocks){
  if(!blocks?.length) return null;
  const spells=[];
  let cur=null;
  blocks.forEach((b,i)=>{
    if(b.wet){
      if(!cur) cur={s:i,e:i,peak:b.rate,peakAt:b.utc+7.5*60000};
      else { cur.e=i; if(b.rate>=cur.peak){ cur.peak=b.rate; cur.peakAt=b.utc+7.5*60000; } }
    } else if(cur){ spells.push(cur); cur=null; }
  });
  if(cur) spells.push(cur);
  const now=Date.now();
  const spell=spells.find(sp=>blocks[sp.e].end>now && blocks[sp.s].utc<=now+60*60000);
  if(!spell) return null;
  const snow=blocks.reduce((s,b)=>s+b.snow,0), rain=blocks.reduce((s,b)=>s+b.rain,0);
  const word=snow>rain&&snow>0?'Snow':precipWord(nowHourIdx());
  const band=spell.peak>=7.6?'heavy':spell.peak>=2.5?'moderate':'light';
  const wetNow=!!blocks[0].wet;
  const endMs=blocks[spell.e].end;
  const m=Math.max(0, Math.round((endMs-now)/60000));
  const next=spells.find(sp=>sp.s>spell.e);
  const more=next?`More from ${clock12(blocks[next.s].utc)}`:null;
  const heaviest=(band==='moderate'||band==='heavy')?`Heaviest around ${clock12(spell.peakAt)}`:null;
  const heavy=band==='heavy'?`Heavy around ${clock12(spell.peakAt)}`:null;
  if(wetNow && endMs>=now+55*60000){
    return {state:'rainingNow', headline:`${word} for the next hour`, detail:heaviest, heroValue:'Now', blocks, spell};
  }
  if(wetNow && m>=2){
    return {state:'rainingNow', headline:`${word} stopping in ${m} min`, detail:more, heroValue:'Now', blocks, spell};
  }
  if(wetNow){
    return {state:'rainingNow', headline:`${word} easing off`, detail:more, heroValue:'Now', blocks, spell};
  }
  const startMs=blocks[spell.s].utc;
  const sm=Math.max(1, Math.round((startMs-now)/60000));
  if(sm>60) return null;
  const dur=Math.max(15, Math.round((endMs-startMs)/60000));
  let detail=endMs<now+60*60000?`Lasting about ${dur} min`:`Continuing past ${clock12(now+60*60000)}`;
  if(heavy) detail=`${heavy} · ${detail}`;
  return {state:'startingSoon', headline:`${word} starting in ${sm} min`, detail, heroValue:`In ${sm} min`, blocks, spell};
}
function sumUntilEndOfDay(fromIdx, date){
  const hh=fcData.hourly;
  let s=0;
  for(let k=fromIdx;k<hh.time.length;k++){
    if(hh.time[k].slice(0,10)!==date) break;
    s+=hh.precipitation?.[k]||0;
  }
  return s;
}
function nextDailyWet(afterDate){
  const d=fcData?.daily;
  if(!d) return null;
  for(let i=0;i<d.time.length;i++){
    if(d.time[i]<=afterDate) continue;
    if((d.precipitation_sum?.[i]||0)>=0.2) return {date:d.time[i], mm:d.precipitation_sum[i]};
  }
  return null;
}
function buildOutlook(){
  const hh=fcData?.hourly;
  if(!hh?.time?.length) return {state:'dry', headline:'No rain in the forecast', detail:null, heroValue:'—', chances:[]};
  const nowI=nowHourIdx();
  const chances=[];
  for(let i=nowI;i<Math.min(hh.time.length, nowI+24);i++) chances.push(hh.precipitation_probability?.[i]??0);
  const blocks=minuteBlocks();
  const minute=blocks?minuteStory(blocks):null;
  if(minute) return {...minute, chances, source:'15'};
  const today=placeNowParts().dateStr;
  let wet=-1;
  for(let i=nowI;i<Math.min(hh.time.length, nowI+48);i++){
    if((hh.precipitation?.[i]||0)>=0.2){ wet=i; break; }
  }
  if(wet===nowI){
    const mm=hh.precipitation[nowI]||0;
    return {state:'rainingNow', headline:`${precipWord(nowI)} this hour`, detail:`About ${approxMm(mm)} this hour`, heroValue:'Now', chances, source:'hour'};
  }
  if(wet>nowI){
    const t=hh.time[wet];
    const date=t.slice(0,10);
    const hr=+t.slice(11,13);
    const word=precipWord(wet).toLowerCase();
    if(date===today){
      const mm=sumUntilEndOfDay(wet, date);
      return {state:'laterToday', headline:`Dry until about ${hourClock(hr)}`, detail:`Then ${word}, ${approxMm(mm)} by midnight`, heroValue:`Until ${hourClock(hr)}`, chances, source:'hour'};
    }
    const day=weekdayName(date);
    const short=weekdayName(date,'short');
    const di=fcData.daily?.time?.indexOf(date)??-1;
    const dayMm=di>=0?(fcData.daily.precipitation_sum?.[di]||0):(hh.precipitation[wet]||0);
    return {state:'laterToday', headline:`Dry until ${day} ${dayPart(hr)}`, detail:`Then ${word}, ${approxMm(dayMm)}`, heroValue:`Dry until ${short}`, chances, source:'hour'};
  }
  const win=typeof hourlyRainWindow==='function'?hourlyRainWindow():null;
  const allDry=win?win.precip.every(v=>(v||0)<0.05):false;
  const headline=allDry?'No rain for at least 48 hours':'No rain for at least 24 hours';
  const next=nextDailyWet(today);
  const detail=next?`Next: ${weekdayName(next.date)}, ${approxMm(next.mm)}`:'No rain in the 7-day forecast';
  const hero=next?`Dry until ${weekdayName(next.date,'short')}`:'Dry';
  return {state:'dry', headline, detail, heroValue:hero, chances, source:'hour'};
}
function rainWithin24(){
  const w=typeof hourlyRainWindow==='function'?hourlyRainWindow():null;
  if(!w) return false;
  for(let i=w.relNow;i<Math.min(w.n, w.relNow+24);i++){
    if((w.precip[i]||0)>=0.2) return true;
  }
  return false;
}

function heroVoice(){
  const parts=placeNowParts();
  const when=`${monthPart(parts.day)}-${MONTHS[parts.month]}`;
  const part=dayPart(parts.hour);
  const t0=todayIdx();
  const hi=nowHourIdx();
  const tempNow=fcData.hourly?.temperature_2m?.[hi];
  const hourNorm=hourlyHistData?.avgByHour?.[parts.hour];
  const nowDelta=tempNow!=null&&hourNorm!=null?tempNow-hourNorm:null;
  const dayDelta=dayAnomC(t0);
  const rainToday=(dailyRainHistData||[]).find(r=>r.date===fcData.daily.time[t0]);
  const wbNow=fcData.hourly?.wet_bulb_temperature_2m?.[hi];
  const wbNorm=hourlyWbHistData?.avgByHour?.[parts.hour];
  let headline=null, panel='panel-temperature', rule='typical';
  if(rainToday && rainToday.p90Mm>0 && rainToday.forecastMm>=rainToday.p90Mm && rainToday.forecastMm>=0.2){
    headline=`An unusually wet day for ${when}`;
    panel='panel-rain'; rule='rain';
  } else if(nowDelta!=null && Math.abs(nowDelta)>=2){
    const d=degFrom(nowDelta);
    headline=`${d.abs}° ${nowDelta>0?'warmer':'colder'} than a normal ${when} ${part}`;
    rule='now';
  } else if(dayDelta!=null && Math.abs(dayDelta)>=2){
    const d=degFrom(dayDelta);
    headline=`${d.abs}° ${dayDelta>0?'warmer':'colder'} than a normal ${when} day`;
    rule='day';
  } else if(wbNow!=null && wbNow>=16 && wbNorm!=null && wbNorm>=8){
    const pct=((wbNow-wbNorm)/wbNorm)*100;
    if(Math.abs(pct)>=15){
      headline=pct>0?'Much muggier than usual for the time of day':'Much less muggy than usual for the time of day';
      panel='panel-wet-bulb'; rule='wb';
    }
  }
  if(!headline){
    if(dayDelta==null && nowDelta==null) return null;
    headline=`A typical ${when} ${part}`;
    rule='typical';
  }
  const clauses=[];
  if(rule==='typical'){
    const tempClose=nowDelta==null || Math.abs(nowDelta)<1;
    const wbClose=wbNow==null || wbNorm==null || Math.abs(wbNow-wbNorm)<1;
    clauses.push(tempClose&&wbClose?'Temperature and humidity within 1° of the usual':'Temperature within 1° of the usual');
  }
  if(hourlyHistData && tempNow!=null){
    const same=[];
    const times=fcData.hourly.time;
    for(let i=0;i<times.length;i++){
      if(+times[i].slice(11,13)!==parts.hour) continue;
      if(times[i].slice(0,10)>parts.dateStr) continue;
      const v=fcData.hourly.temperature_2m?.[i];
      if(v!=null) same.push(v);
    }
    if(same.length>=3){
      const mn=Math.min(...same), mx=Math.max(...same);
      if(tempNow<=mn+0.05) clauses.push(`Coldest ${part} this week`);
      else if(tempNow>=mx-0.05) clauses.push(`Warmest ${part} this week`);
    }
  }
  if(rule!=='typical'){
    for(let i=t0+1;i<(fcData.daily?.time.length||0);i++){
      const a=dayAnomC(i);
      if(a!=null && Math.abs(a)<=1){ clauses.push(`Back to average by ${weekdayName(fcData.daily.time[i])}`); break; }
    }
  }
  const totals=rainTotals();
  if(rule==='typical' && totals.last7!=null && totals.lastN!=null && totals.lastN>=1){
    const ratio=totals.last7/totals.lastN;
    if(ratio<0.85) clauses.push('drier week than normal');
    else if(ratio>1.15) clauses.push('wetter week than normal');
  }
  return {headline, detail:clauses.filter(Boolean).slice(0,2).join(' · '), panel};
}

function tempInsight(){
  if(!histData?.dailyAvg) return null;
  const t0=todayIdx();
  const anoms=(fcData.daily?.time||[]).map((_,i)=>dayAnomC(i));
  const a=anoms[t0];
  if(a==null || Math.abs(a)<2) return null;
  const sign=a>0?1:-1;
  let start=t0;
  while(start>0 && anoms[start-1]!=null && Math.sign(anoms[start-1])===sign && Math.abs(anoms[start-1])>=2) start--;
  const word=sign>0?'Warmer than normal':'Colder than normal';
  const since=start===t0?'today':weekdayName(fcData.daily.time[start]);
  let back='';
  for(let i=t0+1;i<anoms.length;i++){
    if(anoms[i]!=null && Math.abs(anoms[i])<=1){ back=` Back to average by ${weekdayName(fcData.daily.time[i])}.`; break; }
  }
  return `${word} since ${since}.${back}`;
}
function rainTotals(){
  const d=fcData?.daily;
  if(!d?.time) return {};
  const t0=todayIdx();
  const sum=(a,b)=>d.time.slice(a,b).reduce((s,_,i)=>s+(d.precipitation_sum[a+i]||0),0);
  const last7=sum(Math.max(0,t0-7), t0);
  const next7=sum(t0, Math.min(d.time.length, t0+7));
  let lastN=null, nextN=null;
  if(dailyRainHistData){
    const by={}; dailyRainHistData.forEach(r=>{ by[r.date]=r; });
    const nsum=(a,b)=>d.time.slice(a,b).reduce((s,t)=>s+(by[t]?.histMeanMm||0),0);
    lastN=nsum(Math.max(0,t0-7), t0);
    nextN=nsum(t0, Math.min(d.time.length, t0+7));
  }
  const parts=placeNowParts();
  const monthNormal=climatologyData?.months?.[parts.month]?.rain??null;
  const mtd=ytdData?.monthToDateMm??null;
  let pace=null, paceWord=null;
  if(mtd!=null && monthNormal!=null && monthNormal>=1){
    const dim=new Date(Date.UTC(parts.year, parts.month+1, 0)).getUTCDate();
    const expect=monthNormal*(parts.day/dim);
    pace=expect>0?mtd/expect:null;
    if(pace!=null) paceWord=pace<0.85?'Behind pace':pace>1.15?'Ahead of pace':'On pace';
  }
  return {last7,lastN,next7,nextN,mtd,monthNormal,paceWord,month:MONTHS[parts.month]};
}
function rainInsight(outlook, totals){
  if(!outlook) return null;
  let head=outlook.state==='dry'?'Dry today.':outlook.state==='laterToday'?'Dry for now.':outlook.headline;
  if(totals?.next7!=null){
    const days=[];
    const d=fcData.daily, t0=todayIdx();
    for(let i=t0;i<Math.min(d.time.length, t0+7);i++){
      if((d.precipitation_sum[i]||0)>=0.2) days.push(d.time[i]);
    }
    const amt=precipReadout(totals.next7);
    let span='over the next week';
    if(days.length){
      const a=weekdayName(days[0]), b=weekdayName(days[days.length-1]);
      span=a===b?a:`${a}–${b}`;
    }
    let mult='';
    if(totals.nextN!=null && totals.nextN>=1){
      mult=`, about ${(totals.next7/totals.nextN).toFixed(1)}× a normal week`;
    }
    head+=` ${amt} due ${span}${mult}.`;
  }
  return head;
}
function wbInsight(){
  const vals=[];
  const labels=[];
  const t0=todayIdx();
  (fcData.daily?.wet_bulb_temperature_2m_max||[]).forEach((v,i)=>{
    if(i<t0||v==null) return;
    vals.push(v); labels.push(fcData.daily.time[i]);
  });
  const w=typeof hourlyRainWindow==='function'?null:null;
  const hh=fcData.hourly;
  if(hh?.wet_bulb_temperature_2m){
    const i0=nowHourIdx();
    for(let i=Math.max(0,i0-24);i<Math.min(hh.time.length, i0+24);i++){
      const v=hh.wet_bulb_temperature_2m[i];
      if(v!=null){ vals.push(v); labels.push(hh.time[i].slice(0,10)); }
    }
  }
  if(!vals.length) return null;
  let peak=-Infinity, at=null;
  const daily=fcData.daily?.wet_bulb_temperature_2m_max||[];
  for(let i=t0;i<daily.length;i++){
    if(daily[i]!=null && daily[i]>peak){ peak=daily[i]; at=fcData.daily.time[i]; }
  }
  if(peak===-Infinity) return null;
  if(peak<19) return 'No heat stress this week.';
  const when=at?weekdayName(at):'this week';
  const n=Math.round(imp?c2f(peak):peak);
  if(peak<24) return `Peaks at ${n}° on ${when} — warm outdoors.`;
  if(peak<28) return `Peaks at ${n}° on ${when} — uncomfortable outdoors.`;
  return `Peaks at ${n}° on ${when} — dangerous to stay outdoors.`;
}
function climateInsight(){
  if(!ytdData?.monthly || !climatologyData) return null;
  const year=ytdData.thisYear;
  const bits=[];
  const seasons=[{name:'winter',idx:[11,0,1]},{name:'spring',idx:[2,3,4]},{name:'summer',idx:[5,6,7]},{name:'autumn',idx:[8,9,10]}];
  let wetSeason=null, best=0;
  seasons.forEach(s=>{
    let act=0, norm=0, n=0;
    s.idx.forEach(i=>{
      const a=ytdData.monthly[i];
      const nr=climatologyData.months[i]?.rain;
      if(!a?.days||nr==null) return;
      act+=a.rain||0; norm+=nr; n++;
    });
    if(n>=2 && norm>=20 && act>norm*1.3 && act-norm>best){ best=act-norm; wetSeason=s.name; }
  });
  if(wetSeason) bits.push(`a wet ${wetSeason}`);
  let dry=null;
  ytdData.monthly.forEach((a,i)=>{
    const nr=climatologyData.months[i]?.rain;
    if(!a?.days||nr==null||nr<15) return;
    if(i>placeNowParts().month) return;
    if((a.rain||0)<nr*0.15) dry=MONTHS[i];
  });
  if(dry) bits.push(`an almost rainless ${dry}`);
  const last=ytdData.cumCurrentYear?.at?.(-1);
  const avg=ytdData.cumHistAvg?.at?.(-1);
  if(last!=null && avg>=1){
    const pct=Math.round((last-avg)/avg*100);
    if(pct<=-2) bits.push(`${Math.abs(pct)}% less rain than normal overall`);
    else if(pct>=2) bits.push(`${pct}% more rain than normal overall`);
    else bits.push('about normal rainfall overall');
  }
  if(!bits.length) return null;
  return `${year} so far: ${bits.join(', ')}.`;
}
function insightHtml(text){
  if(!text) return '';
  const cut=text.indexOf('. ');
  if(cut<0) return `<p class="insight">${escapeHtml(text)}</p>`;
  return `<p class="insight"><strong>${escapeHtml(text.slice(0,cut+1))}</strong> ${escapeHtml(text.slice(cut+2))}</p>`;
}

function segHtml(){
  const items=[['panel-temperature','Temp'],['panel-wet-bulb','Wet bulb'],['panel-rain','Rain'],['panel-climate','Climate']];
  return `<div class="segs" role="tablist" aria-label="Sections">${items.map(([id,label])=>`<button type="button" role="tab" data-seg="${id}" aria-selected="false">${label}</button>`).join('')}</div>`;
}
function spark(chances){
  const vals=(chances||[]).slice(0,24);
  if(!vals.length) return '';
  return `<div class="spark" aria-hidden="true">${vals.map(p=>`<i style="height:${Math.max(6, Math.round(p||0))}%"></i>`).join('')}</div>`;
}
function minuteSvg(story){
  const blocks=story.blocks;
  const c=typeof _cc==='function'?_cc():{rain:'#6b7fd7', ink:'currentColor', muted:'#8b95a5'};
  const W=560, H=118, pL=78, pR=12, pB=22, pT=8;
  const rates=blocks.map(b=>b.rate);
  const yMax=Math.max(8, ...rates)*1.05;
  const cW=W-pL-pR, cH=H-pT-pB;
  const yf=v=>pT+(1-Math.min(v,yMax)/yMax)*cH;
  const bands=[
    [0,2.5,0.05,'Light'],
    [2.5,7.6,0.09,'Moderate'],
    [7.6,yMax,0.14,'Heavy']
  ];
  const bandSvg=bands.map(([a,b,op,label])=>{
    const y1=yf(b), y2=yf(a);
    const mid=(y1+y2)/2;
    return `<rect x="${pL}" y="${y1.toFixed(1)}" width="${cW}" height="${Math.max(0,y2-y1).toFixed(1)}" fill="${c.rain}" opacity="${op}"/>`+
      `<text x="${pL-8}" y="${(mid+4).toFixed(1)}" font-size="11" fill="${c.ink}" text-anchor="end">${label}</text>`;
  }).join('');
  const slot=cW/blocks.length;
  const bars=blocks.map((b,i)=>{
    const h=Math.max(0, yf(0)-yf(b.rate));
    return `<rect x="${(pL+i*slot+slot*0.18).toFixed(1)}" y="${yf(b.rate).toFixed(1)}" width="${(slot*0.64).toFixed(1)}" height="${h.toFixed(1)}" fill="${c.rain}" rx="2"/>`;
  }).join('');
  const labels=[0,2,4,6,8].map(step=>{
    const i=Math.min(blocks.length-1, Math.round(step/2));
    if(step===8) return `<text x="${(pL+cW).toFixed(1)}" y="${H-4}" font-size="11" fill="${c.muted}" text-anchor="end">${clock12(blocks[0].utc+120*60000)}</text>`;
    const x=pL+(step/2)*slot;
    const text=step===0?'Now':clock12(blocks[0].utc+step*15*60000);
    return `<text x="${x.toFixed(1)}" y="${H-4}" font-size="11" fill="${c.muted}" text-anchor="${step===0?'start':'middle'}">${text}</text>`;
  }).join('');
  let rule='';
  if(story.spell && story.spell.s>0){
    const x=pL+story.spell.s*slot;
    rule=`<line x1="${x.toFixed(1)}" y1="${pT}" x2="${x.toFixed(1)}" y2="${(pT+cH).toFixed(1)}" stroke="${c.ink}" stroke-dasharray="3,3" stroke-width="1"/>`+
      `<text x="${(x+4).toFixed(1)}" y="${(pT+12).toFixed(1)}" font-size="11" fill="${c.ink}">starts ${clock12(blocks[story.spell.s].utc)}</text>`;
  }
  return `<svg viewBox="0 0 ${W} ${H}" class="wc-svg nh-svg" role="img" aria-label="${escapeHtml(story.headline)}. Open-Meteo 15-minute estimate, not minute-by-minute.">${bandSvg}${bars}${rule}${labels}</svg>`;
}
function outlookHtml(o){
  if(o.blocks){
    return `<section class="nexthour" aria-label="Next hour">
      <div class="nh-eye"><span>NEXT HOUR</span><span>Open-Meteo · 15-minute estimate</span></div>
      <h3 class="nh-h">${escapeHtml(o.headline)}</h3>
      ${o.detail?`<p class="nh-d">${escapeHtml(o.detail)}</p>`:''}
      ${minuteSvg(o)}
    </section>`;
  }
  return `<section class="outlook" aria-label="Rain outlook">
    <div class="umb" aria-hidden="true">${ICON.umbrella}</div>
    <div class="outlook-copy">
      <p class="outlook-h">${escapeHtml(o.headline)}</p>
      ${o.detail?`<p class="outlook-d">${escapeHtml(o.detail)}</p>`:''}
      <p class="src-cap">Open-Meteo · hourly estimate</p>
    </div>
    ${spark(o.chances)}
  </section>`;
}
function offerHtml(){
  const a=alertPrefs();
  if(a.dismissed||a.start||a.heavy) return '';
  if(!rainWithin24()) return '';
  return `<div class="offer" id="alert-offer">
    <p>Want a heads-up before rain?</p>
    <button type="button" class="btn" data-alert-on>Turn on alerts</button>
    <button type="button" class="text-btn" data-alert-dismiss>Not now</button>
  </div>`;
}
function pctLine(amount, normal){
  if(normal==null) return '';
  if(normal<1) return 'normally dry';
  const pct=Math.round((amount/normal)*100);
  return `<strong>${pct}%</strong> of normal`;
}
function meter(amount, normal){
  if(amount==null||normal==null) return '';
  const scale=Math.max(amount, normal, 0.001)*1.1;
  const fw=Math.max(0, Math.min(100, amount/scale*100));
  const tick=Math.max(0, Math.min(100, normal/scale*100));
  return `<div class="meter" aria-hidden="true"><i style="width:${fw.toFixed(1)}%"></i><b style="left:${tick.toFixed(1)}%"></b></div>`;
}
function totalsHtml(t){
  if(t.last7==null && t.next7==null && t.mtd==null) return '';
  const tile=(k,amount,normal,foot)=>{
    if(amount==null) return '';
    const parts=precipParts(amount);
    return `<div class="tile"><p class="k">${escapeHtml(k)}</p><p class="v">${escapeHtml(parts.num)}<span>${escapeHtml(parts.unit)}</span></p>${meter(amount, normal)}<p class="foot">${foot}</p></div>`;
  };
  const monthFoot=t.paceWord&&t.monthNormal!=null
    ? `<strong>${escapeHtml(t.paceWord)}</strong> for ${escapeHtml(precipReadout(t.monthNormal))}`
    : pctLine(t.mtd, t.monthNormal);
  return `<div class="totals">${tile('Last 7 days', t.last7, t.lastN, pctLine(t.last7, t.lastN))}${tile('Next 7 days', t.next7, t.nextN, pctLine(t.next7, t.nextN))}${tile(t.month||'This month', t.mtd, t.monthNormal, monthFoot)}</div>`;
}
function legend(items){
  if(!items?.length) return '';
  return `<div class="chart-leg">${items.map(it=>`<span class="cli"><i class="${it.sw}"></i>${escapeHtml(it.t)}</span>`).join('')}</div>`;
}
function readoutHtml(key, num, unit, ctx, store){
  if(store!==false) readoutBase[key]={num, unit, ctx};
  return `<div class="mod-read" data-readout="${key}"><div class="mod-val"><span class="mod-num">${escapeHtml(num)}</span><span class="mod-unit">${escapeHtml(unit)}</span></div><div class="mod-ctx">${ctx}</div></div>`;
}
function chartMod(opts){
  const body=opts.body||'';
  const expandable=body.includes('<svg')&&!opts.noExpand;
  return `<div class="chart-mod" data-chart-key="${opts.key}">
    <div class="mod-eye"><h3>${escapeHtml(opts.title)}</h3>${expandable?`<button type="button" class="mod-expand" data-detail="${opts.key}" aria-label="How ${escapeHtml(opts.title)} is worked out">${ICON.expand}</button>`:''}</div>
    ${opts.readout||''}
    ${opts.legend||''}
    <div class="mod-plot">${body}</div>
  </div>`;
}
function ctx(strong, rest){
  return `<strong>${escapeHtml(strong)}</strong>${rest?` ${rest}`:''}`;
}
function dailyTempReadout(){
  const i=todayIdx();
  const hi=fcData.daily.temperature_2m_max[i];
  const parts=tempParts(hi);
  const a=dayAnomC(i);
  const band=(histData?.dailyAvg||[]).find(x=>x.date===fcData.daily.time[i]);
  let rest='';
  if(a!=null && band){
    const d=degFrom(a);
    const nh=Math.round(nT(band.tMax)), nl=Math.round(nT(band.tMin));
    rest=`· ${d.near?'near normal':d.text} (${nh}° / ${nl}°)`;
  }
  return readoutHtml('temp', parts.num, parts.unit, ctx('Today', rest));
}
function hourlyTempReadout(){
  const i=nowHourIdx();
  const rel=hourlyIndex(i);
  const v=fcData.hourly.temperature_2m?.[i];
  const parts=tempParts(v);
  const norm=hourlyHistData?.avgByHour?.[placeNowParts().hour];
  let rest='';
  if(v!=null && norm!=null){
    const d=degFrom(v-norm);
    rest=`· ${d.near?'near the usual':d.text+' than usual'} for ${hourClock(placeNowParts().hour)} (${Math.round(nT(norm))}°)`;
  }
  return readoutHtml('hourly', parts.num, parts.unit, ctx('Now', rest));
}
function hourlyIndex(abs){
  const wTimes=fcData.hourly.time;
  const start=Math.max(0, nowHourIdx()-24);
  return abs-start;
}
function rangeBar(){
  const i=todayIdx();
  const lo=fcData.daily.temperature_2m_min?.[i];
  const hi=fcData.daily.temperature_2m_max?.[i];
  const band=(histData?.dailyAvg||[]).find(a=>a.date===fcData.daily.time[i]);
  const now=fcData.hourly?.temperature_2m?.[nowHourIdx()];
  if(lo==null||hi==null||!band||band.tMin==null||band.tMax==null){
    return `<div class="range range-slot" aria-hidden="true"></div>`;
  }
  const pad=imp?5:3;
  const vals=[nT(lo),nT(hi),nT(band.tMin),nT(band.tMax)];
  if(now!=null) vals.push(nT(now));
  const min=Math.min(...vals)-pad, max=Math.max(...vals)+pad;
  const span=max-min||1;
  const pct=v=>((nT(v)-min)/span)*100;
  const n1=pct(Math.min(band.tMin,band.tMax)), n2=pct(Math.max(band.tMin,band.tMax));
  const t1=pct(Math.min(lo,hi)), t2=pct(Math.max(lo,hi));
  let l1=t1, l2=t2;
  if(l2-l1<18){ const mid=(l1+l2)/2; l1=mid-10; l2=mid+10; }
  l1=Math.max(8, Math.min(92, l1));
  l2=Math.max(8, Math.min(92, l2));
  const dot=now!=null?pct(now):null;
  const aria=`Today ${Math.round(nT(lo))} to ${Math.round(nT(hi))} degrees, currently ${now==null?'unknown':Math.round(nT(now))}. Normal is ${Math.round(nT(band.tMin))} to ${Math.round(nT(band.tMax))}.`;
  return `<div class="range" role="img" aria-label="${escapeHtml(aria)}">
    <div class="range-track">
      <div class="range-normal" style="left:${n1.toFixed(1)}%;width:${Math.max(n2-n1,1).toFixed(1)}%"></div>
      <div class="range-today" style="left:${t1.toFixed(1)}%;width:${Math.max(t2-t1,1.2).toFixed(1)}%"></div>
      ${dot!=null?`<div class="range-now" style="left:${dot.toFixed(1)}%"></div>`:''}
    </div>
    <span class="range-lo" style="left:${l1.toFixed(1)}%">${fTn(Math.min(lo,hi))}°</span>
    <span class="range-hi" style="left:${l2.toFixed(1)}%">${fTn(Math.max(lo,hi))}°</span>
    <div class="range-cap">normal ${fTn(band.tMin)}°–${fTn(band.tMax)}°</div>
  </div>`;
}
function dryCard(w){
  let until=null;
  for(let i=w.relNow;i<w.n;i++){
    if((w.prob[i]??0)>=5){ until=w.times[i]; break; }
  }
  let detail='Chance stays under 5% through the next 24 hours';
  if(until){
    const day=weekdayName(until.slice(0,10));
    detail=`Chance under 5% until ${day} ${hourClock(+until.slice(11,13))}`;
  }
  const chances=w.prob.slice(w.relNow, w.relNow+24).map(p=>p??0);
  return `<div class="dry-card"><div><p class="outlook-h">No rain, past or next 24 hours</p><p class="outlook-d">${escapeHtml(detail)}</p></div>${spark(chances)}</div>`;
}
function rainDayWords(mm, mean, p90, dateStr){
  if(mm<0.1) return `dry · normal for ${dateStr.slice(8)} ${MONTHS[+dateStr.slice(5,7)-1].slice(0,3)} is ${precipReadout(mean||0)}`;
  if(mean!=null && mean<1) return 'normally dry';
  if(p90>0 && mm>=p90) return `unusually wet (${precipReadout(mean)})`;
  if(mean==null) return '';
  const ratio=mm/mean;
  const word=ratio<0.5?'drier than normal':ratio<=1.5?'about normal':'wetter than normal';
  return `${word} (${precipReadout(mean)})`;
}
function hourlyRainReadout(i, store){
  const d=_hourlyRainData;
  if(!d) return readoutHtml('hourly-rain','—','',ctx('This hour',''), store);
  const idx=i==null?d.relNow:i;
  const parts=precipParts(d.precip[idx]||0);
  const chance=d.prob[idx];
  const usual=d.usual?.[idx];
  const hr=+d.times[idx].slice(11,13);
  const bits=[];
  if(idx>=d.relNow && chance!=null) bits.push(`${chance}% chance`);
  if(usual!=null) bits.push(`the usual for ${hourClock(hr)} is ${usual}%`);
  const label=idx===d.relNow?'This hour':idx<d.relNow?'Observed':'Forecast';
  return readoutHtml('hourly-rain', parts.num, parts.unit, ctx(label, bits.length?`· ${bits.join(' · ')}`:''), store);
}
function dailyRainReadout(i, store){
  const d=_dailyRainData;
  if(!d) return readoutHtml('daily-rain','—','',ctx('Today',''), store);
  const idx=i==null?d.todayIdx:i;
  const parts=precipParts(d.precip[idx]||0);
  const label=idx===d.todayIdx?'Today':idx<d.todayIdx?'Observed':'Forecast';
  const words=rainDayWords(d.precip[idx]||0, d.means?.[idx], idx===d.todayIdx?d.p90:null, d.dates[idx]);
  const chance=idx>=d.todayIdx && d.probs[idx]!=null?`${d.probs[idx]}% chance · `: '';
  return readoutHtml('daily-rain', parts.num, parts.unit, ctx(label, `· ${chance}${words}`), store);
}
function ytdReadout(){
  if(!ytdData) return readoutHtml('rain','—','',ctx('Year to date','· loading'));
  const cur=ytdData.cumCurrentYear.at(-1)||0;
  const avg=ytdData.cumHistAvg.at(-1)||0;
  const parts=precipParts(cur);
  const diff=cur-avg;
  const when=ytdData.latestDate?`${+ytdData.latestDate.slice(8)} ${MONTHS[+ytdData.latestDate.slice(5,7)-1].slice(0,3)}`:'today';
  let rest='';
  if(avg>=1){
    const pct=Math.round(Math.abs(diff)/avg*100);
    rest=`· ${precipReadout(Math.abs(diff))} (${pct}%) ${diff<0?'below':'above'} average`;
  }
  return readoutHtml('rain', parts.num, parts.unit, ctx(`To ${when}`, rest));
}
function climateReadout(){
  const parts=placeNowParts();
  const norm=climatologyData?.months?.[parts.month];
  const act=ytdData?.monthly?.[parts.month];
  if(!norm) return readoutHtml('climate','—','',ctx(MONTHS[parts.month],''));
  const value=act?.tMax!=null?tempParts(act.tMax):tempParts(norm.tMax);
  let rest=`· normal ${Math.round(nT(norm.tMax))}° / ${Math.round(nT(norm.tMin))}°`;
  if(act?.tMax!=null && act?.tMin!=null){
    const dep=(act.tMax+act.tMin)/2-(norm.tMax+norm.tMin)/2;
    const d=degFrom(dep);
    const rain=act.rain!=null&&norm.rain!=null?` · ${precipReadout(act.rain)} of ${precipReadout(norm.rain)}`:'';
    rest=`· ${d.near?'near':d.text+' than'} the ${Math.round(nT(norm.tMax))}° / ${Math.round(nT(norm.tMin))}° normal${rain}`;
  }
  const label=act?.days?`${MONTHS[parts.month]} so far`:`${MONTHS[parts.month]} normal`;
  return readoutHtml('climate', value.num, value.unit, ctx(label, rest));
}

function wbCollapsed(maxC, nowC, normC){
  const nowN=nowC==null?'—':`${Math.round(imp?c2f(nowC):nowC)}°`;
  let second='Charts hidden while it stays under 15°.';
  if(nowC!=null && normC!=null){
    const d=nowC-normC;
    const shown=Math.abs(Math.round(imp?d*9/5:d));
    second=`${shown}° ${d<0?'below':'above'} the usual for the hour. Charts hidden while it stays under 15°.`;
  }
  return `<button type="button" class="wb-card" data-expand-wb>
    <span><strong>Wet bulb ${escapeHtml(nowN)} · no heat stress</strong><small>${escapeHtml(second)}</small></span>
    <span class="chev" aria-hidden="true">${ICON.chev}</span>
  </button>`;
}
function maxWetBulb(){
  let max=-Infinity;
  (fcData.daily?.wet_bulb_temperature_2m_max||[]).forEach(v=>{ if(v!=null&&v>max) max=v; });
  (fcData.hourly?.wet_bulb_temperature_2m||[]).forEach(v=>{ if(v!=null&&v>max) max=v; });
  return max===-Infinity?null:max;
}

function paintPin(temp, cond){
  const pin=document.getElementById('pinbar');
  if(!pin) return;
  const gps=activeSource==='geo';
  const name=shortLabel(geoName)||'Choose a place';
  const when=updatedPhrase();
  pin.innerHTML=`<div class="pin-inner">
    <button type="button" class="pin-row" data-open="places">
      <span class="pin-ico">${gps?ICON.gps:ICON.pin}</span>
      <span class="pin-name">${escapeHtml(name)}</span>
      <span class="pin-now">${escapeHtml(temp)} · ${escapeHtml(cond)}</span>
      <span class="pin-chev">${ICON.chev}</span>
      <span class="pin-updated">${escapeHtml(when.text)}</span>
    </button>
    ${segHtml()}
  </div>`;
}
function updatedPhrase(){
  const t=fcData?._fetchedAt||Date.now();
  const off=(fcData?.utc_offset_seconds||0)*1000;
  const d=new Date(t+off);
  const hm=`${padDate(d.getUTCHours())}:${padDate(d.getUTCMinutes())}`;
  const age=Date.now()-t;
  const parts=placeNowParts();
  const same=d.getUTCFullYear()===parts.year && d.getUTCMonth()===parts.month && d.getUTCDate()===parts.day;
  if(age<3*3600*1000 && same) return {text:`Updated ${hm}`, live:true, phrase:`updated ${hm}`};
  const y=new Date(Date.UTC(parts.year, parts.month, parts.day)-86400000);
  const yest=d.getUTCFullYear()===y.getUTCFullYear() && d.getUTCMonth()===y.getUTCMonth() && d.getUTCDate()===y.getUTCDate();
  if(yest) return {text:`Updated yesterday ${hm}`, live:false, phrase:`last updated yesterday ${hm}`};
  const mon=`${d.getUTCDate()} ${MONTHS[d.getUTCMonth()].slice(0,3)}`;
  return {text:`Updated ${mon} ${hm}`, live:false, phrase:`last updated ${mon} ${hm}`};
}
function sourceRows(){
  const when=updatedPhrase();
  const live=when.live;
  return `<div class="src-list">
    <div class="src-row"><i class="dot ${live?'dot-live':'dot-off'}"></i><div><strong>Forecast &amp; climate history — Open-Meteo · ${escapeHtml(when.phrase)}</strong><small>${live?'Live':'Offline'}</small></div></div>
    <div class="src-row"><i class="dot dot-off"></i><div><strong>Minute-by-minute rain — Apple hasn't enabled this for the app yet; using Open-Meteo estimates</strong><small>Off</small></div></div>
  </div>`;
}
function paintSettings(){
  const card=document.getElementById('settings-card');
  if(!card) return;
  const theme=document.documentElement.dataset.theme||'auto';
  const a=alertPrefs();
  const perm=('Notification' in window)?Notification.permission:'unsupported';
  const warn=(a.start||a.heavy)&&perm!=='granted';
  const denied=perm==='denied'||perm==='unsupported';
  card.innerHTML=`<div class="modal-head"><h2 id="settings-title">Settings</h2><button type="button" class="text-btn" data-close="settings">Done</button></div>
    <section class="set-sec"><h3>Units</h3>
      <div class="unit-seg" role="radiogroup" aria-label="Units">
        <button type="button" role="radio" data-unit="metric" aria-checked="${imp?'false':'true'}" class="${imp?'':'on'}">°C · km/h · mm</button>
        <button type="button" role="radio" data-unit="imp" aria-checked="${imp?'true':'false'}" class="${imp?'on':''}">°F · mph · in</button>
      </div>
    </section>
    <section class="set-sec"><h3>Appearance</h3>
      <div class="unit-seg" role="radiogroup" aria-label="Appearance">
        ${['light','Light','auto','Auto','dark','Dark'].reduce((html,x,i,arr)=>{ if(i%2) return html; const id=arr[i], label=arr[i+1]; return html+`<button type="button" data-theme="${id}" class="${theme===id?'on':''}">${label}</button>`; },'')}
      </div>
    </section>
    <section class="set-sec"><h3>Rain alerts</h3>
      <label class="toggle-row"><span><strong>Rain starting</strong><small>A note before rain is due to begin.</small></span><input type="checkbox" data-alert="start" ${a.start?'checked':''}></label>
      <label class="toggle-row"><span><strong>Heavy rain</strong><small>A note when heavy rain is on the way.</small></span><input type="checkbox" data-alert="heavy" ${a.heavy?'checked':''}></label>
      ${warn?`<div class="warn"><p>Notifications are off — alerts can't be delivered until you allow them.${denied?' Allow them for this site in your browser settings.':''}</p><button type="button" class="btn" data-notify>Turn on</button></div>`:''}
    </section>
    <section class="set-sec"><h3>Data sources</h3>${sourceRows()}</section>`;
}
function renderSavedRows(){
  const box=document.getElementById('saved-list');
  if(!box) return;
  const list=savedList();
  box.innerHTML=list.map((p,i)=>`<div class="saved-row"><button type="button" class="place-row" data-place="${i}"><span class="pin-ico">${ICON.pin}</span><span><strong>${escapeHtml(p.label||p.name)}</strong><small>${escapeHtml([p.region,p.country].filter(Boolean).join(', '))}</small></span></button><button type="button" class="text-btn" data-remove-place="${i}" aria-label="Remove ${escapeHtml(p.label||p.name)}">Remove</button></div>`).join('');
}
function renderPlaceIdle(){
  const box=document.getElementById('place-results');
  if(box) box.innerHTML='';
}
function openPlaces(){
  const modal=document.getElementById('place-modal');
  if(!modal) return;
  modal.classList.remove('hidden');
  document.getElementById('place-card').innerHTML=`<div class="modal-head"><h2 id="place-title">Places</h2><button type="button" class="text-btn" data-close="place">Done</button></div>
    <button type="button" class="place-row" data-use-geo><span class="pin-ico">${ICON.gps}</span><span><strong>My location</strong><small>${myLat!=null?escapeHtml(shortLabel(myName||'Current position')):'Use this device’s location'}</small></span></button>
    <div id="saved-list"></div>
    <label class="search-bar">${ICON_SEARCH}<input id="srch" type="text" placeholder="Search for a place…" autocomplete="off" spellcheck="false" aria-label="Search for a place"></label>
    <div id="place-results"></div>`;
  renderSavedRows();
  document.getElementById('srch')?.focus();
}
function closePlaces(){
  document.getElementById('place-modal')?.classList.add('hidden');
}
function openSettings(){
  paintSettings();
  document.getElementById('settings-modal')?.classList.remove('hidden');
}
function closeSettings(){ document.getElementById('settings-modal')?.classList.add('hidden'); }
function openDetail(key){
  const mod=document.querySelector(`.chart-mod[data-chart-key="${key}"]`);
  const svg=mod?.querySelector('svg')?.outerHTML||'';
  const read=mod?.querySelector('.mod-read')?.innerText||'';
  const card=document.getElementById('detail-card');
  const years=climatologyData?`${climatologyData.yearStart}–${climatologyData.yearEnd}`:(hourlyHistData?`${hourlyHistData.yearStart}–${hourlyHistData.yearEnd}`:'');
  card.innerHTML=`<div class="modal-head"><h2 id="detail-title">${escapeHtml(mod?.querySelector('h3')?.textContent||'Chart')}</h2><button type="button" class="text-btn" data-close="detail">Done</button></div>
    <div class="detail-plot">${svg}</div>
    <div class="detail-stats">${detailStats(key)}</div>
    <p class="how"><strong>How this is worked out.</strong> ${escapeHtml(HOW[key]||'')}${years?` Years ${escapeHtml(years)}.` :''}</p>
    <button type="button" class="btn" data-copy="${escapeHtml(read)}">Copy summary</button>`;
  document.getElementById('detail-modal')?.classList.remove('hidden');
}
function detailStats(key){
  const cell=(k,v)=>`<div><span>${escapeHtml(k)}</span><strong>${escapeHtml(v)}</strong></div>`;
  if(key==='hourly'&&_hourlyData){
    const i=_hourlyData.nowIdx??0;
    const now=_hourlyData.temps[i], usual=_hourlyData.histLine[i];
    const diffs=_hourlyData.temps.map((v,n)=>v!=null&&_hourlyData.histLine[n]!=null?v-_hourlyData.histLine[n]:null).filter(v=>v!=null);
    const cold=Math.min(..._hourlyData.temps.filter(v=>v!=null));
    const warm=Math.max(..._hourlyData.temps.filter(v=>v!=null));
    return cell('Now', now==null?'—':`${Math.round(now)}°`)+cell('Usual for the hour', usual==null?'—':`${Math.round(usual)}°`)+cell('Difference', now==null||usual==null?'—':degFrom(imp?(now-usual)*5/9:now-usual).text)+cell('In this window', `${Math.round(cold)}° to ${Math.round(warm)}°`);
  }
  if(key==='temp'&&_tempData){
    const i=_tempData.todayIdx??0;
    const a=dayAnomC(todayIdx());
    return cell('Today high', _tempData.maxV[i]==null?'—':`${Math.round(_tempData.maxV[i])}°`)+cell('Today low', _tempData.minV[i]==null?'—':`${Math.round(_tempData.minV[i])}°`)+cell('Compared with normal', a==null?'—':degFrom(a).text)+cell('Normal high / low', _tempData.dailyAvg?.[i]?`${Math.round(nT(_tempData.dailyAvg[i].tMax))}° / ${Math.round(nT(_tempData.dailyAvg[i].tMin))}°`:'—');
  }
  if(key==='hourly-rain'&&_hourlyRainData){
    const d=_hourlyRainData, i=d.relNow;
    const wet=d.precip.reduce((m,v,n)=>v>m.v?{v,n}:m,{v:-1,n:0});
    return cell('This hour', precipReadout(d.precip[i]||0))+cell('Chance', d.prob[i]==null?'—':`${d.prob[i]}%`)+cell('Usual chance', d.usual?.[i]==null?'—':`${d.usual[i]}%`)+cell('Wettest hour', precipReadout(wet.v<0?0:wet.v));
  }
  if(key==='daily-rain'&&_dailyRainData){
    const d=_dailyRainData, i=d.todayIdx;
    return cell('Today', precipReadout(d.precip[i]||0))+cell('Chance', d.probs[i]==null?'—':`${d.probs[i]}%`)+cell('Usual', d.means?.[i]==null?'—':precipReadout(d.means[i]))+cell('1-in-10 day', d.p90?precipReadout(d.p90):'—');
  }
  if(key==='rain'&&ytdData){
    const cur=ytdData.cumCurrentYear.at(-1)||0, avg=ytdData.cumHistAvg.at(-1)||0;
    return cell('This year', precipReadout(cur))+cell('Normal', precipReadout(avg))+cell('Difference', precipReadout(cur-avg))+cell('Through', ytdData.latestDate||'—');
  }
  if((key==='climate'||key==='climate-rain')&&climatologyData){
    const mo=placeNowParts().month;
    const n=climatologyData.months[mo], a=ytdData?.monthly?.[mo];
    return cell('Normal high', n?.tMax==null?'—':`${Math.round(nT(n.tMax))}°`)+cell('Normal low', n?.tMin==null?'—':`${Math.round(nT(n.tMin))}°`)+cell('Rain so far', a?.rain==null?'—':precipReadout(a.rain))+cell('Normal rain', n?.rain==null?'—':precipReadout(n.rain));
  }
  if((key==='hourly-wb'||key==='wet-bulb')){
    const now=fcData.hourly?.wet_bulb_temperature_2m?.[nowHourIdx()];
    const mx=maxWetBulb();
    return cell('Now', now==null?'—':`${Math.round(nT(now))}°`)+cell('Highest in view', mx==null?'—':`${Math.round(nT(mx))}°`)+cell('Heat stress', mx!=null&&mx>=19?'Possible':'None this week')+cell('Hidden below', '15°');
  }
  return '';
}

function paintScreen(){
  if(!fcData?.daily) return;
  const key=`${_lazyLat},${_lazyLon}`;
  if(key!==_screenKey){ _screenKey=key; wbExpanded=false; window.scrollTo({top:0,behavior:'auto'}); }
  const t0=todayIdx();
  const hi=nowHourIdx();
  const code=fcData.hourly?.weather_code?.[hi]??fcData.daily.weather_code[t0];
  const day=placeIsDay();
  const tempNow=fcData.hourly?.temperature_2m?.[hi]??fcData.daily.temperature_2m_max[t0];
  const feels=fcData.hourly?.apparent_temperature?.[hi];
  const cond=conditionName(code);
  document.body.classList.add('has-weather');
  document.documentElement.dataset.sky=skyName(code, day);
  const sky=document.getElementById('sky');
  if(sky) sky.hidden=false;
  const voice=heroVoice();
  const outlook=buildOutlook();
  const totals=rainTotals();
  const wind=fcData.hourly?.wind_speed_10m?.[hi]??fcData.daily.wind_speed_10m_max?.[t0];
  const uvNow=fcData.hourly?.uv_index?.[hi];
  const uvMax=fcData.daily.uv_index_max?.[t0];
  const uvLabelTxt=day?'UV':'UV peak';
  const uvVal=uvBits(day?(uvNow??uvMax):uvMax);
  const gps=activeSource==='geo';
  const tp=tempParts(tempNow);
  paintPin(`${tp.num}°`, cond);

  const hourlySvg=makeHourlyTempChart();
  const tempSvg=makeTempChart();
  const hourlyLegs=[{sw:'sw-obs',t:'Observed'},{sw:'sw-fc',t:'Forecast'},{sw:'sw-norm',t:'5-yr average'}];
  if(_hourlyGap?.below) hourlyLegs.push({sw:'sw-below',t:'Below usual'});
  if(_hourlyGap?.above) hourlyLegs.push({sw:'sw-above',t:'Above usual'});
  const wbMax=maxWetBulb();
  const showWb=wbExpanded||wbMax==null||wbMax>=15;
  const wbNow=fcData.hourly?.wet_bulb_temperature_2m?.[hi];
  const wbNorm=hourlyWbHistData?.avgByHour?.[placeNowParts().hour];
  let wbBody='';
  if(!showWb) wbBody=wbCollapsed(wbMax, wbNow, wbNorm);
  else {
    const wbLegs=[{sw:'sw-obs',t:'Observed'},{sw:'sw-fc',t:'Forecast'},{sw:'sw-norm',t:'5-yr average'}];
    if(_wbGap?.below) wbLegs.push({sw:'sw-below',t:'Below usual'});
    if(_wbGap?.above) wbLegs.push({sw:'sw-above',t:'Above usual'});
    const wbParts=tempParts(wbNow);
    let wbRest='';
    if(wbNow!=null&&wbNorm!=null){
      const d=degFrom(wbNow-wbNorm);
      wbRest=`· ${d.near?'near the usual':d.text+' than usual'} for ${hourClock(placeNowParts().hour)}`;
    }
    wbBody=`${wbExpanded&&wbMax!=null&&wbMax<15?`<button type="button" class="text-btn wb-hide" data-expand-wb>Hide charts</button>`:''}
      ${chartMod({key:'hourly-wb', title:'48-hour wet bulb', body:makeHourlyWetBulbChart(), legend:legend(wbLegs), readout:readoutHtml('hourly-wb', wbParts.num, wbParts.unit, ctx('Now', wbRest))})}
      ${chartMod({key:'wet-bulb', title:'14-day wet bulb', body:makeWetBulbChart(), legend:legend([{sw:'sw-band',t:'Normal range'},{sw:'sw-obs',t:'Observed'},{sw:'sw-fc',t:'Forecast'}]), readout:readoutHtml('wet-bulb', wbParts.num, wbParts.unit, ctx('Now', wbRest))})}`;
  }
  const rainWin=typeof hourlyRainWindow==='function'?hourlyRainWindow():null;
  const rainDry=rainWin&&rainWin.n&&rainWin.precip.every(v=>(v||0)<0.05);
  const rain48=rainDry?dryCard(rainWin):chartMod({
    key:'hourly-rain', title:'48-hour rainfall', body:makeHourlyRainChart(),
    legend:legend([{sw:'sw-obs',t:'Observed'},{sw:'sw-fc',t:'Forecast'},{sw:'sw-chance',t:'Chance'},{sw:'sw-norm',t:'Usual amount'}]),
    readout:hourlyRainReadout()
  });
  const tInsight=tempInsight();
  const rInsight=rainInsight(outlook, totals);
  const wInsight=wbInsight();
  const cInsight=climateInsight();
  const loc=shortLabel(geoName)||'Weather';

  document.getElementById('content').innerHTML=`
  <section class="hero" id="hero">
    <div class="hero-chrome">
      <button type="button" class="loc-pill" data-open="places">
        <span class="pin-ico">${gps?ICON.gps:ICON.pin}</span>
        <span>${escapeHtml(loc)}</span>
        ${ICON.chev}
      </button>
      <button type="button" class="icon-btn" data-open="settings" aria-label="Settings">${ICON.gear}</button>
    </div>
    <div class="hero-main">
      <div class="hero-temp">${escapeHtml(tp.num)}<span class="hero-unit">${escapeHtml(tp.unit)}</span></div>
      <div class="hero-icon">${weatherIcon(code, 64)}</div>
    </div>
    <p class="hero-cond">${escapeHtml(cond)}${feels!=null?` · feels ${escapeHtml(String(fTn(feels)))}°`:''}</p>
    ${voice?`<button type="button" class="voice" data-panel-jump="${voice.panel}"><span class="voice-h">${escapeHtml(voice.headline)}</span>${voice.detail?`<span class="voice-d">${escapeHtml(voice.detail)}</span>`:'<span class="voice-d voice-reserve"></span>'}</button>`:`<div class="voice voice-reserve" aria-hidden="true"></div>`}
    ${rangeBar()}
    <div class="hero-stats">
      <div class="hero-stat"><span class="stat-k">Rain</span><span class="stat-v">${escapeHtml(outlook.heroValue||'—')}</span></div>
      <div class="hero-stat"><span class="stat-k">Wind</span><span class="stat-v">${escapeHtml(fW(wind))}</span></div>
      <div class="hero-stat"><span class="stat-k">${uvLabelTxt}</span><span class="stat-v">${escapeHtml(uvVal)}</span></div>
    </div>
  </section>
  <div class="sheet" id="sheet">
    ${segHtml()}
    ${outlookHtml(outlook)}
    ${offerHtml()}
    <section class="wx-sec" id="panel-temperature">
      <header class="sec-head"><h2>Temperature</h2>${tInsight?insightHtml(tInsight):'<p class="sec-sub">Actual air temperature, high and low</p>'}</header>
      <div class="lazy-sentinel" data-lazy="climatology" aria-hidden="true"></div>
      ${chartMod({key:'hourly', title:'48-hour temperature', body:hourlySvg, legend:legend(hourlyLegs), readout:hourlyTempReadout()})}
      ${chartMod({key:'temp', title:'14-day temperature', body:tempSvg, legend:legend([{sw:'sw-band',t:'Normal range'},{sw:'sw-obs',t:'Observed'},{sw:'sw-fc',t:'Forecast'}]), readout:dailyTempReadout()})}
    </section>
    <section class="wx-sec" id="panel-wet-bulb">
      <header class="sec-head"><h2>Wet bulb</h2>${wInsight?insightHtml(wInsight):'<p class="sec-sub">Heat stress</p>'}</header>
      ${wbBody}
    </section>
    <section class="wx-sec" id="panel-rain">
      <header class="sec-head"><h2>Rain</h2>${rInsight?insightHtml(rInsight):'<p class="sec-sub">Precipitation</p>'}</header>
      ${totalsHtml(totals)}
      ${rain48}
      ${chartMod({key:'daily-rain', title:'14-day rainfall', body:makeDailyRainChart(), legend:legend([{sw:'sw-obs',t:'Observed'},{sw:'sw-fc',t:'Forecast'},{sw:'sw-norm',t:'Usual amount'}]), readout:dailyRainReadout()})}
      <div data-lazy="ytd">
      ${chartMod({key:'rain', title:'Year to date', body:makeRainYTDChart(), legend:legend([{sw:'sw-year',t:'This year'},{sw:'sw-fc',t:'Forecast'},{sw:'sw-norm',t:'Normal'}]), readout:ytdReadout()})}
      </div>
    </section>
    <section class="wx-sec" id="panel-climate">
      <header class="sec-head"><h2>Climate</h2>${cInsight?insightHtml(cInsight):'<p class="sec-sub">Monthly normals</p>'}</header>
      ${chartMod({key:'climate', title:'Monthly temperature', body:makeClimateChart(), legend:legend([{sw:'sw-band',t:'Normal range'},{sw:'sw-year',t:'This year'}]), readout:climateReadout()})}
      ${chartMod({key:'climate-rain', title:'Monthly rainfall', body:makeClimateRainChart(), legend:legend([{sw:'sw-norm',t:'Normal'},{sw:'sw-year',t:'This year'}]), readout:''})}
    </section>
    <footer class="footer"><p>Forecast and history from <a href="https://open-meteo.com" target="_blank" rel="noopener">Open-Meteo</a> · Places by <a href="https://nominatim.openstreetmap.org" target="_blank" rel="noopener">Nominatim / OpenStreetMap</a></p></footer>
  </div>`;
  setupLazyLoad();
  requestAnimationFrame(updatePin);
}

function setSeg(id){
  document.querySelectorAll('[data-seg]').forEach(b=>{
    const on=b.dataset.seg===id;
    b.classList.toggle('on', on);
    b.setAttribute('aria-selected', on?'true':'false');
  });
}
let _segLock=null, _segTimer=0;
scrollToPanel=function(id){
  const el=document.getElementById(id);
  if(!el) return;
  const pin=document.getElementById('pinbar');
  const h=(pin?.offsetHeight||96)+10;
  const top=el.getBoundingClientRect().top+window.scrollY-h;
  const reduce=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  window.scrollTo({top:Math.max(0, top), behavior:reduce?'auto':'smooth'});
  _segLock=id;
  setSeg(id);
  clearTimeout(_segTimer);
  _segTimer=setTimeout(()=>{ _segLock=null; }, reduce?0:700);
};
function updatePin(){
  const hero=document.getElementById('hero');
  const pin=document.getElementById('pinbar');
  if(!hero||!pin||!fcData) return;
  const barH=pin.offsetHeight||96;
  const t=Math.min(1, Math.max(0, (barH-hero.getBoundingClientRect().bottom)/24));
  const reduce=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  pin.style.opacity=reduce?(t>0.5?'1':'0'):String(t);
  const on=t>0.55;
  pin.classList.toggle('is-on', on);
  pin.style.pointerEvents=on?'auto':'none';
  pin.setAttribute('aria-hidden', on?'false':'true');
  if(_segLock){ setSeg(_segLock); return; }
  const ids=['panel-temperature','panel-wet-bulb','panel-rain','panel-climate'];
  let current=ids[0];
  ids.forEach(id=>{
    const el=document.getElementById(id);
    if(el && el.getBoundingClientRect().top-barH<=56) current=id;
  });
  setSeg(current);
}
function showSkeleton(name){
  document.getElementById('loading')?.classList.add('hidden');
  document.getElementById('error')?.classList.add('hidden');
  document.getElementById('main')?.classList.remove('hidden');
  document.body.classList.add('has-weather');
  document.documentElement.dataset.sky='clear-day';
  const sky=document.getElementById('sky');
  if(sky) sky.hidden=false;
  const label=name?shortLabel(name):'Loading';
  window.scrollTo({top:0,behavior:'auto'});
  const content=document.getElementById('content');
  if(!content) return;
  content.innerHTML=`<section class="hero hero-skel" id="hero">
      <div class="hero-chrome"><span class="loc-pill">${escapeHtml(label)}</span></div>
      <div class="hero-temp skel-bar">—<span class="hero-unit">°</span></div>
      <p class="hero-cond">Loading the forecast…</p>
      <div class="range range-slot"></div>
    </section>
    <div class="sheet"><div class="segs" aria-hidden="true"></div>
      <p class="sec-sub skel-line">Fetching Open-Meteo for ${escapeHtml(label)}.</p>
    </div>`;
}
async function askNotify(){
  if(!('Notification' in window)) return 'unsupported';
  if(Notification.permission!=='default') return Notification.permission;
  try{
    return await Promise.race([
      Notification.requestPermission(),
      new Promise(resolve=>setTimeout(()=>resolve(Notification.permission), 1600))
    ]);
  }catch{ return Notification.permission; }
}
async function useMyLocation(){
  closePlaces();
  try{
    if(myLat==null){
      const pos=await getPos();
      const name=await geocode(pos.coords.latitude, pos.coords.longitude);
      myLat=pos.coords.latitude; myLon=pos.coords.longitude; myName=name;
    }
    await loadWeather(myLat, myLon, myName, 'geo');
  }catch(e){
    showErr(e.message||'Location is unavailable. Search for a place instead.');
  }
}
function loadSaved(i){
  const p=savedList()[i];
  if(!p) return;
  closePlaces();
  customLat=p.lat; customLon=p.lon; customName=p.label||p.name;
  loadWeather(p.lat, p.lon, p.label||p.name, 'custom').catch(e=>showErr(e.message||'Failed to load weather.'));
}

function applyReadout(key, num, unit, ctxHtml){
  const root=document.querySelector(`.chart-mod[data-chart-key="${key}"] .mod-read`);
  if(!root) return;
  const numEl=root.querySelector('.mod-num');
  const unitEl=root.querySelector('.mod-unit');
  const ctxEl=root.querySelector('.mod-ctx');
  if(numEl) numEl.textContent=num;
  if(unitEl) unitEl.textContent=unit;
  if(ctxEl) ctxEl.innerHTML=ctxHtml;
}
window.restoreChartReadout=function(){
  Object.entries(readoutBase).forEach(([key,v])=>applyReadout(key, v.num, v.unit, v.ctx));
};
window.updateChartReadout=function(chartType, i){
  try{
    if(chartType==='hourly'&&_hourlyData){
      const v=_hourlyData.temps[i], u=_hourlyData.histLine[i];
      const toC=x=>x==null?null:imp?(x-32)*5/9:x;
      const parts=tempParts(toC(v));
      const d=v!=null&&u!=null?degFrom(toC(v)-toC(u)):null;
      const hr=+_hourlyData.times[i].slice(11,13);
      const label=i<_hourlyData.nowIdx?'Observed':i===_hourlyData.nowIdx?'Now':'Forecast';
      applyReadout('hourly', parts.num, parts.unit, ctx(label, d?`· ${d.near?'near the usual':d.text+' than usual'} for ${hourClock(hr)}`:''));
    } else if(chartType==='temp'&&_tempData){
      const parts={num:String(Math.round(_tempData.maxV[i])), unit:imp?'°F':'°C'};
      const date=fcData.daily.time[i];
      const a=dayAnomC(i);
      const band=_tempData.dailyAvg?.[i];
      const rest=a!=null&&band?`· ${degFrom(a).text} (${Math.round(nT(band.tMax))}° / ${Math.round(nT(band.tMin))}°)`:'';
      const label=i===_tempData.todayIdx?'Today':i<_tempData.todayIdx?'Observed':'Forecast';
      applyReadout('temp', parts.num, parts.unit, ctx(label, rest));
    } else if(chartType==='hourly-rain'&&_hourlyRainData){
      const html=hourlyRainReadout(i, false);
      const wrap=document.createElement('div'); wrap.innerHTML=html; const row=wrap.firstElementChild;
      applyReadout('hourly-rain', row.querySelector('.mod-num').textContent, row.querySelector('.mod-unit').textContent, row.querySelector('.mod-ctx').innerHTML);
    } else if(chartType==='daily-rain'&&_dailyRainData){
      const html=dailyRainReadout(i, false);
      const wrap=document.createElement('div'); wrap.innerHTML=html; const row=wrap.firstElementChild;
      applyReadout('daily-rain', row.querySelector('.mod-num').textContent, row.querySelector('.mod-unit').textContent, row.querySelector('.mod-ctx').innerHTML);
    }
    else if(chartType==='hourly-wb'&&_hourlyWbData){
      const v=_hourlyWbData.vals[i];
      const parts=tempParts(imp?(v-32)*5/9:v);
      const label=i<_hourlyWbData.nowIdx?'Observed':i===_hourlyWbData.nowIdx?'Now':'Forecast';
      applyReadout('hourly-wb', parts.num, parts.unit, ctx(label, ''));
    }
  }catch{}
};

document.addEventListener('click', async (e)=>{
  const open=e.target.closest('[data-open]');
  if(open){
    e.preventDefault();
    if(open.dataset.open==='settings') openSettings();
    if(open.dataset.open==='places') openPlaces();
    return;
  }
  const close=e.target.closest('[data-close]');
  if(close){
    if(close.dataset.close==='settings') closeSettings();
    if(close.dataset.close==='place') closePlaces();
    if(close.dataset.close==='detail') document.getElementById('detail-modal')?.classList.add('hidden');
    return;
  }
  if(e.target.classList?.contains('modal')){
    e.target.classList.add('hidden');
    return;
  }
  const seg=e.target.closest('[data-seg]');
  if(seg){ e.preventDefault(); scrollToPanel(seg.dataset.seg); return; }
  const unit=e.target.closest('[data-unit]');
  if(unit){
    imp=unit.dataset.unit==='imp';
    savePrefs({imp});
    renderContent();
    paintSettings();
    return;
  }
  const theme=e.target.closest('[data-theme]');
  if(theme){
    if(theme.dataset.theme==='auto'){
      delete document.documentElement.dataset.theme;
      savePrefs({theme:'auto'});
    } else applyTheme(theme.dataset.theme);
    renderContent();
    paintSettings();
    return;
  }
  if(e.target.closest('[data-notify]')){ await askNotify(); paintSettings(); return; }
  if(e.target.closest('[data-alert-on]')){
    savePrefs({alertStart:true});
    await askNotify();
    const node=document.getElementById('alert-offer');
    if(node) node.remove();
    if(!document.getElementById('settings-modal')?.classList.contains('hidden')) paintSettings();
    return;
  }
  if(e.target.closest('[data-alert-dismiss]')){
    savePrefs({alertOfferDismissed:true});
    document.getElementById('alert-offer')?.remove();
    return;
  }
  const detail=e.target.closest('[data-detail]');
  if(detail){ openDetail(detail.dataset.detail); return; }
  if(e.target.closest('[data-expand-wb]')){
    wbExpanded=!wbExpanded;
    renderContent();
    return;
  }
  if(e.target.closest('[data-use-geo]')){ useMyLocation(); return; }
  const place=e.target.closest('[data-place]');
  if(place){ loadSaved(+place.dataset.place); return; }
  const remove=e.target.closest('[data-remove-place]');
  if(remove){
    const list=savedList().filter((_,i)=>i!==+remove.dataset.removePlace);
    savePrefs({savedLocations:list});
    renderSavedRows();
    return;
  }
  const copy=e.target.closest('[data-copy]');
  if(copy){
    const text=copy.dataset.copy||'';
    try{ await navigator.clipboard.writeText(text); copy.textContent='Copied'; }
    catch{ copy.textContent='Copy failed'; }
    return;
  }
});
document.addEventListener('change', async (e)=>{
  const box=e.target.closest('[data-alert]');
  if(!box) return;
  const on=box.checked;
  if(box.dataset.alert==='start') savePrefs({alertStart:on});
  else savePrefs({alertHeavy:on});
  if(on) await askNotify();
  paintSettings();
  if(on) document.getElementById('alert-offer')?.remove();
});
document.addEventListener('keydown', (e)=>{
  if(e.key==='Escape'){
    document.querySelectorAll('.modal').forEach(m=>m.classList.add('hidden'));
    return;
  }
  if(e.target.id==='srch' && !e.target.closest('#app-hdr')) onSearchKey(e);
});
document.addEventListener('input', (e)=>{
  if(e.target.id==='srch' && !e.target.closest('#app-hdr')) onSearchInput(e.target.value);
});
window.addEventListener('scroll', ()=>{ updatePin(); }, {passive:true});

const _headerBeforeScreen=renderHeader;
renderHeader=function(){
  if(!fcData){
    document.body.classList.remove('has-weather');
    document.getElementById('sky')?.setAttribute('hidden','');
    document.documentElement.removeAttribute('data-sky');
    const pin=document.getElementById('pinbar');
    if(pin){ pin.innerHTML=''; pin.style.opacity='0'; }
    _headerBeforeScreen();
    return;
  }
  document.body.classList.add('has-weather');
  const el=document.getElementById('app-hdr');
  if(el) el.innerHTML='';
};
renderContent=function(){
  paintScreen();
  if(typeof bindChartAccessibility==='function') bindChartAccessibility();
};

window.rememberPlace=rememberPlace;
window.closePlaces=closePlaces;
window.showSkeleton=showSkeleton;
window.renderPlaceIdle=renderPlaceIdle;
window.kmBetween=kmBetween;
window.shortLabel=shortLabel;
