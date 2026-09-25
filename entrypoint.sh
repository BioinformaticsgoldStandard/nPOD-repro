#!/bin/bash
set -euo pipefail

# Activate the py3 conda environment (contains JupyterLab + Python 3 stack).
# R notebooks use the separate 'r' kernel registered at image build time.
eval "$(micromamba shell hook -s bash)"
micromamba activate py3

exec jupyter lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --notebook-dir=/home/jovyan/work \
    "$@"
