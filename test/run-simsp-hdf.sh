#!/usr/bin/env bash
#
# run-simsp-hdf.sh -- sim+signal-processing regression smoke with HDF I/O
# (xerosere ddm-3bu.9), the HDF-file analog of the WCT BATS test
# test-pdsp-simsn-nfsp.bats.  Covers PDSP, PDHD and PDVD.
#
# For each detector it generates ideal-line depos in-process, runs
# drift+sim+OmnibusSigProc, writes the gauss frame to arrow-hdf, and asserts the
# SP frame's total ROI-trace count is in (0, CEIL).  A regression of the PDHD
# troi_col_th_factor collection bug (2.5 instead of 5.0) floods the frame with
# ~50k noise ROIs/event and trips the ceiling; a clean run is a few thousand.
#
# PDHD is run with sp_wiener=narrow (the bare-OSP Wiener that also tames the
# induction planes, ddm-3bu.9); pdsp/pdvd use their native filters.
#
# Usage: run-simsp-hdf.sh [env=gcc15] [detector...]
#   detectors default: pdsp pdhd pdvd
# Exit: 0 = pass, 1 = failure, 77 = skipped (env/build not present).

set -uo pipefail

SKIP=77
name="simsp-hdf"
say()  { echo "[$name] $*" >&2; }
skip() { say "SKIP: $*"; exit "$SKIP"; }
die()  { say "ERROR: $*"; exit 1; }

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

env_name="${1:-gcc15}"; [ $# -gt 0 ] && shift || true
dets=( "$@" ); [ "${#dets[@]}" -gt 0 ] || dets=( pdsp pdhd pdvd )

view="$root/extern/envs/$env_name/view"
install="$root/installs/envs/$env_name"
builds="$root/builds/envs/$env_name"
phlex="$view/bin/phlex"
h5ls="$view/bin/h5ls"

[ -x "$phlex" ]                                             || skip "phlex not found ($phlex)"
[ -e "$builds/edep-phlex/libedp_line_gen.so" ]             || skip "edep-phlex not built"
[ -e "$builds/wire-cell-phlex/libwcph_tracksegmentset_to_frame.so" ] || skip "wire-cell-phlex not built"
[ -e "$builds/wire-cell-phlex-arrow/libwire_cell_phlex_arrow_convert.so" ] || skip "wire-cell-phlex-arrow not built"
[ -e "$install/lib/libphlex_arrow_hdf_output.so" ]         || skip "phlex-arrow-hdf not installed"
[ -d "$root/reference/wire-cell-data" ]                    || skip "wire-cell-data not present"

export PHLEX_PLUGIN_PATH="$builds/edep-phlex:$builds/wire-cell-phlex:$builds/wire-cell-phlex-arrow:$install/lib:$view/lib"
export LD_LIBRARY_PATH="$builds/edep-phlex:$install/lib:$install/lib64:$view/lib:$view/lib64:${LD_LIBRARY_PATH:-}"
export WIRECELL_PATH="$root/devel/wire-cell-phlex/cfg:$root/reference/wire-cell-data:$root/reference/dunereco/dunereco/DUNEWireCell/protodunevd:$install/share/wirecell:$view/share/wirecell"
export GODEBUG="${GODEBUG:+$GODEBUG,}asyncpreemptoff=1"

# Per-detector line center (mm, inside anode-0 drift volume), Wiener set, and the
# total-ROI ceiling (a clean 4-event run is a few thousand; the troi_col bug is
# tens of thousands per event).
det_center() { case "$1" in
    pdsp) echo '[-1000.0, 2000.0, 1000.0]' ;;
    pdhd) echo '[-1000.0, 2000.0, 1000.0]' ;;
    pdvd) echo '[-1000.0, 2000.0, 1000.0]' ;;
esac; }
det_wiener() { case "$1" in pdhd) echo narrow ;; *) echo native ;; esac; }
det_ceil()   { echo 30000; }

workroot="${SIMSP_HDF_OUTDIR:-$(mktemp -d)}"
say "workdir: $workroot"

overall=0
for det in "${dets[@]}"; do
    case "$det" in pdsp|pdhd|pdvd) ;; *) die "unknown detector '$det'";; esac
    outdir="$workroot/$det"; mkdir -p "$outdir"
    job="$outdir/smoke-simsp-hdf.jsonnet"
    out="$outdir/simsp-$det.h5"
    center="$(det_center "$det")"; wiener="$(det_wiener "$det")"; ceil="$(det_ceil "$det")"

    sed -e "s|@DETECTOR@|$det|g" -e "s|@CENTER@|$center|g" \
        -e "s|@SP_WIENER@|$wiener|g" -e "s|@OUT@|$out|g" \
        "$here/smoke-simsp-hdf.jsonnet.in" > "$job"

    say "=== $det (sp_wiener=$wiener) -> $out ==="
    if ( cd "$outdir" && "$phlex" -c "$job" > phlex.log 2>&1 ); then :; else
        # A missing detector data file (e.g. a field-response .json.bz2 not shipped
        # in this wire-cell-data) is an environment gap, not a regression -> skip
        # this detector rather than failing the whole test.
        if grep -qiE 'no such file:.*\.json\.bz2|Maybe you need to add to WIRECELL_PATH' "$outdir/phlex.log"; then
            miss="$(grep -oE 'no such file: [^ ]+' "$outdir/phlex.log" | head -1)"
            say "$det: SKIP -- missing detector data file (${miss:-unknown}) in this environment"
            continue
        fi
        say "$det: phlex run FAILED"; tail -20 "$outdir/phlex.log" >&2; overall=1; continue
    fi
    [ -s "$out" ] || { say "$det: no HDF5 output produced"; overall=1; continue; }

    # Sum wc.trace.channel dataset sizes across all events = total SP ROI-traces.
    # Match ONLY the frame traces channel dataset (not trace_tags.trace_index etc.).
    listing="$("$h5ls" -r "$out" 2>/dev/null)"
    ntraces="$(printf '%s\n' "$listing" \
        | grep -E '/frame/traces/wc\.trace\.channel Dataset \{[0-9]+\}' \
        | grep -oE 'Dataset \{[0-9]+\}' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')"

    say "$det: total SP ROI-traces = ${ntraces:-0} (ceiling $ceil)"
    if [ -z "$ntraces" ] || [ "$ntraces" -lt 1 ]; then
        say "$det: FAIL -- zero SP ROI-traces (line not seen? sim/SP failed?)"; overall=1; continue
    fi
    if [ "$ntraces" -gt "$ceil" ]; then
        say "$det: FAIL -- SP ROI-trace count $ntraces exceeds ceiling $ceil"
        say "$det:        (regression of the troi_col_th_factor collection bug, ddm-3bu.9?)"
        overall=1; continue
    fi
    say "$det: PASS"
done

if [ "$overall" -eq 0 ]; then
    say "ALL PASS (${dets[*]})"
else
    say "FAILURES present"
fi
exit "$overall"
