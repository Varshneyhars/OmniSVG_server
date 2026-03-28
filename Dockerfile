# syntax=docker/dockerfile:1
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TOKENIZERS_PARALLELISM=false \
    HF_HOME=/workspace/hf_cache

WORKDIR /workspace

# System deps for Pillow, CairoSVG (cairo + pango + fonts)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libcairo2 \
    libcairo2-dev \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libfontconfig1 \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Install deps first (cached unless requirements.txt changes)
COPY requirements.txt /workspace/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Pre-download all models at build time.
# These layers are ordered BEFORE "COPY . /workspace" so source code changes
# don't invalidate the cache — models won't re-download on every build.

# Qwen 3B (4B pipeline) — tokenizer + processor + model weights
RUN python -c "\
from transformers import AutoTokenizer, AutoProcessor, Qwen2_5_VLForConditionalGeneration; \
AutoTokenizer.from_pretrained('Qwen/Qwen2.5-VL-3B-Instruct', trust_remote_code=True); \
AutoProcessor.from_pretrained('Qwen/Qwen2.5-VL-3B-Instruct', trust_remote_code=True); \
Qwen2_5_VLForConditionalGeneration.from_pretrained('Qwen/Qwen2.5-VL-3B-Instruct', torch_dtype='auto', device_map='cpu')"

# Qwen 7B (8B pipeline) — tokenizer + processor + model weights
RUN python -c "\
from transformers import AutoTokenizer, AutoProcessor, Qwen2_5_VLForConditionalGeneration; \
AutoTokenizer.from_pretrained('Qwen/Qwen2.5-VL-7B-Instruct', trust_remote_code=True); \
AutoProcessor.from_pretrained('Qwen/Qwen2.5-VL-7B-Instruct', trust_remote_code=True); \
Qwen2_5_VLForConditionalGeneration.from_pretrained('Qwen/Qwen2.5-VL-7B-Instruct', torch_dtype='auto', device_map='cpu')"

# OmniSVG weight files
RUN python -c "\
from huggingface_hub import hf_hub_download; \
hf_hub_download(repo_id='OmniSVG/OmniSVG1.1_4B', filename='pytorch_model.bin'); \
hf_hub_download(repo_id='OmniSVG/OmniSVG1.1_8B', filename='pytorch_model.bin')"

# Now copy source code — changes here won't re-trigger model downloads above
COPY . /workspace

# Default ENV — use HF repo IDs; models are already in HF_HOME cache
ENV WEIGHT_PATH=OmniSVG/OmniSVG \
    WEIGHT_PATH_4B=OmniSVG/OmniSVG1.1_4B \
    WEIGHT_PATH_8B=OmniSVG/OmniSVG1.1_8B \
    CONFIG_PATH=/workspace/config.yaml \
    QWEN_LOCAL_DIR=Qwen/Qwen2.5-VL-3B-Instruct \
    QWEN_MODEL_4B=Qwen/Qwen2.5-VL-3B-Instruct \
    QWEN_MODEL_8B=Qwen/Qwen2.5-VL-7B-Instruct \
    SVG_TOKENIZER_CONFIG=/workspace/config.yaml \
    ENABLE_DUMMY=true

# Serverless entrypoint
CMD ["python", "-u", "handler.py"]
