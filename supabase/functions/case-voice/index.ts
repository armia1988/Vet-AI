import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});
const shortLang = (v: string) => v.trim().toLowerCase().split(/[-_]/)[0] || "en";
const sanitize = (input: string) => input
  .replace(/https?:\/\/\S+/gi, " ").replace(/www\.\S+/gi, " ")
  .replace(/[`*_#]+/g, " ").replace(/[•●▪◦‣⁃]+/g, ". ")
  .replace(/(^|\n)\s*[-–—]+\s*/gm, ". ").replace(/\s+/g, " ").trim().slice(0, 1200);

const b64ToBytes = (value: string) => {
  const b = atob(value); const out = new Uint8Array(b.length);
  for (let i=0;i<b.length;i++) out[i]=b.charCodeAt(i); return out;
};
const bytesToB64 = (bytes: Uint8Array) => {
  let out=""; for (let i=0;i<bytes.length;i+=0x8000) out += String.fromCharCode(...bytes.subarray(i,Math.min(i+0x8000,bytes.length))); return btoa(out);
};
const ascii = (v: DataView,o:number,s:string)=>{for(let i=0;i<s.length;i++)v.setUint8(o+i,s.charCodeAt(i));};
const pcmToWav=(pcm:Uint8Array,rate=24000)=>{const b=new ArrayBuffer(44+pcm.length);const v=new DataView(b);ascii(v,0,"RIFF");v.setUint32(4,36+pcm.length,true);ascii(v,8,"WAVE");ascii(v,12,"fmt ");v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,rate,true);v.setUint32(28,rate*2,true);v.setUint16(32,2,true);v.setUint16(34,16,true);ascii(v,36,"data");v.setUint32(40,pcm.length,true);new Uint8Array(b,44).set(pcm);return new Uint8Array(b);};

const localeMap: Record<string,string> = { ar:"ar-XA", en:"en-GB", nl:"nl-NL", de:"de-DE", fr:"fr-FR", es:"es-ES", it:"it-IT", pt:"pt-BR", tr:"tr-TR", ru:"ru-RU", pl:"pl-PL", uk:"uk-UA", ro:"ro-RO", el:"el-GR", cs:"cs-CZ", sk:"sk-SK", hu:"hu-HU", bg:"bg-BG", hr:"hr-HR", sr:"sr-RS", sl:"sl-SI", sv:"sv-SE", no:"nb-NO", da:"da-DK", fi:"fi-FI", he:"he-IL", hi:"hi-IN", bn:"bn-IN", ta:"ta-IN", te:"te-IN", ml:"ml-IN", mr:"mr-IN", gu:"gu-IN", kn:"kn-IN", zh:"cmn-CN", ja:"ja-JP", ko:"ko-KR", th:"th-TH", vi:"vi-VN", id:"id-ID", sw:"sw-KE" };
const chirpVoice = (language:string) => {
  const l=shortLang(language); const code=localeMap[l] ?? "en-GB";
  return { languageCode: code, name: `${code}-Chirp3-HD-Charon` };
};
function base64Url(bytes: Uint8Array){ return bytesToB64(bytes).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,""); }
function utf8Url(v:string){ return base64Url(new TextEncoder().encode(v)); }
async function serviceAccountToken(raw:string){
  const sa=JSON.parse(raw); const email=String(sa?.client_email??""); const pem=String(sa?.private_key??"");
  if(!email||!pem) return null;
  const body=pem.replace(/-----BEGIN PRIVATE KEY-----/g,"").replace(/-----END PRIVATE KEY-----/g,"").replace(/\s+/g,"");
  const bin=atob(body); const bytes=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);
  const key=await crypto.subtle.importKey("pkcs8",bytes.buffer,{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
  const now=Math.floor(Date.now()/1000); const h=utf8Url(JSON.stringify({alg:"RS256",typ:"JWT"}));
  const p=utf8Url(JSON.stringify({iss:email,scope:"https://www.googleapis.com/auth/cloud-platform",aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3300}));
  const unsigned=`${h}.${p}`; const sig=await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,new TextEncoder().encode(unsigned));
  const assertion=`${unsigned}.${base64Url(new Uint8Array(sig))}`;
  const r=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion})});
  const j=await r.json().catch(()=>null); return r.ok && typeof j?.access_token==="string" ? j.access_token as string : null;
}
async function cloudTts(text:string, language:string, auth:{accessToken?:string,apiKey?:string}){
  const v=chirpVoice(language); const qs=auth.apiKey?`?key=${encodeURIComponent(auth.apiKey)}`:"";
  const c=new AbortController(); const timer=setTimeout(()=>c.abort(),18000);
  try{
    const r=await fetch(`https://texttospeech.googleapis.com/v1/text:synthesize${qs}`,{method:"POST",signal:c.signal,headers:{"content-type":"application/json",...(auth.accessToken?{authorization:`Bearer ${auth.accessToken}`}:{})},body:JSON.stringify({input:{text},voice:v,audioConfig:{audioEncoding:"MP3"}})});
    const j=await r.json().catch(()=>null); const audio=typeof j?.audioContent==="string"?j.audioContent:"";
    return {ok:r.ok&&!!audio,status:r.status,audio,detail:String(j?.error?.message??"").slice(0,300),voice:v.name};
  }catch(e){return {ok:false,status:0,audio:"",detail:e instanceof DOMException&&e.name==="AbortError"?"timeout":String(e),voice:v.name};}
  finally{clearTimeout(timer);}
}
async function geminiTts(text:string, language:string, key:string){
  const ar=shortLang(language)==="ar";
  const style=ar
   ? "SYNTHESIZE SPEECH ONLY. Speak the exact transcript as a real Egyptian male veterinarian from Cairo. Natural Egyptian Arabic pronunciation, warm professional tone, normal conversational rhythm and human pauses. Do not add, remove, translate or explain any words. Do not read these instructions."
   : `SYNTHESIZE SPEECH ONLY. Read the exact transcript naturally in ${language}. Warm professional male veterinarian voice, conversational rhythm and human pauses. Do not add, remove or explain words.`;
  const prompt=`${style}\n\nTRANSCRIPT START\n${text}\nTRANSCRIPT END`;
  for(const model of ["gemini-3.1-flash-tts-preview","gemini-2.5-flash-preview-tts"]){
    const c=new AbortController(); const timer=setTimeout(()=>c.abort(),30000);
    try{
      const r=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,{method:"POST",signal:c.signal,headers:{"x-goog-api-key":key,"content-type":"application/json"},body:JSON.stringify({contents:[{role:"user",parts:[{text:prompt}]}],generationConfig:{responseModalities:["AUDIO"],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:"Charon"}}}}})});
      const j=await r.json().catch(()=>null); const part=j?.candidates?.[0]?.content?.parts?.find((p:any)=>p?.inlineData?.data||p?.inline_data?.data); const raw=part?.inlineData?.data??part?.inline_data?.data;
      if(r.ok&&typeof raw==="string"&&raw){const pcm=b64ToBytes(raw); if(pcm.length>0&&pcm.length<10*1024*1024)return {ok:true,audio:bytesToB64(pcmToWav(pcm)),model,status:r.status,detail:""};}
      const detail=String(j?.error?.message??j?.candidates?.[0]?.finishReason??"empty_audio").slice(0,300);
      if(model==="gemini-2.5-flash-preview-tts") return {ok:false,audio:"",model,status:r.status,detail};
    }catch(e){if(model==="gemini-2.5-flash-preview-tts") return {ok:false,audio:"",model,status:0,detail:e instanceof DOMException&&e.name==="AbortError"?"timeout":String(e)};}
    finally{clearTimeout(timer);}
  }
  return {ok:false,audio:"",model:"gemini-tts",status:0,detail:"no_audio"};
}
Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:corsHeaders});
  if(req.method!=="POST") return json({error:"Method not allowed"},405);
  const auth=req.headers.get("Authorization"); if(!auth)return json({error:"Missing authorization"},401);
  const userClient=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:userData,error:userError}=await userClient.auth.getUser(); if(userError||!userData.user)return json({error:"Invalid session"},401);
  const body=await req.json().catch(()=>({})); const text=sanitize(typeof body?.text==="string"?body.text:""); const language=typeof body?.language==="string"&&body.language.trim()?body.language.trim().toLowerCase():"en";
  if(!text)return json({error:"Text is required"},400);
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  const log=async(provider:string,model:string,outcome:string,status:number,detail:string)=>{try{await admin.from("voice_provider_events").insert({user_id:userData.user.id,requested_language:language,provider,model_or_voice:model,outcome,http_status:status||null,detail:detail.slice(0,500)||null});}catch(_){}};
  const geminiKey=Deno.env.get("GEMINI_API_KEY")?.trim()??""; const googleKey=Deno.env.get("GOOGLE_API_KEY")?.trim()??""; const saRaw=Deno.env.get("GOOGLE_CLOUD_TTS_SERVICE_ACCOUNT_JSON")?.trim()??"";
  if(shortLang(language)==="ar"&&geminiKey){const g=await geminiTts(text,language,geminiKey);await log("gemini-tts",g.model,g.ok?"success":g.detail==="timeout"?"timeout":"failure",g.status,g.detail);if(g.ok)return json({audio_base64:g.audio,audioContent:g.audio,mime_type:"audio/wav",provider:"gemini-tts",voice:"Charon",model:g.model,requested_language:language,egyptian_style:true});}
  if(saRaw){try{const token=await serviceAccountToken(saRaw);if(token){const c=await cloudTts(text,language,{accessToken:token});await log("google-cloud-tts-oauth",c.voice,c.ok?"success":c.detail==="timeout"?"timeout":"failure",c.status,c.detail);if(c.ok)return json({audio_base64:c.audio,audioContent:c.audio,mime_type:"audio/mpeg",provider:"google-cloud-tts",voice:c.voice,requested_language:language});}else await log("google-cloud-tts-oauth","service-account","failure",0,"oauth_token_exchange_failed");}catch(e){await log("google-cloud-tts-oauth","service-account","failure",0,String(e));}}
  else await log("google-cloud-tts-oauth","service-account","not_configured",0,"GOOGLE_CLOUD_TTS_SERVICE_ACCOUNT_JSON missing");
  if(googleKey){const c=await cloudTts(text,language,{apiKey:googleKey});await log("google-cloud-tts-api-key",c.voice,c.ok?"success":c.detail==="timeout"?"timeout":"failure",c.status,c.detail);if(c.ok)return json({audio_base64:c.audio,audioContent:c.audio,mime_type:"audio/mpeg",provider:"google-cloud-tts",voice:c.voice,requested_language:language});}
  else await log("google-cloud-tts-api-key","api-key","not_configured",0,"GOOGLE_API_KEY missing");
  if(shortLang(language)!=="ar"&&geminiKey){const g=await geminiTts(text,language,geminiKey);await log("gemini-tts",g.model,g.ok?"success":g.detail==="timeout"?"timeout":"failure",g.status,g.detail);if(g.ok)return json({audio_base64:g.audio,audioContent:g.audio,mime_type:"audio/wav",provider:"gemini-tts",voice:"Charon",model:g.model,requested_language:language});}
  return json({code:"VOICE_TEMPORARILY_UNAVAILABLE",google_api_key_configured:Boolean(googleKey),service_account_configured:Boolean(saRaw),gemini_key_configured:Boolean(geminiKey)},503);
});