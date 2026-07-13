# Data Download Instructions
## Marketplace Analytics Platform

This project uses the Olist Brazilian E-Commerce dataset from Kaggle (9 CSVs, ~126 MB, Version 2). The raw data is not committed to this repository (see `.gitignore`) — anyone replicating this project needs to download it locally using the steps below.

## Prerequisites

- A free Kaggle account: https://www.kaggle.com/account/login
- This repo's conda environment created and activated (see `environment.yml`), which installs the `kaggle` CLI

## Steps

**1. Create and activate the conda environment**

```bash
conda env create -f environment.yml
conda activate Marketplace-Analytics-Platform
```

**2. Authenticate with Kaggle (one-time)**

```bash
kaggle auth login
```

This opens a browser OAuth flow — log in and approve access. Credentials are cached locally; you won't need to repeat this on the same machine.

**3. Download the dataset**

```bash
python data/02_download_data.py
```

This pulls all 9 CSVs directly into `data/`, so every script and notebook in this repo can rely on a fixed path (`data/<file>.csv`). If the files already exist, the script skips downloading and exits immediately.

## Notes

- The `kaggle` CLI always downloads whatever version is currently live — there is no option to pin an older version. This project was built on Version 2 (confirmed via the Kaggle dataset page on 2026-07-13).
- If `kaggle auth login` reports you're already logged in, no further action is needed — proceed to step 3.
- Dataset source: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
