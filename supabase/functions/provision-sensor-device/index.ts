import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
const hex=(bytes:Uint8Array)=>Array.from(bytes).map(b=>b.toString(16).padStart(2,"0")).join("");
async function sha256(value:string){return hex(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))))}

Deno.serve(async(req)=>{
  if(req.method!=="POST") return json({error:"POST only"},405);
  const auth=req.headers.get("authorization");
  if(!auth) return json({error:"Missing authorization"},401);
  const userClient=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:userData,error:userError}=await userClient.auth.getUser();
  if(userError||!userData.user) return json({error:"Invalid session"},401);
  const body=await req.json().catch(()=>({}));
  const farmId=String(body?.farm_id??"");
  const deviceUid=String(body?.device_uid??"").trim();
  if(!farmId||!deviceUid) return json({error:"farm_id and device_uid are required"},400);
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:farm}=await admin.from("farms").select("id,owner_id").eq("id",farmId).maybeSingle();
  if(!farm||farm.owner_id!==userData.user.id) return json({error:"Farm owner permission required"},403);
  const raw=new Uint8Array(32);crypto.getRandomValues(raw);const token=Array.from(raw).map(b=>b.toString(16).padStart(2,"0")).join("");
  const secretHash=await sha256(token);
  const sensorModels=Array.isArray(body?.sensor_models)?body.sensor_models.map(String):["MPU6050","SHT40","SC4-O2","SCT-013","TP4056 + LiPo 3.7V 5000mAh"];
  const payload={farm_id:farmId,device_uid:deviceUid,device_type:String(body?.device_type??"vetai_sensor_hub"),controller_model:"ESP32-C3 SuperMini",sensor_models:sensorModels,battery_capacity_mah:5000,power_module:"TP4056",device_secret_hash:secretHash,firmware_version:String(body?.firmware_version??""),capabilities:{motion:sensorModels.includes("MPU6050"),environment:sensorModels.includes("SHT40"),oxygen:sensorModels.includes("SC4-O2"),power:sensorModels.includes("SCT-013"),battery:true},active:true};
  const {data,error}=await admin.from("sensor_devices").upsert(payload,{onConflict:"device_uid"}).select("id,device_uid,device_type,controller_model,sensor_models").single();
  if(error) return json({error:error.message},500);
  return json({device:data,device_token:token,warning:"Store this device token in ESP32 secure configuration. It is returned only for provisioning."});
});
