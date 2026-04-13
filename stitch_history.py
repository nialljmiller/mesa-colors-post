#!/usr/bin/env python3
"""
stitch_history.py — appends colors columns onto the original MESA history file.

Reads history_file and output_file from the existing &post_proc namelist in
'inlist'. The colors output_file is expected to have been produced by
colors_post_proc. The stitched result is written to history_with_colors.data.

Usage:
    python stitch_history.py
"""

import re
import sys

HISTORY_HEADER_LINES = 6   # 5 MESA header lines + 1 column-name line
COLORS_SKIP_COLS     = 4   # star_age, Teff, log_g, feh  (already in history)
STITCHED_OUTPUT      = 'history_with_colors.data'

# --- read inlist ---
try:
    with open('inlist') as f:
        text = f.read()
except FileNotFoundError:
    sys.exit('error: inlist not found')

m_hist = re.search(r"history_file\s*=\s*'([^']+)'", text)
m_out  = re.search(r"output_file\s*=\s*'([^']+)'",  text)

history_file  = m_hist.group(1) if m_hist else 'LOGS/history.data'
colors_file   = m_out.group(1)  if m_out  else 'post_proc_output.data'

# --- read original history file (preserve everything) ---
try:
    with open(history_file) as f:
        hist_lines = f.readlines()
except FileNotFoundError:
    sys.exit(f'error: history file not found: {history_file}')

hist_header = hist_lines[:HISTORY_HEADER_LINES]
hist_data   = [l for l in hist_lines[HISTORY_HEADER_LINES:] if l.strip()]
hist_cols   = hist_header[HISTORY_HEADER_LINES - 1].split()

# --- read colors output file ---
try:
    with open(colors_file) as f:
        col_lines = f.readlines()
except FileNotFoundError:
    sys.exit(f'error: colors output file not found: {colors_file}')

col_header = col_lines[0]
col_data   = [l for l in col_lines[1:] if l.strip()]
col_names  = col_header.split()[COLORS_SKIP_COLS:]   # drop repeated cols

# --- check row counts match ---
if len(hist_data) != len(col_data):
    sys.exit(
        f'error: row count mismatch — '
        f'history has {len(hist_data)} models, '
        f'colors output has {len(col_data)}'
    )

# --- build stitched header ---
stitched_col_header = (
    hist_header[HISTORY_HEADER_LINES - 1].rstrip()
    + '   ' + '   '.join(col_names) + '\n'
)
stitched_header = hist_header[:HISTORY_HEADER_LINES - 1] + [stitched_col_header]

# --- stitch rows ---
stitched_rows = []
for h_line, c_line in zip(hist_data, col_data):
    color_vals = c_line.split()[COLORS_SKIP_COLS:]
    stitched_rows.append(h_line.rstrip() + '   ' + '   '.join(color_vals) + '\n')

# --- write output ---
with open(STITCHED_OUTPUT, 'w') as f:
    f.writelines(stitched_header)
    f.writelines(stitched_rows)

print(f'history : {history_file} ({len(hist_data)} models, {len(hist_cols)} cols)')
print(f'colors  : {colors_file} (+{len(col_names)} color cols)')
print(f'wrote   : {STITCHED_OUTPUT}')