import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
const hex=(bytes:Uint8Array)=>Array.from(bytes).map(b=>b.toString(16).padStart(2,"0")).join("");
async function sha256(value:string){return hex(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))))}
const num=(v:any)=>typeof v==="number"&&Number.isFinite(v)?v:null;

Deno.serve(async(req)=>{
  if(req.method!=="POST") return json({error:"POST only"},405);
  const body=await req.json().catch(()=>({}));
  const deviceUid=String(body?.device_uid??"").trim();
  const token=String(body?.device_token??"").trim();
  const reading=body?.reading&&typeof body.reading==="object"?body.reading:{};
  if(!deviceUid||!token) return json({error:"device_uid and device_token are required"},401);
  const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:device,error:deviceError}=await admin.from("sensor_devices").select("id,farm_id,animal_id,active,device_secret_hash").eq("device_uid",deviceUid).maybeSingle();
  if(deviceError||!device||device.active!==true) return json({error:"Unknown or inactive device"},401);
  if((await sha256(token))!==device.device_secret_hash) return json({error:"Invalid device token"},401);

  const ax=num(reading.accel_x_g), ay=num(reading.accel_y_g), az=num(reading.accel_z_g);
  let activity=num(reading.activity_index);
  if(activity==null&&ax!=null&&ay!=null&&az!=null){const magnitude=Math.sqrt(ax*ax+ay*ay+az*az);activity=Math.abs(magnitude-1);}
  const payload:any={device_id:device.id,farm_id:device.farm_id,animal_id:device.animal_id,recorded_at:String(reading.recorded_at??new Date().toISOString()),ambient_temperature_c:num(reading.ambient_temperature_c),humidity_percent:num(reading.humidity_percent),activity_index:activity,steps:Number.isInteger(reading.steps)?reading.steps:null,lying_minutes:num(reading.lying_minutes),feeding_minutes:num(reading.feeding_minutes),rumination_minutes:num(reading.rumination_minutes),accel_x_g:ax,accel_y_g:ay,accel_z_g:az,oxygen_percent:num(reading.oxygen_percent),current_amp:num(reading.current_amp),battery_voltage_v:num(reading.battery_voltage_v),battery_percent:num(reading.battery_percent),charging:typeof reading.charging==="boolean"?reading.charging:null,raw:reading.raw&&typeof reading.raw==="object"?reading.raw:{}};
  const {data:inserted,error}=await admin.from("sensor_readings").insert(payload).select("id,recorded_at").single();
  if(error) return json({error:error.message},500);
  await admin.from("sensor_devices").update({last_seen_at:new Date().toISOString()}).eq("id",device.id);
  return json({ok:true,reading_id:inserted.id,recorded_at:inserted.recorded_at});
});
