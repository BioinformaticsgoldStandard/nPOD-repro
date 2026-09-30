# nPOD-repro — reproducible snATAC-seq analysis environment
#
# Three isolated environments in one image:
#   py3  — Python 3.7 stack (scanpy, pysam, etc.) for snATAC_01/02 and pipeline scripts
#   py2  — Python 2.7 stack, solely for clean_barcode_multiplets_1.1.py
#   r    — R 4.1 + Seurat 4 / Signac 1 stack for snATAC_03/04/05
#
# CellRanger-ATAC is NOT baked in (10x Genomics licence restriction).
# Mount the binary at runtime — see docker-compose.yml.
#
# The peak-call-pipeline (Gaulton-Lab/peak-call-pipeline) runs in its own
# standalone conda environment built from its call_peaks_environment.yml.
# It is NOT included here; see README.md "Peak-call-pipeline environment" section.

FROM ubuntu:22.04

LABEL maintainer="Sourdv"
LABEL description="nPOD snATAC-seq reproduction environment"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget curl ca-certificates gnupg \
        build-essential gfortran \
        libcurl4-openssl-dev libssl-dev libxml2-dev \
        libbz2-dev liblzma-dev libncurses5-dev zlib1g-dev \
        libreadline-dev libpcre2-dev liblapack-dev libblas-dev \
        libharfbuzz-dev libfribidi-dev \
        libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
        libhdf5-dev \
        git parallel pigz tabix python-is-python3 \
        python3 python3-pip python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# samtools 1.17 (not pinned in original; using a recent stable release)
# ---------------------------------------------------------------------------
ARG SAMTOOLS_VERSION=1.17
RUN wget -qL https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 \
    && tar xjf samtools-${SAMTOOLS_VERSION}.tar.bz2 \
    && cd samtools-${SAMTOOLS_VERSION} && ./configure --prefix=/usr/local && make -j4 && make install \
    && cd / && rm -rf samtools-${SAMTOOLS_VERSION} samtools-${SAMTOOLS_VERSION}.tar.bz2

