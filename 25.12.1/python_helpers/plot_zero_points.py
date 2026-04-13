#!/usr/bin/env python3
"""
compare_mag_systems.py

Runs MESA colors post-processor 3 times with different magnitude zero-point
systems (Vega, AB, ST) and overlays the resulting CMDs for comparison.

Usage: python compare_mag_systems.py
       (Run from the custom_colors test suite directory)

Requires an existing MESA LOGS directory (or LOGS_original backup) containing
history.data from a completed stellar evolution run.

Niall Miller (2025)
"""

import os
import re
import shutil
import subprocess

import matplotlib.pyplot as plt
import numpy as np

# Configuration
MAG_SYSTEMS = ["Vega", "AB", "ST"]
COLORS = {"Vega": "blue", "AB": "red", "ST": "green"}
INLIST_COLORS = "inlist"
LOGS_ORIGINAL = "LOGS_original"  # backup of original MESA run — preserved across runs

os.chdir("../")


def read_inlist(filename):
    """Read inlist file content."""
    with open(filename, "r") as f:
        return f.read()


def write_inlist(filename, content):
    """Write inlist file content."""
    with open(filename, "w") as f:
        f.write(content)


def modify_mag_system(content, mag_system):
    """Change the mag_system parameter in inlist content."""
    pattern = r"(mag_system\s*=\s*')[^']*(')"
    return re.sub(pattern, rf"\g<1>{mag_system}\g<2>", content)


def ensure_logs_backup():
    """
    Back up the original LOGS directory to LOGS_original if not already done.
    This must exist before the first run wipes LOGS.
    """
    if os.path.exists(LOGS_ORIGINAL):
        return True
    if os.path.exists("LOGS"):
        print(f"Backing up LOGS -> {LOGS_ORIGINAL}")
        shutil.copytree("LOGS", LOGS_ORIGINAL)
        return True
    print(
        f"Error: Neither LOGS nor {LOGS_ORIGINAL} found.\n"
        "Run a full MESA stellar evolution first, then re-run this script."
    )
    return False


def restore_logs():
    """Restore LOGS from LOGS_original so the post-processor has its input."""
    if os.path.exists("LOGS"):
        shutil.rmtree("LOGS")
    shutil.copytree(LOGS_ORIGINAL, "LOGS")


def run_postproc(mag_system, run_dir):
    """Run the colors post-processor with the specified mag_system."""
    print(f"\n{'=' * 60}")
    print(f"Running colors post-processor with mag_system = {mag_system}")
    print(f"{'=' * 60}")

    # Restore original LOGS so the post-processor can read history.data
    restore_logs()

    # Temporarily patch the inlist
    original_content = read_inlist(INLIST_COLORS)
    modified_content = modify_mag_system(original_content, mag_system)
    # Disable pgstar for batch runs
    modified_content = re.sub(
        r"pgstar_flag\s*=\s*\.true\.", "pgstar_flag = .false.", modified_content
    )
    write_inlist(INLIST_COLORS, modified_content)

    try:
        result = subprocess.run(
            ["./rn"],
            capture_output=True,
            text=True,
            timeout=3600,
        )
        if result.returncode != 0:
            print(f"Post-processor failed for {mag_system}")
            print(result.stderr)
        else:
            print(f"Post-processor succeeded for {mag_system}")
    except subprocess.TimeoutExpired:
        print(f"Post-processor timed out for {mag_system}")
    except Exception as e:
        print(f"Error running post-processor: {e}")
    finally:
        write_inlist(INLIST_COLORS, original_content)

    # Save this run's LOGS
    if os.path.exists("LOGS"):
        if os.path.exists(run_dir):
            shutil.rmtree(run_dir)
        shutil.copytree("LOGS", run_dir)
        print(f"Results saved to {run_dir}")


