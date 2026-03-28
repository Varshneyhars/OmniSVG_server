# OmniSVG_server

[![Runpod](https://api.runpod.io/badge/yaoqih/OmniSVG_server)](https://console.runpod.io/hub/yaoqih/OmniSVG_server)

Serverless SVG generation from text or images, powered by Qwen-VL and a custom sketch decoder. This repo includes a Runpod Serverless handler and Hub configuration for one-click deployment.

## Components

- Serverless handler: [`handler.handler()`](handler.py:34) — wraps `service.run_generation` for Runpod
- Core service + inference helpers (`service.py`):
  - `ensure_model_loaded()` / `load_models()` — lazy multi-model (4B / 8B) init
  - `run_generation()` — shared entry for `/predict` and handler, returns multi-candidate payloads
  - `prepare_inputs`, `generate_candidates`, `b64_to_pil`/`pil_to_b64` utilities
- Minimal Qwen vision utility: [`qwen_vl_utils.process_vision_info()`](qwen_vl_utils.py:4)
- Client tooling: [`gradio_runpod.py`](gradio_runpod.py) + [`runpod_client.py`](runpod_client.py)
- Runpod Hub configuration: [.runpod/hub.json](.runpod/hub.json)
- Runpod Tests configuration: [.runpod/tests.json](.runpod/tests.json)
- Container build: [Dockerfile](Dockerfile)

## Runpod Serverless

Handler entry: [`handler.py`](handler.py)

Event input schema (JSON in `event.input`):
```json
{
  "task_type": "text-to-svg | image-to-svg",
  "text": "required for text-to-svg",
  "image_base64": "required for image-to-svg (base64 PNG/JPEG/WEBP, no data: prefix)",
  "model_size": "optional, defaults to config.default_model_size (4B | 8B)",
  "task_subtype": "optional, overrides icon/illustration auto-detect",
  "num_candidates": "optional, 1 ~ generation.max_num_candidates",
  "max_length": "optional, 256 ~ 2048",
  "temperature": "optional, float",
  "top_p": "optional, float",
  "top_k": "optional, int",
  "repetition_penalty": "optional, float",
  "replace_background": "optional, bool (image-to-svg)",
  "return_png": true
}
```

Response:
```json
{
  "status": "ok | no_valid_candidates | error",
  "task_type": "text-to-svg",
  "model_size": "4B",
  "subtype": "icon",
  "parameters": {
    "temperature": 0.4,
    "top_p": 0.9,
    "top_k": 50,
    "repetition_penalty": 1.05,
    "max_length": 512,
    "num_candidates": 1
  },
  "candidates": [
    {
      "index": 1,
      "path_count": 42,
      "svg": "<svg ...>...</svg>",
      "png_base64": "optional PNG preview"
    }
  ],
  "primary_svg": "<svg ...>",
  "primary_png_base64": "optional PNG preview",
  "processed_input_png_base64": "image preview (image-to-svg)",
  "elapsed_ms": 1234
}
```

Dummy mode:
- For Hub validations (no private weights), the handler supports `ENABLE_DUMMY=true` to return a valid, simple SVG without loading heavy models.
- For production, set `ENABLE_DUMMY=false` to run real inference with your weights and model.

## Environment Variables

Handled by `service.ensure_model_loaded()` / `handler.py`:

- `CONFIG_PATH` — config YAML path (default `/workspace/config.yaml`)
- `WEIGHT_PATH` — fallback OmniSVG weights path or HF repo (default `OmniSVG/OmniSVG`)
- `WEIGHT_PATH_4B`, `WEIGHT_PATH_8B` — optional overrides for each model (default `OmniSVG/OmniSVG1.1_4B` etc.)
- `QWEN_LOCAL_DIR` — fallback Qwen model path / repo id (default `Qwen/Qwen2.5-VL-3B-Instruct`)
- `QWEN_MODEL_4B`, `QWEN_MODEL_8B` — optional overrides for each backbone (defaults `Qwen/Qwen2.5-VL-3B-Instruct` and `Qwen/Qwen2.5-VL-7B-Instruct`)
- `SVG_TOKENIZER_CONFIG` — tokenizer config path (default `/workspace/config.yaml`)
- `ENABLE_DUMMY` — return placeholder SVGs without loading weights (default `true` in Hub; set `false` for production)

Defaults are encoded in [.runpod/hub.json](.runpod/hub.json) and surfaced as editable env fields.

## Tests (Runpod Hub)

Hub validations use [.runpod/tests.json](.runpod/tests.json):
- Text + image smoke tests send the latest parameter set (model size, sampling knobs, background toggle).
- `ENABLE_DUMMY=true` is injected so tests succeed without your private weights.
- GPU target: `A40` + CUDA 12.x (adjust as needed).

## Container

The [Dockerfile](Dockerfile) includes:
- Python 3.10 slim base
- System deps for CairoSVG (`libcairo2`, `libpango`, fonts)
- PyTorch CUDA 12.1 wheels + torchvision
- Python deps: `runpod`, `fastapi`, `uvicorn`, `transformers`, `Pillow`, `PyYAML`, `cairosvg`

Default CMD launches the serverless handler:
```
CMD ["python", "-u", "handler.py"]
```

## Local (optional)

You can still run the FastAPI service locally for debugging:
- Entry: [`service.py`](service.py)
- Run: `python service.py` (serves `/ping` and `/predict`)
- Note: Local environment must have matching CUDA/PyTorch and system libs for CairoSVG.

## Deploy Steps

1) Ensure your model and weights are accessible in Runpod via a mounted volume or public HF repo.
2) Configure env vars in Hub (or use defaults in [.runpod/hub.json](.runpod/hub.json)).
3) Create a GitHub release to trigger Hub ingestion.
4) In production, disable dummy mode: `ENABLE_DUMMY=false`.

