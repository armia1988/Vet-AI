#!/usr/bin/env python3
"""Vet AI local camera gateway.

Runs on an always-on machine inside the farm LAN. It keeps ONVIF PullPoint
subscriptions alive, polls supported Hikvision/HIKMICRO thermometry rules, and
forwards only normalized camera events/threshold crossings to the authenticated
Vet AI camera-gateway-ingest Edge Function.

The phone is not part of the monitoring path after this agent starts.
"""

from __future__ import annotations

import base64
import datetime as dt
import hashlib
import json
import os
import platform
import signal
import socket
import sys
import threading
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from html import escape
from pathlib import Path
from typing import Any

AGENT_VERSION = "0.1.0-v93"
DEFAULT_CONFIG = "camera_gateway_config.json"
STOP = threading.Event()
LOCK = threading.Lock()

SOAP_NS = "http://www.w3.org/2003/05/soap-envelope"
WSA_NS = "http://www.w3.org/2005/08/addressing"
WSSE_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
WSU_NS = "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"
TEV_NS = "http://www.onvif.org/ver10/events/wsdl"
TDS_NS = "http://www.onvif.org/ver10/device/wsdl"


def iso_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def wsse_security(username: str, password: str) -> str:
    if not username:
        return ""
    nonce = os.urandom(16)
    created = iso_now()
    digest = hashlib.sha1(nonce + created.encode("utf-8") + password.encode("utf-8")).digest()
    digest_b64 = base64.b64encode(digest).decode("ascii")
    nonce_b64 = base64.b64encode(nonce).decode("ascii")
    return f"""
      <wsse:Security soap:mustUnderstand="true">
        <wsse:UsernameToken>
          <wsse:Username>{escape(username)}</wsse:Username>
          <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">{digest_b64}</wsse:Password>
          <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">{nonce_b64}</wsse:Nonce>
          <wsu:Created>{created}</wsu:Created>
        </wsse:UsernameToken>
      </wsse:Security>"""


def envelope(to: str, action: str, username: str, password: str, body: str) -> bytes:
    message_id = f"urn:uuid:{uuid.uuid4()}"
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="{SOAP_NS}" xmlns:wsa="{WSA_NS}" xmlns:wsse="{WSSE_NS}" xmlns:wsu="{WSU_NS}" xmlns:tds="{TDS_NS}" xmlns:tev="{TEV_NS}">
  <soap:Header>
    <wsa:Action soap:mustUnderstand="true">{escape(action)}</wsa:Action>
    <wsa:MessageID>{message_id}</wsa:MessageID>
    <wsa:To soap:mustUnderstand="true">{escape(to)}</wsa:To>
    {wsse_security(username, password)}
  </soap:Header>
  <soap:Body>{body}</soap:Body>
