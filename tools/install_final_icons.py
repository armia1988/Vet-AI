from pathlib import Path
import base64

mapping = {
    'livestock': 'final_livestock.b64',
    'dog': 'final_dog.b64',
    'poultry': 'final_poultry.b64',
}

payload_dir = Path('tools/icon_payloads')
assets_dir = Path('assets/icons')
assets_dir.mkdir(parents=True, exist_ok=True)

for name, payload_name in mapping.items():
    raw = base64.b64decode((payload_dir / payload_name).read_text().strip())
    (assets_dir / f'{name}_final.png').write_bytes(raw)

app = Path('lib/v5_app.dart')
s = app.read_text()
s = s.replace("assets/icons/livestock.svg", "assets/icons/livestock_final.png")
s = s.replace("assets/icons/poultry.svg", "assets/icons/poultry_final.png")
s = s.replace("assets/icons/dog.svg", "assets/icons/dog_final.png")
s = s.replace(
    "SvgPicture.asset(asset,width:42,height:42)",
    "Image.asset(asset,width:54,height:54,fit:BoxFit.contain,filterQuality:FilterQuality.high)",
)
s = s.replace(
    "SvgPicture.asset(asset,width:47,height:47)",
    "Image.asset(asset,width:62,height:62,fit:BoxFit.contain,filterQuality:FilterQuality.high)",
)
app.write_text(s)
