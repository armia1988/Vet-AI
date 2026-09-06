import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"content-type":"application/json; charset=utf-8","cache-control":"no-store"}});
const shortLang=(v:string)=>v.trim().toLowerCase().split(/[-_]/)[0]||"en";
const sanitize=(input:string)=>input.replace(/https?:\/\/\S+/gi," ").replace(/www\.\S+/gi," ").replace(/[`*_#]+/g," ").replace(/[•●▪◦‣⁃]+/g,". ").replace(/(^|\n)\s*[-–—]+\s*/gm,". ").replace(/\s+/g," ").trim().slice(0,1200);

const chirpLocales:Record<string,string>={ar:"ar-XA",en:"en-GB",nl:"nl-NL",de:"de-DE",fr:"fr-FR",es:"es-ES",it:"it-IT",pt:"pt-BR",tr:"tr-TR",ru:"ru-RU",pl:"pl-PL",uk:"uk-UA",ro:"ro-RO",el:"el-GR",cs:"cs-CZ",sk:"sk-SK",hu:"hu-HU",bg:"bg-BG",hr:"hr-HR",sr:"sr-RS",sl:"sl-SI",sv:"sv-SE",no:"nb-NO",da:"da-DK",fi:"fi-FI",he:"he-IL",hi:"hi-IN",bn:"bn-IN",ta:"ta-IN",te:"te-IN",ml:"ml-IN",mr:"mr-IN",gu:"gu-IN",kn:"kn-IN",zh:"cmn-CN",ja:"ja-JP",ko:"ko-KR",th:"th-TH",vi:"vi-VN",id:"id-ID",sw:"sw-KE"};
const chirpVoice=(language:string)=>{const code=chirpLocales[shortLang(language)]??"en-GB";return{languageCode:code,name:`${code}-Chirp3-HD-Charon`}};

function bytesToB64(bytes:Uint8Array){let out="";for(let i=0;i<bytes.length;i+=0x8000)out+=String.fromCharCode(...bytes.subarray(i,Math.min(i+0x8000,bytes.length)));return btoa(out)}
function b64urlBytes(bytes:Uint8Array){return bytesToB64(bytes).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,"")}
function b64urlText(v:string){return b64urlBytes(new TextEncoder().encode(v))}
async function serviceAccountAccess(raw:string){
  try{
    const sa=JSON.parse(raw);const email=String(sa?.client_email??"");const pem=String(sa?.private_key??"");const project=String(sa?.project_id??"");
    if(!email||!pem)return{token:null as string|null,project,error:"service_account_missing_fields"};
    const body=pem.replace(/-----BEGIN PRIVATE KEY-----/g,"").replace(/-----END PRIVATE KEY-----/g,"").replace(/\s+/g,"");
    const bin=atob(body);const bytes=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);
    const key=await crypto.subtle.importKey("pkcs8",bytes.buffer,{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
    const now=Math.floor(Date.now()/1000);const h=b64urlText(JSON.stringify({alg:"RS256",typ:"JWT"}));const p=b64urlText(JSON.stringify({iss:email,scope:"https://www.googleapis.com/auth/cloud-platform",aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+1200}));
    const unsigned=`${h}.${p}`;const sig=await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,new TextEncoder().encode(unsigned));const assertion=`${unsigned}.${b64urlBytes(new Uint8Array(sig))}`;
    const r=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion})});
    const j=await r.json().catch(()=>null);return{token:r.ok&&typeof j?.access_token==="string"?j.access_token:null,project,error:r.ok?"":String(j?.error_description??j?.error??`http_${r.status}`).slice(0,300)};
  }catch(e){return{token:null as string|null,project:"",error:String(e).slice(0,300)}}
}
async function cloudRequest(body:any,auth:{token?:string,key?:string,project?:string},timeoutMs:number){
  const qs=auth.key?`?key=${encodeURIComponent(auth.key)}`:"";const c=new AbortController();const timer=setTimeout(()=>c.abort(),timeoutMs);const started=Date.now();
  try{
    const r=await fetch(`https://texttospeech.googleapis.com/v1/text:synthesize${qs}`,{method:"POST",signal:c.signal,headers:{"content-type":"application/json",...(auth.token?{authorization:`Bearer ${auth.token}`}:{}) ,...(auth.project?{"x-goog-user-project":auth.project}:{})},body:JSON.stringify(body)});
    const j=await r.json().catch(()=>null);const audio=typeof j?.audioContent==="string"?j.audioContent:"";
    return{ok:r.ok&&!!audio,status:r.status,audio,detail:String(j?.error?.message??"").slice(0,350),ms:Date.now()-started};
  }catch(e){return{ok:false,status:0,audio:"",detail:e instanceof DOMException&&e.name==="AbortError"?"timeout":String(e).slice(0,350),ms:Date.now()-started};}
  finally{clearTimeout(timer)}
}
async function generativeGemini(text:string,language:string,key:string){
  const l=shortLang(language);const ar=l==="ar";const prompt=ar?`اتكلم بالمصري القاهري الطبيعي بصوت دكتور بيطري راجل، هادي ومهني، وانطق النص كما هو بدون إضافة أو حذف:\n${text}`:`Read this exact veterinary text naturally in ${language}, warm professional male voice. Do not add or remove words:\n${text}`;
  for(const model of ["gemini-3.1-flash-tts-preview","gemini-2.5-flash-preview-tts"]){
    const c=new AbortController();const timer=setTimeout(()=>c.abort(),12000);const started=Date.now();
    try{
      const r=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,{method:"POST",signal:c.signal,headers:{"x-goog-api-key":key,"content-type":"application/json"},body:JSON.stringify({contents:[{role:"user",parts:[{text:prompt}]}],generationConfig:{responseModalities:["AUDIO"],speechConfig:{voiceConfig:{prebuiltVoiceConfig:{voiceName:"Charon"}}}}})});
      const j=await r.json().catch(()=>null);const part=j?.candidates?.[0]?.content?.parts?.find((p:any)=>p?.inlineData?.data||p?.inline_data?.data);const raw=part?.inlineData?.data??part?.inline_data?.data;
      if(r.ok&&typeof raw==="string"&&raw)return{ok:true,status:r.status,audio:raw,detail:"",model,ms:Date.now()-started,mime:"audio/pcm"};
      const detail=String(j?.error?.message??j?.candidates?.[0]?.finishReason??"empty_audio").slice(0,350);if(model.endsWith("preview-tts"))return{ok:false,status:r.status,audio:"",detail,model,ms:Date.now()-started,mime:""};
    }catch(e){if(model.endsWith("preview-tts"))return{ok:false,status:0,audio:"",detail:e instanceof DOMException&&e.name==="AbortError"?"timeout":String(e).slice(0,350),model,ms:Date.now()-started,mime:""};}
    finally{clearTimeout(timer)}
  }
  return{ok:false,status:0,audio:"",detail:"no_audio",model:"gemini-tts",ms:0,mime:""};
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  const auth=req.headers.get("Authorization");if(!auth)return json({error:"Missing authorization"},401);
  const userClient=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:userData,error:userError}=await userClient.auth.getUser();if(userError||!userData.user)return json({error:"Invalid session"},401);
  const body=await req.json().catch(()=>({}));const text=sanitize(typeof body?.text==="string"?body.text:"");const language=typeof body?.language==="string"&&body.language.trim()?body.language.trim().toLowerCase():"en";
  if(!text)return json({error:"Text is required"},400);
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  const log=async(provider:string,model:string,outcome:string,status:number,detail:string)=>{try{await admin.from("voice_provider_events").insert({user_id:userData.user.id,requested_language:language,provider,model_or_voice:model,outcome,http_status:status||null,detail:(detail||"").slice(0,500)||null});}catch(_){}};
  await log("case-voice","v15","request_started",0,`lang=${language}`);
  const googleKey=Deno.env.get("GOOGLE_API_KEY")?.trim()??"";const geminiKey=Deno.env.get("GEMINI_API_KEY")?.trim()??"";const saRaw=Deno.env.get("GOOGLE_CLOUD_TTS_SERVICE_ACCOUNT_JSON")?.trim()??"";
  const l=shortLang(language);

  if(l==="ar"&&saRaw){
    const sa=await serviceAccountAccess(saRaw);await log("google-cloud-oauth","service-account",sa.token?"success":"failure",0,sa.error);
    if(sa.token){
      const g=await cloudRequest({input:{prompt:"اتكلم بالمصري القاهري الطبيعي بصوت دكتور بيطري راجل، هادي ومهني. انطق النص كما هو بدون إضافة أو حذف.",text},voice:{languageCode:"ar-EG",name:"Charon",modelName:"gemini-2.5-flash-tts"},audioConfig:{audioEncoding:"MP3"}},{token:sa.token,project:sa.project},15000);
      await log("google-cloud-gemini-tts","gemini-2.5-flash-tts/ar-EG/Charon",g.ok?"success":g.detail==="timeout"?"timeout":"failure",g.status,`${g.detail}; ${g.ms}ms`);
      if(g.ok)return json({audio_base64:g.audio,audioContent:g.audio,mime_type:"audio/mpeg",provider:"google-cloud-gemini-tts",voice:"Charon",model:"gemini-2.5-flash-tts",requested_language:language,egyptian_style:true});
    }
  } else if(l==="ar") await log("google-cloud-gemini-tts","service-account","not_configured",0,"GOOGLE_CLOUD_TTS_SERVICE_ACCOUNT_JSON missing");

  if(googleKey){
    const v=chirpVoice(language);const c=await cloudRequest({input:{text},voice:v,audioConfig:{audioEncoding:"MP3"}},{key:googleKey},9000);
    await log("google-cloud-chirp3",v.name,c.ok?"success":c.detail==="timeout"?"timeout":"failure",c.status,`${c.detail}; ${c.ms}ms`);
    if(c.ok)return json({audio_base64:c.audio,audioContent:c.audio,mime_type:"audio/mpeg",provider:"google-cloud-chirp3",voice:v.name,requested_language:language,egyptian_style:false});
  } else await log("google-cloud-chirp3","api-key","not_configured",0,"GOOGLE_API_KEY missing");

  if(geminiKey){const g=await generativeGemini(text,language,geminiKey);await log("gemini-generative-tts",g.model,g.ok?"success":g.detail==="timeout"?"timeout":"failure",g.status,`${g.detail}; ${g.ms}ms`);if(g.ok)return json({audio_base64:g.audio,audioContent:g.audio,mime_type:g.mime,provider:"gemini-generative-tts",voice:"Charon",model:g.model,requested_language:language,egyptian_style:l==="ar"});}
  else await log("gemini-generative-tts","api-key","not_configured",0,"GEMINI_API_KEY missing");

  return json({code:"VOICE_TEMPORARILY_UNAVAILABLE",google_api_key_configured:Boolean(googleKey),service_account_configured:Boolean(saRaw),gemini_key_configured:Boolean(geminiKey)},503);
});