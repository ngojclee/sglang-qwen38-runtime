import asyncio
import os
import time
import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("vast-auto-scaler")

app = FastAPI(title="Vast.ai On-Demand Auto-Scaler Gateway")

VAST_API_KEY = os.getenv("VAST_API_KEY", "")
INSTANCE_POOL = [i.strip() for i in os.getenv("INSTANCE_POOL", "").split(",") if i.strip()]
TARGET_PORT = int(os.getenv("TARGET_PORT", "18000"))
IDLE_TIMEOUT_MINUTES = int(os.getenv("IDLE_TIMEOUT_MINUTES", "20"))
HEALTH_CHECK_TIMEOUT_SECS = int(os.getenv("HEALTH_CHECK_TIMEOUT_SECS", "180"))

# State
last_activity_time = time.time()
active_instance_id = None
active_target_url = None
lock = asyncio.Lock()

async def get_vast_instances():
    """Fetch instance states from Vast.ai API"""
    if not VAST_API_KEY:
        return []
    url = f"https://console.vast.ai/api/v0/instances/?api_key={VAST_API_KEY}"
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get(url)
            if resp.status_code == 200:
                data = resp.json()
                return data.get("instances", [])
        except Exception as e:
            logger.error(f"Error fetching Vast instances: {e}")
    return []

async def start_vast_instance(instance_id: str):
    """Start a stopped instance via Vast.ai API"""
    url = f"https://console.vast.ai/api/v0/instances/{instance_id}/?api_key={VAST_API_KEY}"
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.put(url, json={"state": "running"})
            logger.info(f"Sent START command to instance {instance_id}: status {resp.status_code}")
            return resp.status_code == 200
        except Exception as e:
            logger.error(f"Error starting instance {instance_id}: {e}")
    return False

async def stop_vast_instance(instance_id: str):
    """Stop a running instance via Vast.ai API"""
    url = f"https://console.vast.ai/api/v0/instances/{instance_id}/?api_key={VAST_API_KEY}"
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.put(url, json={"state": "stopped"})
            logger.info(f"Sent STOP command to instance {instance_id}: status {resp.status_code}")
            return resp.status_code == 200
        except Exception as e:
            logger.error(f"Error stopping instance {instance_id}: {e}")
    return False

async def check_target_health(url: str) -> bool:
    """Check if SGLang /v1/models is responding with 200 OK"""
    models_url = f"{url}/v1/models"
    async with httpx.AsyncClient(timeout=3) as client:
        try:
            resp = await client.get(models_url)
            return resp.status_code == 200
        except Exception:
            return False

async def ensure_active_instance() -> str:
    """Ensure at least one instance in the pool is running and healthy, booting if needed"""
    global active_instance_id, active_target_url, last_activity_time
    last_activity_time = time.time()

    async with lock:
        # 1. If we already have an active target and it's healthy, return it
        if active_target_url and await check_target_health(active_target_url):
            return active_target_url

        instances = await get_vast_instances()
        instance_map = {str(inst["id"]): inst for inst in instances}

        # 2. Check if any instance in our pool is currently running & healthy
        for inst_id in INSTANCE_POOL:
            inst = instance_map.get(inst_id)
            if inst and inst.get("actual_status") == "running":
                ssh_host = inst.get("ssh_host")
                # Direct port mapping or direct domain
                target_url = f"http://{ssh_host}:{TARGET_PORT}" if ssh_host else None
                if target_url and await check_target_health(target_url):
                    active_instance_id = inst_id
                    active_target_url = target_url
                    logger.info(f"Found active healthy instance: {inst_id} at {target_url}")
                    return target_url

        # 3. Cold start: boot the first available instance in the pool
        candidate_id = INSTANCE_POOL[0] if INSTANCE_POOL else None
        if not candidate_id:
            raise RuntimeError("No instances configured in INSTANCE_POOL")

        logger.info(f"All instances are idle. Cold starting instance {candidate_id}...")
        await start_vast_instance(candidate_id)

        # 4. Wait loop for SGLang to boot up
        start_time = time.time()
        while time.time() - start_time < HEALTH_CHECK_TIMEOUT_SECS:
            await asyncio.sleep(5)
            fresh_instances = await get_vast_instances()
            fresh_map = {str(inst["id"]): inst for inst in fresh_instances}
            inst = fresh_map.get(candidate_id)
            if inst and inst.get("actual_status") == "running":
                ssh_host = inst.get("ssh_host")
                target_url = f"http://{ssh_host}:{TARGET_PORT}"
                if await check_target_health(target_url):
                    active_instance_id = candidate_id
                    active_target_url = target_url
                    logger.info(f"🎉 Instance {candidate_id} is now UP and HEALTHY at {target_url}!")
                    return target_url
            logger.info(f"Waiting for instance {candidate_id} to boot... ({int(time.time() - start_time)}s)")

        raise RuntimeError(f"Timeout waiting for instance {candidate_id} to become healthy.")

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(idle_watcher())

async def idle_watcher():
    """Background task to stop instances when idle timeout is exceeded"""
    global active_instance_id, active_target_url
    while True:
        await asyncio.sleep(60)
        idle_seconds = time.time() - last_activity_time
        if active_instance_id and idle_seconds > (IDLE_TIMEOUT_MINUTES * 60):
            logger.info(f"💤 Idle timeout of {IDLE_TIMEOUT_MINUTES}m exceeded. Stopping instance {active_instance_id} to save costs...")
            await stop_vast_instance(active_instance_id)
            active_instance_id = None
            active_target_url = None

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"])
async def reverse_proxy(request: Request, path: str):
    global last_activity_time
    last_activity_time = time.time()

    target_base = await ensure_active_instance()
    target_url = f"{target_base}/{path}"
    if request.url.query:
        target_url += f"?{request.url.query}"

    body = await request.body()
    headers = dict(request.headers)
    headers.pop("host", None)

    async with httpx.AsyncClient(timeout=300.0) as client:
        req = client.build_request(
            method=request.method,
            url=target_url,
            headers=headers,
            content=body
        )
        resp = await client.send(req, stream=True)
        return StreamingResponse(
            resp.aiter_raw(),
            status_code=resp.status_code,
            headers=dict(resp.headers),
            background=None
        )
