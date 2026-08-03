#!/usr/bin/env bash
#
# Run the SPLIT full-chain smoke (xerosere ddm-0hk.1): the run-fullchain.sh
# WCT graph separated into a sim island (-> ADC Frame product) and a sigproc
# island, with BOTH the ADC frame and the signal-processed frame converted to
# wc.frame and written to one HDF5.  Success = the HDF5 holds nonzero-row
# traces tables from both to_arrow_adc and to_arrow_sig.
set -uo pipefail

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

view="$root/extern/envs/gcc15/view"
install="$root/installs/envs/gcc15"
builds="$root/builds/envs/gcc15"
edepsim_root="$(echo "$root"/extern/spack/opt/spack/*/edepsim-*/ | awk '{print $1}')"

export PHLEX_PLUGIN_PATH="$builds/hepmc-phlex:$builds/edep-sim-phlex:$builds/wire-cell-phlex:$builds/wire-cell-phlex-arrow:$install/lib:$view/lib"
export LD_LIBRARY_PATH="$install/lib:$view/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WIRECELL_PATH="$root/devel/wire-cell-phlex/cfg:$root/reference/wire-cell-data:$install/share/wirecell:$view/share/wirecell"
export EDEPSIM_ROOT="$edepsim_root"

workdir="${1:-$(mktemp -d)}"
mkdir -p "$workdir"
echo "workdir: $workdir"
cd "$workdir"

"$view/bin/phlex" -c "$here/smoke-fullchain-pdhd-split.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/fullchain-pdhd-split.h5"
if [ ! -s "$h5" ]; then
    echo "SPLIT FULL-CHAIN TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

h5_contents="$("$view/bin/h5ls" -r "$h5" 2>/dev/null)"
fail=0
for tap in to_arrow_adc to_arrow_sig; do
    traces_line="$(printf '%s\n' "$h5_contents" | grep -m1 "$tap.*frame/traces/wc.trace.charge")"
    if [ -z "$traces_line" ]; then
        echo "SPLIT FULL-CHAIN TEST FAILED: no wc.frame traces table from $tap in $h5"
        fail=1
        continue
    fi
    ntraces="$(printf '%s\n' "$traces_line" | grep -o '{[0-9]*' | tr -d '{')"
    echo "$tap: traces=$ntraces"
    if [ -z "$ntraces" ] || [ "$ntraces" -lt 1 ]; then
        echo "SPLIT FULL-CHAIN TEST FAILED: zero traces from $tap"
        fail=1
    fi
done
if [ "$fail" -ne 0 ]; then
    printf '%s\n' "$h5_contents" | head -30
    exit 1
fi

echo "----------------------------------------------------------------"
echo "SPLIT FULL-CHAIN TEST PASSED: sim island (ADC) + sigproc island -> HDF5."
echo "view with: adove gui $h5"
