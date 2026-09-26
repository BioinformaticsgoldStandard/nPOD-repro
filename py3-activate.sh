# Activate the py3 conda environment in every interactive/login shell,
# so CLI scripts (e.g. snATAC_pipeline_10X.py) work from `docker exec -it <c> bash`
# as well as from the JupyterLab terminal.
# Installed as /etc/profile.d/npod-py3.sh (login shells) and sourced from
# /etc/bash.bashrc (interactive non-login shells, which skip profile.d).
if [ -n "${BASH_VERSION:-}" ] && [ -x /usr/local/bin/micromamba ]; then
    eval "$(/usr/local/bin/micromamba shell hook -s bash)"
    if [ "${CONDA_PREFIX:-}" != "/opt/conda/envs/py3" ]; then
        micromamba activate py3
    fi
fi
