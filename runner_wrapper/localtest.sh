#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

safe_name() {
  tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g'
}

repo_name="$(basename "${REPO_ROOT}" | safe_name)"

IMAGE="${RUNNER_IMAGE:-scenegendeploybench-pano2room:local}"
CONTAINER="${RUNNER_CONTAINER:-pano2room-runner-localtest}"
HOST_PORT="${RUNNER_HOST_PORT:-58090}"
DATA_DIR="${RUNNER_DATA_DIR:-${REPO_ROOT}/data}"
RUNNER_NAME="${RUNNER_NAME:-pano2room}"
RUNNER_TYPE="${RUNNER_TYPE:-generator}"
RUNNER_VERSION="${RUNNER_VERSION:-0.1.0}"
RUNNER_ADAPTER="${RUNNER_ADAPTER:-runner_wrapper.adapter:run_job}"
RUNNER_WEIGHTS_DIR="${RUNNER_WEIGHTS_DIR:-}"
REQUEST_FILE="${RUNNER_REQUEST_FILE:-${SCRIPT_DIR}/examples/${RUNNER_TYPE}_job_request.json}"

usage() {
  cat <<EOF
Usage:
  runner_wrapper/localtest.sh build
  runner_wrapper/localtest.sh run
  runner_wrapper/localtest.sh smoke
  runner_wrapper/localtest.sh status
  runner_wrapper/localtest.sh logs
  runner_wrapper/localtest.sh down

Environment:
  RUNNER_IMAGE=${IMAGE}
  RUNNER_CONTAINER=${CONTAINER}
  RUNNER_HOST_PORT=${HOST_PORT}
  RUNNER_TYPE=${RUNNER_TYPE}
  RUNNER_NAME=${RUNNER_NAME}
  RUNNER_VERSION=${RUNNER_VERSION}
  RUNNER_ADAPTER=${RUNNER_ADAPTER}
  RUNNER_REQUEST_FILE=${REQUEST_FILE}
  RUNNER_DATA_DIR=${DATA_DIR}
  RUNNER_WEIGHTS_DIR=${RUNNER_WEIGHTS_DIR}

Set RUNNER_WEIGHTS_DIR to the host directory containing the mounted
Pano2Room weights before running a full smoke test.
EOF
}

require_tools() {
  command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
}

build_image() {
  docker build \
    -f "${SCRIPT_DIR}/Dockerfile" \
    -t "${IMAGE}" \
    "${REPO_ROOT}"
}

prepare_data() {
  mkdir -p \
    "${DATA_DIR}/datasets/smoke" \
    "${DATA_DIR}/output/pano2room@0.1.0/smoke-dataset/sample-1"

  if [[ ! -f "${DATA_DIR}/datasets/smoke/image.png" ]]; then
    if [[ -f "${REPO_ROOT}/input/input_panorama.png" ]]; then
      cp "${REPO_ROOT}/input/input_panorama.png" "${DATA_DIR}/datasets/smoke/image.png"
    elif [[ -f "${REPO_ROOT}/demo/input_panorama.png" ]]; then
      cp "${REPO_ROOT}/demo/input_panorama.png" "${DATA_DIR}/datasets/smoke/image.png"
    else
      printf 'smoke input\n' > "${DATA_DIR}/datasets/smoke/image.png"
    fi
  fi
}

run_container() {
  prepare_data
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true

  local env_args=(
    -e "RUNNER_PORT=58090"
    -e "RUNNER_NAME=${RUNNER_NAME}"
    -e "RUNNER_TYPE=${RUNNER_TYPE}"
    -e "RUNNER_VERSION=${RUNNER_VERSION}"
    -e "RUNNER_ADAPTER=${RUNNER_ADAPTER}"
  )

  if [[ -n "${RUNNER_LOG_LEVEL:-}" ]]; then
    env_args+=(-e "RUNNER_LOG_LEVEL=${RUNNER_LOG_LEVEL}")
  fi
  for env_name in \
    PANO2ROOM_CHECKPOINT_DIR \
    PANO2ROOM_LAMA_CONFIG_PATH \
    PANO2ROOM_LAMA_CKPT_PATH \
    PANO2ROOM_OMNIDATA_DEPTH_CKPT_PATH \
    PANO2ROOM_OMNIDATA_NORMAL_CKPT_PATH \
    PANO2ROOM_SD_MODEL_PATH \
    PANO2ROOM_AUTO_DOWNLOAD_WEIGHTS \
    PANO2ROOM_SDFT_WEIGHTS_DIR \
    PANO2ROOM_CAMERA_TRAJECTORY_DIR; do
    if [[ -n "${!env_name:-}" ]]; then
      env_args+=(-e "${env_name}=${!env_name}")
    fi
  done

  local volume_args=(-v "${DATA_DIR}:/data")
  if [[ -n "${RUNNER_WEIGHTS_DIR}" ]]; then
    volume_args+=(-v "${RUNNER_WEIGHTS_DIR}:/models/pano2room/checkpoints:ro")
  fi

  docker run -d \
    --name "${CONTAINER}" \
    -p "${HOST_PORT}:58090" \
    "${env_args[@]}" \
    "${volume_args[@]}" \
    "${IMAGE}" >/dev/null

  wait_ready
  echo "runner available at http://127.0.0.1:${HOST_PORT}"
}

wait_ready() {
  local attempt
  for attempt in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${HOST_PORT}/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "runner did not become ready" >&2
  docker logs "${CONTAINER}" >&2 || true
  exit 1
}

submit_request() {
  [[ -f "${REQUEST_FILE}" ]] || { echo "missing request file: ${REQUEST_FILE}" >&2; exit 1; }
  curl -fsS \
    -X POST "http://127.0.0.1:${HOST_PORT}/run-job" \
    -H 'Content-Type: application/json' \
    --data @"${REQUEST_FILE}"
  echo
}

status_json() {
  curl -fsS "http://127.0.0.1:${HOST_PORT}/status"
}

status_field() {
  python3 -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1"
}

poll_terminal() {
  local attempt state
  for attempt in $(seq 1 3600); do
    state="$(status_json | status_field state)"
    case "${state}" in
      finished)
        status_json
        echo
        return 0
        ;;
      failed)
        status_json
        echo
        return 1
        ;;
    esac
    sleep 1
  done

  echo "runner job did not finish before local poll timeout" >&2
  return 1
}

smoke() {
  build_image
  run_container
  submit_request
  poll_terminal
}

main() {
  require_tools
  case "${1:-smoke}" in
    build)
      build_image
      ;;
    run)
      build_image
      run_container
      ;;
    smoke)
      smoke
      ;;
    status)
      status_json
      echo
      ;;
    logs)
      docker logs -f "${CONTAINER}"
      ;;
    down)
      docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "unknown command: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
