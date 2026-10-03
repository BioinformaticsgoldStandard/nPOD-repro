#!/bin/bash
set -euo pipefail

# Activate the py3 conda environment (contains JupyterLab + Python 3 stack).
# R notebooks use the separate 'r' kernel registered at image build time.
eval "$(micromamba shell hook -s bash)"
# conda activate.d scripts are not nounset-safe. bioconda's macs2 depends on
# r-base (MACS2 only writes <name>_model.r for the user to run with Rscript;
# it never calls R itself), which pulls compiler activation scripts into py3
# that read unset variables (e.g. ADDR2LINE).
set +u
micromamba activate py3
set -u

# Spawned by JupyterHub: the hub always sets JUPYTERHUB_API_TOKEN.
if [ -n "${JUPYTERHUB_API_TOKEN:-}" ]; then
    # Some spawners (e.g. JupyDo) run the container as root;
    # jupyterhub-singleuser refuses root without --allow-root.
    if [ "$(id -u)" -eq 0 ]; then
        set -- "$@" --allow-root
    fi
    exec "$@"
fi

# Standalone: drop the image's default CMD, keep any other args as extra
# JupyterLab flags.
if [ "${1:-}" = "jupyterhub-singleuser" ]; then
    shift
fi

exec jupyter lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --notebook-dir=/home/jovyan/work \
    "$@"
