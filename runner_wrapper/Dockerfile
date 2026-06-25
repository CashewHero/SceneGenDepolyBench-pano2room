FROM pytorch/pytorch:2.1.2-cuda11.8-cudnn8-devel

WORKDIR /app/model_repo

# Build from the repository root:
# docker build -f runner_wrapper/Dockerfile -t scenegendeploybench-pano2room:0.1.0 .
COPY . /app/model_repo

# If the build context is runner_wrapper/ itself, normalize it
RUN if [ -f server.py ] && [ -f adapter.py ] && [ ! -f runner_wrapper/server.py ]; then \
      mkdir /tmp/runner_wrapper; \
      mv ./* /tmp/runner_wrapper/; \
      mv /tmp/runner_wrapper runner_wrapper; \
    fi

ENV PYTHONPATH=/app/model_repo:/app
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ffmpeg libgl1 libglib2.0-0 ninja-build && \
    rm -rf /var/lib/apt/lists/*

ARG TCNN_CUDA_ARCHITECTURES=75
ENV TCNN_CUDA_ARCHITECTURES=${TCNN_CUDA_ARCHITECTURES}
ARG TORCH_CUDA_ARCH_LIST=7.5
ENV TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}

ARG INSTALL_REQUIREMENTS=1
RUN if [ "$INSTALL_REQUIREMENTS" = "1" ] && [ -f requirements_git.txt ]; then \
      pip install --no-cache-dir -r requirements_git.txt; \
    fi
RUN if [ "$INSTALL_REQUIREMENTS" = "1" ] && [ -f requirements.txt ]; then \
      grep -vE '^(--extra-index-url|torch[[:space:]]*$|torchvision[[:space:]]*$|triton[[:space:]]*$|xformers[[:space:]]*$)' requirements.txt > /tmp/requirements.txt; \
      pip install --no-cache-dir --retries 2 --timeout 60 -r /tmp/requirements.txt; \
    fi

ARG INSTALL_EDITABLE=0
RUN if [ "$INSTALL_EDITABLE" = "1" ] && { [ -f pyproject.toml ] || [ -f setup.py ]; }; then \
      pip install --no-cache-dir -e .; \
    fi

EXPOSE 58090

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV RUNNER_PORT=58090
ENV RUNNER_NAME=pano2room
ENV RUNNER_TYPE=generator
ENV RUNNER_VERSION=0.1.0
ENV RUNNER_CONTRACT_VERSION=1
ENV RUNNER_IDLE_TIMEOUT_SECONDS=900
ENV RUNNER_ADAPTER=runner_wrapper.adapter:run_job
ENV PANO2ROOM_CHECKPOINT_DIR=/models/pano2room/checkpoints
ENV PANO2ROOM_LAMA_CONFIG_PATH=/models/pano2room/checkpoints/big-lama-config.yaml
ENV PANO2ROOM_LAMA_CKPT_PATH=/models/pano2room/checkpoints/big-lama.ckpt
ENV PANO2ROOM_OMNIDATA_DEPTH_CKPT_PATH=/models/pano2room/checkpoints/omnidata_dpt_depth_v2.ckpt
ENV PANO2ROOM_OMNIDATA_NORMAL_CKPT_PATH=/models/pano2room/checkpoints/omnidata_dpt_normal_v2.ckpt
ENV PANO2ROOM_AUTO_DOWNLOAD_WEIGHTS=1

CMD ["python", "-m", "runner_wrapper.server"]
