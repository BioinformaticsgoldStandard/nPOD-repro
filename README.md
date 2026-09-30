# nPOD-repro — snATAC-seq reproduction

Reproduction of the snATAC-seq processing and clustering pipeline from
Melton et al. (2025), *Science Advances*, eady0080,
"Multi-modal single-cell profiling of the human pancreas reveals
epigenetic and transcriptional regulation in type 1 diabetes."

Raw data: Bioproject accession [PRJNA1141467](https://www.ncbi.nlm.nih.gov/bioproject/PRJNA1141467)

**Scope of this reproduction:** ATAC-seq branch only — `snATAC_01` through
`snATAC_05`, the AMULET doublet step, `scripts/snATAC_pipeline_10X.py`,
`scripts/clean_barcode_multiplets_1.1.py`, and the external
peak-call-pipeline.  snRNA-seq and all downstream analysis notebooks
(`downstream_analysis/`) are out of scope, with the one exception that
the snRNA pipeline must be run to produce `rna_obj.rds` as an input to
the label-transfer step (snATAC_05).

---

## Requirements

| Resource | Minimum | Recommended |
|---|---|---|
| RAM | 64 GB | 128 GB |
| Disk | 500 GB | 1 TB |
| CPU | 16 cores | 32 cores |
| Docker | ≥ 20.10 | latest |
| docker compose plugin | ≥ 2.0 | latest |

CellRanger-ATAC is not bundled in the image (10x Genomics licence restriction).
Download it from [10x Genomics](https://www.10xgenomics.com/support/software/cell-ranger-atac)
and mount it at runtime (see "CellRanger-ATAC" below).

---

## Quick start

```bash
git clone https://github.com/BioinformaticsgoldStandard/nPOD-repro.git
cd nPOD-repro
git checkout repro          # all portability fixes are on this branch

# Edit these two lines in docker-compose.yml to point at your data:
#   NPOD_DATA_HOST   — directory containing pipeline outputs, QC files, etc.
#   NPOD_CELLRANGER_HOST — directory containing per-sample CellRanger outputs

docker compose build
docker compose up -d
```

Open JupyterLab at <http://localhost:8888>.  The repository is mounted at
`/home/jovyan/work`.

---

## Container architecture

Three isolated environments are built into the image:

| Kernel name | Activated by | Used for |
|---|---|---|
| `py3` (Python 3.7) | JupyterLab default | `snATAC_01`, `snATAC_02`, pipeline scripts |
| `r4` (R 4.1) | R kernel in JupyterLab | `snATAC_03`, `snATAC_04`, `snATAC_05` |
| `py2` (Python 2.7) | `/usr/local/bin/python2-repro` in terminal | `clean_barcode_multiplets_1.1.py` **only** |

> **py2 implementation note:** Python 2.7.18 is installed from the
> [deadsnakes PPA](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa)
> rather than a conda environment. `pysam`, `pandas`, and `numpy` are
> installed via pip. See "Deviations" for the reason.

Select the correct kernel before running each notebook.

### Peak-call-pipeline environment (standalone — not in this image)

The `Gaulton-Lab/peak-call-pipeline` runs in its own conda environment
built from `call_peaks_environment.yml` inside that repository.  Build it
separately on a host with conda/micromamba:

```bash
git clone https://github.com/Gaulton-Lab/peak-call-pipeline
cd peak-call-pipeline
# Remove or change the hardcoded prefix: line before creating the environment
sed -i '/^prefix:/d' call_peaks_environment.yml
conda env create -f call_peaks_environment.yml
conda activate call_peaks
```

Note: `mergePeaks.sh` and `merge_tagAligns.R` contain hardcoded NFS paths
and must be edited before use (the pipeline README flags this explicitly).

---

## CellRanger-ATAC

CellRanger-ATAC is not included in the image.  Download v2.2.0 from
10x Genomics and either add it to your `PATH` on the host before running
`docker compose`, or mount it inside the container by adding a volume to
`docker-compose.yml`:

```yaml
- /path/to/cellranger-atac-2.2.0:/opt/cellranger-atac:ro
```

Then prepend `/opt/cellranger-atac` to `PATH` in the compose `environment`
block.

---

## Execution order

> **Warning:** the execution order documented by the original authors in
> `Data_proccessing/data_processing.md` (03 → 04 → 05) is **incorrect**.
> The actual required order, determined by tracing file inputs and outputs,
> is given below.  Both affected notebooks contain an execution-order warning
> cell at the top.

### Prerequisites (run once, outside notebooks)

```bash
# 1. CellRanger-ATAC per sample
cellranger-atac count --id ${SAMPLE} \
    --fastqs /path/to/raw_data \
    --sample ${SAMPLE} \
    --reference /path/to/refdata-cellranger-arc-GRCh38-2024-A \
    --localcores 24 --disable-ui

# 2. Window-based matrix + QC (Python 3 env)
python scripts/snATAC_pipeline_10X.py \
    -b cellranger_outputs/${SAMPLE}/outs/atac_possorted_bam.bam \
    -o snatac_pipeline_output/${SAMPLE} -n ${SAMPLE} -t 24 -m 2 \
    --minimum-reads 1000 \
    --chrom-sizes /reference_files/hg38.chrom.sizes \
    --blacklist-file /reference_files/hg38-blacklist.v3.bed \
    --promoter-file /reference_files/gencode.hg38.v19.2kb_autosomal_prom_uniq.bed

# 3. Barcode multiplet removal (Python 2 env — isolated)
python2-repro scripts/clean_barcode_multiplets_1.1.py \
    cellranger_outputs/${SAMPLE}/outs --prefix ${SAMPLE}

# 4. AMULET doublet detection (run in terminal after snATAC_02 prepares inputs)
AMULET.sh --forcesorted --bambc CB --bcidx 0 --cellidx 8 --iscellidx 9 \
    cellranger_outputs/${SAMPLE}/outs/possorted_bam.bam \
    /data/singlecell_files/${SAMPLE}_singlecell.csv \
    /path/to/amulet/human_autosomes.txt \
    /path/to/amulet/RepeatFilterFiles/blacklist_repeats_segdups_rmsk_hg38.bed \
    /data/amulet/${SAMPLE}
```

### Notebooks (in order)

| Step | Notebook | Kernel | Notes |
|------|----------|--------|-------|
| 1 | `Data_proccessing/snATAC_01_indSample_processing.ipynb` | Python 3.7 | Per-sample QC filtering; run once per sample |
| 2 | `Data_proccessing/snATAC_02_AMULET_singlecellFile_singlomeOnly.ipynb` | Python 3.7 | Prepare `singlecell.csv` for AMULET; then run AMULET in terminal |
| 3 | `Data_proccessing/snATAC_03_mergeATACobj.ipynb` | R 4.1 | Merge all samples; initial clustering |
| 4 | `Data_proccessing/snATAC_05_labelTransfer_github.ipynb` (**cells 1–11**) | R 4.1 | Label transfer — **run before snATAC_04** |
| 5 | `Data_proccessing/snATAC_04_manualDoubletRemoval_PromAccess.ipynb` | R 4.1 | Manual doublet removal via promoter accessibility |
| 6 | `Data_proccessing/snATAC_05_labelTransfer_github.ipynb` (**final filter cells**) | R 4.1 | Acinar-sum filtering pass after snATAC_04 |

### Peak calling (between steps 3 and 4)

After snATAC_03 produces cluster labels, run the peak-call-pipeline in the
standalone conda environment.  See the pipeline README for the full 10-step
procedure.  The merged fragment file required by snATAC_03 is produced by:

```bash
for SAMPLE in ${SAMPLES[@]}; do
    zcat /data/cellranger_outputs/${SAMPLE}_fragments.tsv.gz \
    | awk -v S=$SAMPLE 'BEGIN{FS=OFS="\t"}{print $1,$2,$3,S"_"$4,$5}'
done | sort -k1,1 -k2,2n -S 64G | bgzip -c -@ 16 > /data/merged.atac_fragments.tsv.gz
tabix -p bed /data/merged.atac_fragments.tsv.gz
```

---

## Version table

### Python 3 stack

| Component | Version | Source |
|---|---|---|
| Python | 3.7.10 | confirmed — `call_peaks_environment.yml` |
| scanpy | 1.8.1 | confirmed — `call_peaks_environment.yml` |
| anndata | 0.7.6 | confirmed — `call_peaks_environment.yml` |
| numpy | 1.20.3 | confirmed — `call_peaks_environment.yml` |
| pandas | 1.3.3 | confirmed — `call_peaks_environment.yml` |
| scipy | 1.6.3 | confirmed — `call_peaks_environment.yml` |
| matplotlib | 3.4.3 | confirmed — `call_peaks_environment.yml` |
| seaborn | 0.11.2 | confirmed — `call_peaks_environment.yml` |
| statsmodels | 0.13.0 | confirmed — `call_peaks_environment.yml` |
| scikit-learn | 1.0 | confirmed — `call_peaks_environment.yml` |
| pysam | 0.17.0 | confirmed — `call_peaks_environment.yml` |
| umap-learn | 0.5.1 | confirmed — `call_peaks_environment.yml` |
| leidenalg | 0.8.7 | confirmed — `call_peaks_environment.yml` |

### Python 2 stack (`clean_barcode_multiplets_1.1.py` only)

| Component | Version | Source |
|---|---|---|
| Python | 2.7.18 | inferred — last Py2 release; deadsnakes PPA for Ubuntu 22.04 |
| pysam | 0.15.4 | inferred — last pysam with Py2 support; pip (manylinux2010 wheel) |
| pandas | 0.24.2 | inferred — last pandas with Py2 support; pip |
| numpy | 1.16.6 | inferred — last numpy with Py2 support; pip |

### Bioinformatics tools

| Component | Version | Source |
|---|---|---|
| CellRanger-ATAC | 2.2.0 (to be used) | repo states 2.0.0; see deviations |
| MACS2 | 2.2.7.1 | confirmed — `call_peaks_environment.yml` |
| bedtools | 2.30.0 | confirmed — `call_peaks_environment.yml` |
| samtools | 1.17 | inferred — not pinned in original; modern stable release |
| UCSC bedGraphToBigWig | 377 | confirmed — `call_peaks_environment.yml` |
| AMULET | 1.1 | inferred — no version stated; CLI flags match v1.1 docs |

### R stack

| Component | Version | Source |
|---|---|---|
| R | 4.1.3 | inferred — minimum compatible with Seurat 4 + Bioc 3.13 |
| Seurat | 4.3.0 | inferred — `CreateChromatinAssay` / `CreateDimReducObject` APIs match 4.x; Seurat 5 broke these |
| SeuratObject | 4.1.4 | inferred — pinned so Seurat 4.3.0 does not pull SeuratObject 5.x (requires Matrix ≥ 1.6-4) |
| Matrix | 1.5-4 | inferred — predates the Matrix ≥ 1.6-2 ABI change that breaks SeuratObject 4.x; conda-forge build `1.5_4` for R 4.1 verified to exist |
| Signac | 1.11.0 | inferred — `CreateChromatinAssay()` is Signac 1.x constructor; Signac 2.0 deprecated it |
| harmony | 1.0 | inferred — `HarmonyMatrix()` direct call; function restructured in 1.2+ |
| EnsDb.Hsapiens.v86 | Bioc 3.14 | inferred — GRCh38 annotation, Bioc 3.14 compatible with R 4.1 |
| hdf5r, dplyr, ggplot2, data.table, ggpubr, cowplot, pheatmap, gplots, tictoc, tibble, scater, sctransform, reticulate, BiocParallel, GenomeInfoDb | unpinned | inferred — versions compatible with Seurat 4 + Bioc 3.14 |

---

## Deviations from the original analysis

### CellRanger-ATAC version

The paper (Methods) states v1.1.0.  The repository's `data_preprocessing.md`
states v2.0.0 — an undocumented upgrade.  This reproduction uses **v2.2.0**
because v1.1.0 and v2.0.0 are no longer distributed by 10x Genomics.

The reference package for CellRanger-ATAC 2.0+ is named
`refdata-cellranger-arc-GRCh38-2024-A` (note "arc" in the name, not "atac").
Despite the name, this is the correct genome reference for CellRanger-ATAC 2.x,
confirmed against the 10x Genomics download page for the 2.2.0 release.
The older `refdata-cellranger-atac-GRCh38-1.2.0` package is incompatible with v2.x.

### Hardcoded paths — scripts (patched, repro branch)

`scripts/snATAC_pipeline_10X.py`: five CLI default arguments pointed to
hg19 files on the original developer's workstation.  Updated to `/reference_files/`
(hg38).  The `--picard` argument is retained for CLI compatibility but is
**dead code**: `remove_duplicate_reads()` uses only samtools; picard is
never called and is not installed in the image.

`scripts/Josh_10XPipeline_withPeaks_justLFM_UCSCcoordsShortList.py`: the
promoter windows file path was a string literal inside `generate_matrix()`,
making it impossible to override without editing source.  Moved to `--windows-file`
CLI argument with the original path as the documented default.

### Hardcoded paths — notebooks (patched, repro branch)

All `/data/`, `/reference_files/`, and `/nfs/lab/` absolute paths in
`snATAC_01` through `snATAC_05` have been replaced with environment variables
(`os.environ.get()` in Python notebooks, `Sys.getenv()` in R notebooks).
The original paths are kept as fallback defaults.  The container mounts data
at `/data` and reference files at `/reference_files` by default, so
unmodified notebooks work without setting any variables.

### Peak-call-pipeline hardcoded scripts

`mergePeaks.sh` and `merge_tagAligns.R` contain hardcoded NFS paths and
sample lists.  The pipeline README explicitly flags both as "hard coded —
be sure to adapt it to your needs."  These must be edited before use; they
are not patched in this repository because they live in an external repo.

### Unused imports removed (repro branch)

`snATAC_03`: `library(EnsDb.Mmusculus.v79)` — mouse annotation, human study;
confirmed not called anywhere in the notebook.

`snATAC_04`: `library(EnsDb.Hsapiens.v75)` — GRCh37/hg19 annotation in an
hg38 analysis; confirmed not called anywhere.  `library(EnsDb.Mmusculus.v79)` —
same as above.  Removing these avoids installing two unnecessary Bioconductor
packages (one for the wrong genome build, one for the wrong species).

### Picard

The `--picard` argument in `snATAC_pipeline_10X.py` is present in the CLI
parser but is dead code upstream: the `remove_duplicate_reads()` function
uses only samtools for duplicate marking and removal; picard is never called.
Picard is not installed in the image.

### Notebook 04 / 05 execution order

The original `data_processing.md` documents the order as 03 → 04 → 05.
This is incorrect: `snATAC_04` reads `snATAC_Lt_filt05AcinarSum.rds`, which
is an output of `snATAC_05`.  The actual required order is
**03 → 05 (label transfer) → 04 (promoter doublet removal) → 05 (final acinar filter)**.
Both notebooks contain an execution-order warning cell at the top.

### AMULET support files

`human_autosomes.txt` and `blacklist_repeats_segdups_rmsk_hg38.bed`
(AMULET's `RepeatFilterFiles/`) are bundled with the AMULET v1.1 distribution
and are not in this repository's `reference_files/`.  The `hg38-blacklist.v3.bed`
in `reference_files/` is the ENCODE blacklist used by `snATAC_pipeline_10X.py` —
it is a different file from the AMULET-specific repeat/segdup filter.

### No R version pins in original notebooks

No R package versions are specified anywhere in the original notebooks.
All R versions in the table above are inferred from the API calls used
(see "confirmed vs. inferred" column).

> **Re-verify on first build:** the R / Seurat / SeuratObject / Signac / Matrix
> compatibility claims above were inferred from general knowledge at authoring
> time, not checked against live package metadata. Re-verify them against the
> packages actually installed (`sessionInfo()` in the `r4` kernel) during the
> first real build on Dora.
>
> The shell activation of py3 (`/etc/profile.d/npod-py3.sh` sourced from
> `/etc/bash.bashrc`, plus `ENV PATH`) is based on reasoning from the bash
> documentation (`man bash`, INVOCATION) and was tested only in a minimal
> Ubuntu 22.04 image (micromamba + py3 with Python only), not in the full
> image. Confirm on the first real build that
> `docker exec -it <container> bash` and `docker exec <container> python`
> both resolve to `/opt/conda/envs/py3/bin/python`.

---

## Repository structure

```
nPOD-repro/
├── Dockerfile                          Container definition (three envs)
├── docker-compose.yml                  Service configuration
├── entrypoint.sh                       Starts JupyterLab in the py3 env
├── py3-activate.sh                     Activates py3 in every container shell
├── CLAUDE.md                           Claude Code guidance
├── Data_proccessing/
│   ├── data_preprocessing.md           CellRanger commands (original authors)
│   ├── data_processing.md              Per-sample QC overview (original authors)
│   ├── snATAC_01_indSample_processing.ipynb   Python 3.7 — per-sample QC
│   ├── snATAC_02_AMULET_singlecellFile_singlomeOnly.ipynb   Python 3.7 — AMULET prep
│   ├── snATAC_03_mergeATACobj.ipynb    R 4.1 — merge + cluster
│   ├── snATAC_04_manualDoubletRemoval_PromAccess.ipynb   R 4.1 — doublet removal
│   └── snATAC_05_labelTransfer_github.ipynb   R 4.1 — label transfer
├── scripts/
│   ├── snATAC_pipeline_10X.py          BAM → fragment matrix (Python 3)
│   ├── Josh_10XPipeline_withPeaks_justLFM_UCSCcoordsShortList.py   Promoter matrix
│   └── clean_barcode_multiplets_1.1.py Multiplet removal (Python 2 only)
└── reference_files/                    hg38 reference files (see README therein)
```

---

### Python 2.7 source: deadsnakes PPA instead of conda Anaconda defaults

`conda-forge` and `bioconda` dropped Python 2.7 builds after its January 2020
end-of-life; `python=2.7.18` is no longer resolvable from those channels.
The Anaconda `defaults` channel (`pkgs/main`) still carries the build, but its
Terms of Service require a paid licence for organisations with ≥ 200
employees/contractors; academic institutions "may qualify for exemptions" —
a conditional, not a guaranteed right. Because this repository is public and
can be built by anyone, relying on `defaults` would expose contributors and
users to an ambiguous licence situation without their knowledge.
Python 2.7.18 is therefore installed from the
[deadsnakes PPA](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa),
which packages upstream CPython releases for Ubuntu without distribution
restrictions. `pysam 0.15.4`, `pandas 0.24.2`, and `numpy 1.16.6` are
installed via pip; pysam ships a manylinux2010 pre-built wheel so no C
compilation is required at image build time.

---

## References

- Melton et al. (2025). *Science Advances*, eady0080.
- Gaulton-Lab peak-call-pipeline: <https://github.com/Gaulton-Lab/peak-call-pipeline>
- AMULET v1.1: <https://github.com/tdslam/AMULET>
- CellRanger-ATAC: <https://www.10xgenomics.com/support/software/cell-ranger-atac>

## Licence

MIT. See LICENSE.