## License

No license specified in this repository.
## Gradio Client (Runpod Backend)

This client provides a lightweight Gradio frontend that calls the Runpod Serverless queue endpoint directly via HTTP (requests) for inference. No local model loading is required, and it does not invoke the local service in this repo (i.e., `service.load_models_once` is never triggered).

- Entry point: `gradio_runpod.py`
- Runpod HTTP client: `runpod_client.py`, core methods:
  - Synchronous call: [`runpod_client.runsync()`](runpod_client.py:87)
  - Async polling: [`runpod_client.run_async()`](runpod_client.py:121)

### Environment Variables

Configure the following environment variables before launching (do not hardcode secrets in code):

- `RUNPOD_API_KEY` — Your Runpod API Key
- `ENDPOINT_ID` — Runpod queue endpoint ID

Linux / macOS:
```bash
export RUNPOD_API_KEY="rp_xxx_your_api_key"
export ENDPOINT_ID="xxxxxxxxxxxxxxxx"
```

Windows PowerShell:
```powershell
$env:RUNPOD_API_KEY="rp_xxx_your_api_key"
$env:ENDPOINT_ID="xxxxxxxxxxxxxxxx"
```

### Installation & Launch

- Install dependencies:
  ```bash
  pip install -r requirements_client.txt
  # If gradio is not installed locally:
  # pip install gradio
  ```
- Start the Gradio client:
  ```bash
  python gradio_runpod.py --listen 0.0.0.0 --port 7860
  # Optional flags:
  #   --share   Enable Gradio public sharing link
  #   --debug   Show detailed errors (Gradio show_error)
  ```

Once started, open your browser to the displayed address (e.g., `http://127.0.0.1:7860`).

### UI & Usage

The client includes two tabs matching the server-side interface, exposing all key parameters:

1) **Text-to-SVG**
   - Input: prompt text (gr.Textbox)
   - Model selection: 4B/8B dropdown
   - Sampling settings: num_candidates, max_length, temperature, top_p, top_k, repetition_penalty (collapsed under advanced settings)
   - Behavior: calls [`runpod_client.runsync()`](runpod_client.py:87), can also be extended to `run_async`

2) **Image-to-SVG**
   - Input: image (gr.Image, type="pil", image_mode="RGBA")
   - Settings: same as Text tab plus a `replace_background` toggle
   - Behavior: encodes image to base64 and calls the Runpod endpoint

Output components include:
- SVG grid (HTML gallery)
- SVG code (gr.Code)
- PNG preview (processed input + primary candidate)
- Run status text (model / elapsed / message)

### Request & Response Structure (Client Side)

- Synchronous mode (runsync):
  - POST `https://api.runpod.ai/v2/{ENDPOINT_ID}/runsync?wait=120000`
  - Headers:
    - `accept: application/json`
    - `authorization: RUNPOD_API_KEY` (value from environment variable)
    - `content-type: application/json`
  - Body (example):
    ```json
    {
      "input": {
        "task_type": "text-to-svg",
        "text": "...",
        "model_size": "4B",
        "num_candidates": 1,
        "max_length": 512,
        "temperature": 0.4,
        "top_p": 0.9,
        "top_k": 50,
        "repetition_penalty": 1.05,
        "return_png": true
      }
    }
    ```
  - Response supports two formats: top-level business fields or wrapped in `output`; the client normalizes both to
    `{'status': str|null, 'svg': str|null, 'png_base64': str|null, 'candidates': list|null, 'parameters': dict|null, 'elapsed_ms': int|null, 'delayTime': int|null, 'executionTime': int|null, ...}`

- Async mode (queue polling):
  - POST submit: `https://api.runpod.ai/v2/{ENDPOINT_ID}/run`
  - Poll GET: `https://api.runpod.ai/v2/{ENDPOINT_ID}/status/{job_id}`
  - Polling strategy:
    - Base interval: 2s, dynamically adjusted based on `delayTime`
    - Total timeout: 180s by default
    - On 429: exponential backoff (base 1s, doubling up to 16s max, plus 0–500ms jitter)
    - On 401/404/500: fail immediately and stop

### Error Handling

- The client merges HTTP status codes with the `error` field in responses into user-readable error messages.
- When environment variables are missing (`RUNPOD_API_KEY` or `ENDPOINT_ID`), a prominent error is displayed at the top of the UI and requests are blocked.
- The Gradio UI shows simplified error messages; raw response fragments are available in logs for debugging.
