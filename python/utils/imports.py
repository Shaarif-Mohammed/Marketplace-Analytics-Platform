# =============================================================================
# python/utils/imports.py
# Standard library imports and display configuration for all notebooks.
# =============================================================================

import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
from scipy import stats
import statsmodels.api as sm
from IPython.display import display

warnings.filterwarnings("ignore")

pd.set_option("display.max_columns", None)
pd.set_option("display.max_rows", 100)
pd.set_option("display.float_format", "{:,.2f}".format)

# --- Plot styling: consistent, presentation-quality look across all notebooks ---
PALETTE = ["#2E5EAA", "#E8743B", "#4BA173", "#C94C4C", "#8067C2", "#D4A72C"]

sns.set_theme(
    context="notebook",
    style="whitegrid",
    palette=PALETTE,
    font_scale=1.05,
)

plt.rcParams.update({
    "figure.figsize": (10, 6),
    "figure.dpi": 100,
    "savefig.dpi": 200,
    "axes.titlesize": 14,
    "axes.titleweight": "bold",
    "axes.labelsize": 11,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "legend.frameon": False,
    "font.family": "sans-serif",
})


def format_thousands(ax, axis="y"):
    """Apply thousands-separator formatting to an axis (e.g. 12,000 not 12000)."""
    formatter = mticker.FuncFormatter(lambda x, _: f"{x:,.0f}")
    getattr(ax, f"{axis}axis").set_major_formatter(formatter)