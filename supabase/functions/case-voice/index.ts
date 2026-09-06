import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const respond=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"content-type":"application/json; charset=utf-8","cache-control":"no-store"}});
const shortLang=(v:string)=>v.trim().toLowerCase().split(/[-_]/)[0]||"en";
const sanitize=(v:string)=>v.replace(/https?:\/\/\S+/gi," ").replace(/www\.\S+/gi," ").replace(/[`*_#]+/g," ").replace(/[•●▪◦‣⁃]+/g,". ").replace(/(^|\n)\s*[-–—]+\s*/gm,". ").replace(/\s+/g," ").trim().slice(0,3600);
const locales:Record<string,string>={ar:"ar-XA",en:"en-GB",nl:"nl-NL",de:"de-DE",fr:"fr-FR",es:"es-ES",it:"it-IT",pt:"pt-BR",tr:"tr-TR",ru:"ru-RU",pl:"pl-PL",uk:"uk-UA",ro:"ro-RO",el:"el-GR",cs:"cs-CZ",sk:"sk-SK",hu:"hu-HU",bg:"bg-BG",hr:"hr-HR",sr:"sr-RS",sl:"sl-SI",sv:"sv-SE",no:"nb-NO",da:"da-DK",fi:"fi-FI",he:"he-IL",hi:"hi-IN",bn:"bn-IN",ta:"ta-IN",te:"te-IN",ml:"ml-IN",mr:"mr-IN",gu:"gu-IN",kn:"kn-IN",zh:"cmn-CN",ja:"ja-JP",ko:"ko-KR",th:"th-TH",vi:"vi-VN",id:"id-ID",sw:"sw-KE"};
const chirpVoice=(language:string)=>{const code=locales[shortLang(language)]??"en-GB";return{languageCode:code,name:`${code}-Chirp3-HD-Charon`}};

async function fetchJson(url:string,init:RequestInit,timeoutMs:number){const c=new AbortController();const t=setTimeout(()=>c.abort(),timeoutMs);const started=Date.now();try{const r=await fetch(url,{...init,signal:c.signal});const j=await r.json().catch(()=>null);return{r,j,ms:Date.now()-started,error:""};}catch(e){return{r:null,j:null,ms:Date.now()-started,error:e instanceof DOMException&&e.name==="AbortError"?"timeout":String(e).slice(0,300)};}finally{clearTimeout(t)}}

async function cloudChirp(text:string,language:string,key:string){const v=chirpVoice(language);const x=await fetchJson(`https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(key)}`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({input:{text},voice:v,audioConfig:{audioEncoding:"MP3"}})},7000);const audio=typeof x.j?.audioContent==="string"?x.j.audioContent:"";return{ok:Boolean(x.r?.ok&&audio),audio,mime:"audio/mpeg",provider:"google-cloud-chirp3",model:v.name,status:x.r?.status??0,detail:String(x.j?.error?.message??x.error??"").slice(0,300),ms:x.ms};}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return respond({error:"Method not allowed"},405);

  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  const log=async(user_id:string|null,language:string|null,provider:string,model:string,outcome:string,status:number,detail:string)=>{try{await admin.from("voice_provider_events").insert({user_id,requested_language:language,provider,model_or_voice:model,outcome,http_status:status||null,detail:(detail||"").slice(0,500)||null});}catch(_){}};

  const auth=req.headers.get("Authorization");
  if(!auth)return respond({code:"VOICE_AUTH_MISSING"},401);
  const userClient=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:userData,error:userError}=await userClient.auth.getUser();
  if(userError||!userData.user){await log(null,null,"case-voice","v21-fast","auth_failure",401,String(userError?.message??"invalid_session"));return respond({code:"VOICE_AUTH_INVALID"},401);}

  const body=await req.json().catch(()=>({}));
  const text=sanitize(typeof body?.text==="string"?body.text:"");
  const language=typeof body?.language==="string"&&body.language.trim()?body.language.trim().toLowerCase():"en";
  if(!text)return respond({error:"Text is required"},400);

  const uid=userData.user.id;
  const googleKey=Deno.env.get("GOOGLE_API_KEY")?.trim()??"";
  if(!googleKey){await log(uid,language,"case-voice","v21-fast","no_provider_configured",0,"GOOGLE_API_KEY missing");return respond({code:"VOICE_NOT_CONFIGURED"},503);}

  await log(uid,language,"case-voice","v21-fast","request_started",0,`lang=${language}; chars=${text.length}; fast_chirp=true`);
  const result=await cloudChirp(text,language,googleKey);
  await log(uid,language,result.provider,result.model,result.ok?"success":result.detail==="timeout"?"timeout":"failure",result.status,`${result.detail}; ${result.ms}ms; fast_chirp=true`);
  if(!result.ok)return respond({code:"VOICE_TEMPORARILY_UNAVAILABLE"},503);

  return respond({audio_base64:result.audio,audioContent:result.audio,mime_type:result.mime,provider:result.provider,voice:result.model,requested_language:language,egyptian_style:shortLang(language)==="ar",text_chars:text.length,fast_path:true});
});