def read_mesa_history(logs_dir):
    """Read MESA history.data and return as dict of arrays."""
    history_file = os.path.join(logs_dir, "history.data")

    if not os.path.exists(history_file):
        print(f"Warning: {history_file} not found")
        return None

    with open(history_file, "r") as f:
        lines = f.readlines()

    # Find the column-names header line
    header_line = 5
    for i, line in enumerate(lines):
        if "model_number" in line:
            header_line = i
            break

    column_names = lines[header_line].split()
    data = np.loadtxt(history_file, skiprows=header_line + 1)

    result = {}
    for i, name in enumerate(column_names):
        if i < data.shape[1]:
            result[name] = data[:, i]

    return result


def find_column(data, candidates):
    """Return the first candidate column name found in data, or None."""
    for name in candidates:
        if name in data:
            return name
    return None


def plot_cmd_comparison(results):
    """Plot CMD comparison for all mag systems."""

    # Print available columns from the first successful result so the user
    # can verify the filter names if the plots come out empty.
    for mag_system, data in results.items():
        if data is not None:
            print(f"\nAvailable history columns ({mag_system}):")
            print("  " + "  ".join(data.keys()))
            break

    # Common alternative column names for Bessell B, V, U filters
    B_CANDIDATES = ["B", "Bessell_B", "bessell_B", "mag_B", "johnson_B"]
    V_CANDIDATES = ["V", "Bessell_V", "bessell_V", "mag_V", "johnson_V"]
    U_CANDIDATES = ["U", "Bessell_U", "bessell_U", "mag_U", "johnson_U"]

    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    # CMD 1: B-V vs V
    ax1 = axes[0]
    for mag_system, data in results.items():
        if data is None:
            continue
        b_col = find_column(data, B_CANDIDATES)
        v_col = find_column(data, V_CANDIDATES)
        if b_col and v_col:
            ax1.plot(
                data[b_col] - data[v_col],
                data[v_col],
                "-",
                color=COLORS[mag_system],
                label=mag_system,
                alpha=0.8,
                linewidth=1.5,
            )
        else:
            print(f"Warning: B or V column not found for {mag_system} — skipping CMD1")

    ax1.set_xlabel("B - V", fontsize=12)
    ax1.set_ylabel("V (mag)", fontsize=12)
    ax1.set_title("CMD: B-V vs V", fontsize=14)
    ax1.invert_yaxis()
    ax1.legend(loc="best")
    ax1.grid(True, alpha=0.3)

    # CMD 2: U-B vs B
    ax2 = axes[1]
    for mag_system, data in results.items():
        if data is None:
            continue
        u_col = find_column(data, U_CANDIDATES)
        b_col = find_column(data, B_CANDIDATES)
        if u_col and b_col:
            ax2.plot(
                data[u_col] - data[b_col],
                data[b_col],
                "-",
                color=COLORS[mag_system],
                label=mag_system,
                alpha=0.8,
                linewidth=1.5,
            )
        else:
            print(f"Warning: U or B column not found for {mag_system} — skipping CMD2")

    ax2.set_xlabel("U - B", fontsize=12)
    ax2.set_ylabel("B (mag)", fontsize=12)
    ax2.set_title("CMD: U-B vs B", fontsize=14)
    ax2.invert_yaxis()
    ax2.legend(loc="best")
    ax2.grid(True, alpha=0.3)

    plt.suptitle("Magnitude System Comparison", fontsize=16, y=1.02)
    plt.tight_layout()

    output_file = "mag_system_comparison.png"
    plt.savefig(output_file, dpi=150, bbox_inches="tight")
    print(f"\nPlot saved to {output_file}")


def main():
    """Main execution."""
    if not os.path.exists(INLIST_COLORS):
        print(f"Error: {INLIST_COLORS} not found. Run from custom_colors directory.")
        return

    if not os.path.exists("./rn"):
        print("Error: ./rn not found. Run from custom_colors directory.")
        return

    if not ensure_logs_backup():
        return

    results = {}

    for mag_system in MAG_SYSTEMS:
        run_dir = f"LOGS_{mag_system}"
        run_postproc(mag_system, run_dir)
        results[mag_system] = read_mesa_history(run_dir)

    plot_cmd_comparison(results)

    print("\n" + "=" * 60)
    print("Comparison complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