# bedtools 2.30.0 (confirmed from call_peaks_environment.yml)
ARG BEDTOOLS_VERSION=2.30.0
RUN wget -qL https://github.com/arq5x/bedtools2/releases/download/v${BEDTOOLS_VERSION}/bedtools-${BEDTOOLS_VERSION}.tar.gz \
    && tar xzf bedtools-${BEDTOOLS_VERSION}.tar.gz \
    && cd bedtools2 && make -j4 && cp bin/* /usr/local/bin/ \
    && cd / && rm -rf bedtools2 bedtools-${BEDTOOLS_VERSION}.tar.gz

# UCSC bedGraphToBigWig build 377 (confirmed from call_peaks_environment.yml)
RUN wget -q https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/bedGraphToBigWig \
    && chmod +x bedGraphToBigWig && mv bedGraphToBigWig /usr/local/bin/

# ---------------------------------------------------------------------------
# micromamba — used to build all three conda environments
# ---------------------------------------------------------------------------
ARG MICROMAMBA_VERSION=1.5.3
RUN wget -qO- https://micro.mamba.pm/api/micromamba/linux-64/${MICROMAMBA_VERSION} \
    | tar -xvj -C /usr/local bin/micromamba

ENV MAMBA_ROOT_PREFIX=/opt/conda

# ---------------------------------------------------------------------------
# Python 3.7 environment  (py3 — snATAC_01, snATAC_02, pipeline scripts)
# Versions confirmed from call_peaks_environment.yml (Python stack only).
# JupyterLab is included here to serve all notebooks; R uses a separately
# registered kernel (see r env below).
# ---------------------------------------------------------------------------
RUN /usr/local/bin/micromamba create -n py3 -c conda-forge -c bioconda -y \
        python=3.7.10 \
        scanpy=1.8.1 \
        anndata=0.7.6 \
        numpy=1.20.3 \
        pandas=1.3.3 \
        scipy=1.6.3 \
        matplotlib=3.4.3 \
        seaborn=0.11.2 \
        statsmodels=0.13.0 \
        scikit-learn=1.0 \
        pysam=0.17.0 \
        umap-learn=0.5.1 \
        leidenalg=0.8.7 \
        macs2=2.2.7.1 \
        jupyterlab \
    && /usr/local/bin/micromamba clean -afy

# ---------------------------------------------------------------------------
# Python 2.7 environment  (py2 — clean_barcode_multiplets_1.1.py ONLY)
# pysam 0.15.4, pandas 0.24.2, numpy 1.16.6: last releases with Py2 support.
# ---------------------------------------------------------------------------
RUN /usr/local/bin/micromamba create -n py2 -c conda-forge -c bioconda -y \
        python=2.7.18 \
        pysam=0.15.4 \
        pandas=0.24.2 \
        numpy=1.16.6 \
    && /usr/local/bin/micromamba clean -afy

# Convenience wrapper so the script can be called as `python2-repro <script>`
RUN printf '#!/bin/bash\n/opt/conda/envs/py2/bin/python "$@"\n' > /usr/local/bin/python2-repro \
    && chmod +x /usr/local/bin/python2-repro

# ---------------------------------------------------------------------------
# R 4.1 environment  (r — snATAC_03/04/05)
# R 4.1 is the earliest release compatible with Seurat 4.x + Bioc 3.13–3.14.
# Seurat, Signac, and harmony are installed from CRAN/GitHub because conda
# packages lag behind; harmony <=1.2 is needed for the HarmonyMatrix() API.
# IRkernel is included so R notebooks are selectable in JupyterLab.
#
# Matrix is pinned to 1.5-4: it predates the Matrix >= 1.6-2 C-level ABI change
# that breaks SeuratObject 4.x / Seurat 4.x. conda-forge names it "1.5_4"
# (underscore; verified build r41he1ae0d6_0, requires r-base >=4.1,<4.2).
# ---------------------------------------------------------------------------
ARG R_VERSION=4.1.3
RUN /usr/local/bin/micromamba create -n r -c conda-forge -c bioconda -y \
        r-base=${R_VERSION} \
        r-hdf5r \
        r-data.table \
        r-dplyr \
        r-ggplot2 \
        r-matrix=1.5_4 \
        r-tibble \
        r-ggpubr \
        r-pheatmap \
        r-gplots \
        r-cowplot \
        r-tictoc \
        r-future \
        r-sctransform \
        bioconductor-scater \
        bioconductor-biocparallel \
        bioconductor-genomeinfodb \
        bioconductor-ensdb.hsapiens.v86 \
        bioconductor-iranges \
        bioconductor-s4vectors \
        bioconductor-biobase \
        r-irkernel \
    && /usr/local/bin/micromamba clean -afy

# SeuratObject is pinned to 4.1.4 before Seurat so Seurat 4.3.0 doesn't pull
# SeuratObject 5.x (which requires Matrix >= 1.6-4). upgrade='never' stops
# remotes from replacing the pinned Matrix while resolving dependencies.
# stopifnot() fails the build if Matrix drifted anyway; package_version
# normalises "1.5-4" to "1.5.4", so the dotted comparison is correct.
RUN /opt/conda/envs/r/bin/Rscript -e " \
    install.packages('remotes', repos='https://cloud.r-project.org/'); \
    remotes::install_version('SeuratObject', version='4.1.4', repos='https://cloud.r-project.org/', upgrade='never'); \
    remotes::install_version('Seurat',       version='4.3.0', repos='https://cloud.r-project.org/', upgrade='never'); \
    remotes::install_version('harmony',      version='1.0',   repos='https://cloud.r-project.org/', upgrade='never'); \
    remotes::install_github('timoast/signac', ref='v1.11.0', upgrade='never'); \
    stopifnot(packageVersion('Matrix') == '1.5.4'); \
    "

# Register the R kernel for JupyterLab.
# IRkernel::installspec() shells out to `jupyter kernelspec install` internally.
# /opt/conda/envs/py3/bin is not on PATH during RUN layers, so we pass the full
# path explicitly via the jupyter= parameter (available since IRkernel 1.1).
RUN /opt/conda/envs/r/bin/Rscript -e \
    "IRkernel::installspec(user=FALSE, name='r4', displayname='R 4.1 (nPOD)', jupyter='/opt/conda/envs/py3/bin/jupyter')"

# ---------------------------------------------------------------------------
# JupyterLab (served from the py3 env)
# ---------------------------------------------------------------------------
EXPOSE 8888

# Non-root user. NB_UID defaults to 1000; override at build time
# (docker compose build --build-arg NB_UID=$(id -u)) to match the host user
# that owns the bind-mounted data directories. Ownership is set below.
ARG NB_UID=1000
RUN useradd --create-home --shell /bin/bash --uid ${NB_UID} jovyan

WORKDIR /home/jovyan/work

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Activate py3 in every shell, not only the JupyterLab process.
# profile.d covers login shells; bash.bashrc covers interactive non-login
# shells such as `docker exec -it <container> bash`, which never read profile.d.
# ENV PATH covers commands run without a shell (`docker exec <c> python ...`).
COPY py3-activate.sh /etc/profile.d/npod-py3.sh
RUN echo '[ -f /etc/profile.d/npod-py3.sh ] && . /etc/profile.d/npod-py3.sh' >> /etc/bash.bashrc
# Intentionally redundant with `micromamba activate py3`: in activated shells
# py3/bin appears twice in PATH, which is harmless. This line is only a safety
# net for commands run without a shell (`docker exec <container> python ...`).
ENV PATH=/opt/conda/envs/py3/bin:$PATH

RUN mkdir -p /data /reference_files /cellranger_outputs \
    && chown -R jovyan:jovyan /home/jovyan /data /reference_files /cellranger_outputs

USER jovyan

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