</soap:Envelope>"""
    return xml.encode("utf-8")


def auth_opener(url: str, username: str, password: str) -> urllib.request.OpenerDirector:
    mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    if username:
        mgr.add_password(None, url, username, password)
    return urllib.request.build_opener(
        urllib.request.HTTPDigestAuthHandler(mgr),
        urllib.request.HTTPBasicAuthHandler(mgr),
    )


def http_json(url: str, payload: dict[str, Any], timeout: float = 10.0) -> dict[str, Any]:
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST", headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read().decode("utf-8", errors="replace")
            parsed = json.loads(raw or "{}")
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"HTTP {response.status}: {parsed}")
            return parsed
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {raw[:600]}") from exc


@dataclass
class CameraState:
    online: bool = False
    last_error: str = ""
    last_event_at: str | None = None
    events: int = 0
    thermal_samples: int = 0


@dataclass
class RuntimeState:
    cameras: dict[str, CameraState] = field(default_factory=dict)
    events_forwarded: int = 0
    thermal_samples: int = 0
    last_error: str = ""

    def snapshot(self) -> dict[str, Any]:
        with LOCK:
            online = sum(1 for value in self.cameras.values() if value.online)
            return {
                "cameras_configured": len(self.cameras),
                "cameras_online": online,
                "events_forwarded": self.events_forwarded,
                "thermal_samples": self.thermal_samples,
                "last_error": self.last_error,
                "runtime": {
                    uid: {
                        "online": state.online,
                        "last_error": state.last_error,
                        "last_event_at": state.last_event_at,
                        "events": state.events,
                        "thermal_samples": state.thermal_samples,
                    }
                    for uid, state in self.cameras.items()
                },
            }


class GatewaySender:
    def __init__(self, cfg: dict[str, Any], state: RuntimeState):
        base = str(cfg["supabase_url"]).rstrip("/")
        self.endpoint = f"{base}/functions/v1/camera-gateway-ingest"
        self.gateway_uid = str(cfg["gateway_device_uid"])
        self.gateway_token = str(cfg["gateway_device_token"])
        self.state = state

    def send(self, payload: dict[str, Any], timeout: float = 10.0) -> dict[str, Any]:
        base = {
            "gateway_device_uid": self.gateway_uid,
            "gateway_device_token": self.gateway_token,
        }
        base.update(payload)
        return http_json(self.endpoint, base, timeout=timeout)

    def heartbeat(self) -> None:
        snap = self.state.snapshot()
        self.send({
            "kind": "heartbeat",
            "agent_version": AGENT_VERSION,
            "hostname": socket.gethostname(),
            "platform": platform.platform(),
            **snap,
        })


class OnvifCamera:
    def __init__(self, cfg: dict[str, Any]):
        self.cfg = cfg
        self.uid = str(cfg["camera_uid"])
        self.name = str(cfg.get("name") or self.uid)
        self.host = str(cfg["host"])
        self.port = int(cfg.get("http_port", 80))
        self.username = str(cfg.get("username", ""))
        self.password = str(cfg.get("password", ""))
        self.device_url = str(cfg.get("device_service") or f"http://{self.host}:{self.port}/onvif/device_service")
        self.events_url = str(cfg.get("events_xaddr") or "")

    def soap(self, url: str, action: str, body: str, timeout: float = 12.0) -> ET.Element:
        req = urllib.request.Request(
            url,
            data=envelope(url, action, self.username, self.password, body),
            method="POST",
            headers={"content-type": f'application/soap+xml; charset=utf-8; action="{action}"'},
        )
        opener = auth_opener(url, self.username, self.password)
        try:
            with opener.open(req, timeout=timeout) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"ONVIF HTTP {exc.code}: {detail[:500]}") from exc
        root = ET.fromstring(raw)
        for node in root.iter():
            if local_name(node.tag) == "Fault":
                text = " ".join((part.text or "").strip() for part in node.iter() if (part.text or "").strip())
                raise RuntimeError(f"ONVIF SOAP fault: {text[:600]}")
        return root

    def discover_events_url(self) -> str:
        if self.events_url:
            return self.events_url
        action = "http://www.onvif.org/ver10/device/wsdl/GetCapabilities"
        root = self.soap(self.device_url, action, "<tds:GetCapabilities><tds:Category>All</tds:Category></tds:GetCapabilities>")
        for node in root.iter():
            if local_name(node.tag) != "Events":
                continue
            for child in node.iter():
                if local_name(child.tag) == "XAddr" and (child.text or "").strip():
                    self.events_url = (child.text or "").strip()
                    return self.events_url
        raise RuntimeError("Camera did not report an ONVIF Events XAddr")

    def create_pullpoint(self) -> str:
        events_url = self.discover_events_url()
        action = "http://www.onvif.org/ver10/events/wsdl/EventPortType/CreatePullPointSubscriptionRequest"
        body = "<tev:CreatePullPointSubscription><tev:InitialTerminationTime>PT10M</tev:InitialTerminationTime></tev:CreatePullPointSubscription>"
        root = self.soap(events_url, action, body)
        for node in root.iter():
            if local_name(node.tag) == "SubscriptionReference":
                for child in node.iter():
                    if local_name(child.tag) == "Address" and (child.text or "").strip():
                        return (child.text or "").strip()
        raise RuntimeError("ONVIF CreatePullPointSubscription returned no subscription address")

    def pull_messages(self, subscription_url: str, timeout_seconds: int) -> list[dict[str, Any]]:
        action = "http://www.onvif.org/ver10/events/wsdl/PullPointSubscription/PullMessagesRequest"
        body = f"<tev:PullMessages><tev:Timeout>PT{max(1, timeout_seconds)}S</tev:Timeout><tev:MessageLimit>32</tev:MessageLimit></tev:PullMessages>"
        root = self.soap(subscription_url, action, body, timeout=float(timeout_seconds + 10))
        result: list[dict[str, Any]] = []
        for notification in root.iter():
            if local_name(notification.tag) != "NotificationMessage":
                continue
            topic = ""
            operation = ""
            utc_time = iso_now()
            values: dict[str, str] = {}
            for node in notification.iter():
                name = local_name(node.tag)
                if name == "Topic" and (node.text or "").strip():
                    topic = (node.text or "").strip()
                elif name == "Message":
                    utc_time = node.attrib.get("UtcTime", utc_time)
                    operation = node.attrib.get("PropertyOperation", operation)
                elif name == "SimpleItem":
                    key = node.attrib.get("Name")
                    value = node.attrib.get("Value")
                    if key and value is not None:
                        values[key] = value
            if topic or values:
                result.append({"topic": topic, "operation": operation, "utc_time": utc_time, "values": values})
        return result

    def thermal_rule_sample(self, thermal: dict[str, Any]) -> dict[str, Any]:
        channel = int(thermal.get("channel_id", 1))
        scene = int(thermal.get("scene_id", 1))
        rule = int(thermal.get("rule_id", 1))
        url = f"http://{self.host}:{self.port}/ISAPI/Thermal/channels/{channel}/thermometry/{scene}/rulesTemperatureInfo/{rule}?format=json"
        req = urllib.request.Request(url, method="GET", headers={"accept": "application/json"})
        opener = auth_opener(url, self.username, self.password)
        with opener.open(req, timeout=10.0) as response:
            data = json.loads(response.read().decode("utf-8", errors="replace") or "{}")
        source = data
        if isinstance(data, dict):
            for key in ("ThermometryRulesTemperatureInfo", "rulesTemperatureInfo", "RuleTemperatureInfo"):
                if isinstance(data.get(key), dict):
                    source = data[key]
                    break
        if not isinstance(source, dict):
            raise RuntimeError("Unexpected Hikvision thermometry response")
        maximum = source.get("maxTemperature")
        minimum = source.get("minTemperature")
        average = source.get("averageTemperature")
        if maximum is None:
            raise RuntimeError("Thermometry response did not include maxTemperature")
        return {
            "max_temperature_c": float(maximum),
            "min_temperature_c": float(minimum) if minimum is not None else None,
            "average_temperature_c": float(average) if average is not None else None,
            "topic": "hikvision/thermal/rule",
            "utc_time": iso_now(),
        }


def mark_state(state: RuntimeState, uid: str, *, online: bool | None = None, error: str | None = None, event: bool = False, thermal: bool = False) -> None:
    with LOCK:
        camera = state.cameras[uid]
        if online is not None:
            camera.online = online
        if error is not None:
            camera.last_error = error[:1000]
            state.last_error = error[:1000]
        if event:
            camera.events += 1
            camera.last_event_at = iso_now()
            state.events_forwarded += 1
        if thermal:
            camera.thermal_samples += 1
            state.thermal_samples += 1


def event_worker(camera_cfg: dict[str, Any], sender: GatewaySender, state: RuntimeState, pull_timeout: int) -> None:
    camera = OnvifCamera(camera_cfg)
    uid = camera.uid
    backoff = 2.0
    while not STOP.is_set():
        try:
            subscription = camera.create_pullpoint()
            mark_state(state, uid, online=True, error="")
            backoff = 2.0
            while not STOP.is_set():
                for event in camera.pull_messages(subscription, pull_timeout):
                    sender.send({"kind": "event", "camera_uid": uid, **event}, timeout=float(pull_timeout + 15))
                    mark_state(state, uid, online=True, error="", event=True)
        except Exception as exc:
            mark_state(state, uid, online=False, error=f"{camera.name}: {exc}")
            STOP.wait(backoff)
            backoff = min(backoff * 2.0, 60.0)


def thermal_worker(camera_cfg: dict[str, Any], sender: GatewaySender, state: RuntimeState, interval: float) -> None:
    camera = OnvifCamera(camera_cfg)
    uid = camera.uid
    thermal = camera_cfg.get("thermal") if isinstance(camera_cfg.get("thermal"), dict) else {}
    while not STOP.is_set():
        try:
            sample = camera.thermal_rule_sample(thermal)
            sender.send({"kind": "thermal_sample", "camera_uid": uid, **sample})
            mark_state(state, uid, online=True, error="", thermal=True)
        except Exception as exc:
            mark_state(state, uid, online=False, error=f"{camera.name} thermal: {exc}")
        STOP.wait(interval)


def heartbeat_worker(sender: GatewaySender, interval: float) -> None:
    while not STOP.is_set():
        try:
            sender.heartbeat()
        except Exception as exc:
            with LOCK:
                sender.state.last_error = f"Heartbeat: {exc}"[:1000]
        STOP.wait(interval)


def load_config(path: str) -> dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    for key in ("supabase_url", "gateway_device_uid", "gateway_device_token"):
        if not str(data.get(key, "")).strip():
            raise ValueError(f"Missing required config field: {key}")
    cameras = data.get("cameras")
    if not isinstance(cameras, list):
        raise ValueError("cameras must be a JSON array")
    seen: set[str] = set()
    for camera in cameras:
        if not isinstance(camera, dict):
            raise ValueError("Each camera entry must be an object")
        for key in ("camera_uid", "host"):
            if not str(camera.get(key, "")).strip():
                raise ValueError(f"Camera missing required field: {key}")
        uid = str(camera["camera_uid"])
        if uid in seen:
            raise ValueError(f"Duplicate camera_uid: {uid}")
        seen.add(uid)
    return data


def main() -> int:
    config_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VET_AI_CAMERA_GATEWAY_CONFIG", DEFAULT_CONFIG)
    try:
        cfg = load_config(config_path)
    except Exception as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2

    state = RuntimeState()
    cameras: list[dict[str, Any]] = cfg.get("cameras", [])
    for camera in cameras:
        state.cameras[str(camera["camera_uid"])] = CameraState()
    sender = GatewaySender(cfg, state)

    heartbeat_seconds = max(10.0, float(cfg.get("heartbeat_seconds", 30)))
    pull_timeout = max(5, int(cfg.get("pull_timeout_seconds", 20)))
    thermal_poll = max(2.0, float(cfg.get("thermal_poll_seconds", 5)))

    def stop_handler(_signum: int, _frame: Any) -> None:
        STOP.set()

    signal.signal(signal.SIGINT, stop_handler)
    signal.signal(signal.SIGTERM, stop_handler)

    threads: list[threading.Thread] = [
        threading.Thread(target=heartbeat_worker, args=(sender, heartbeat_seconds), name="gateway-heartbeat", daemon=True),
    ]
    for camera in cameras:
        if camera.get("events", True):
            threads.append(threading.Thread(target=event_worker, args=(camera, sender, state, pull_timeout), name=f"onvif-{camera['camera_uid']}", daemon=True))
        thermal = camera.get("thermal")
        if isinstance(thermal, dict) and thermal.get("enabled") is True:
            vendor = str(camera.get("vendor", "")).lower()
            if "hikvision" in vendor or "hikmicro" in vendor:
                threads.append(threading.Thread(target=thermal_worker, args=(camera, sender, state, thermal_poll), name=f"thermal-{camera['camera_uid']}", daemon=True))
            else:
                print(f"Thermal polling skipped for {camera['camera_uid']}: V93 only enables verified Hikvision/HIKMICRO ISAPI thermometry.")

    for thread in threads:
        thread.start()

    print(f"Vet AI Camera Gateway {AGENT_VERSION} running with {len(cameras)} camera(s).")
    print("Monitoring is now local-to-cloud; the mobile app may be closed.")
    while not STOP.wait(1.0):
        pass
    print("Stopping Vet AI Camera Gateway…")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
