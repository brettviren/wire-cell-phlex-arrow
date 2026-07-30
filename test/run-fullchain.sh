#!/usr/bin/env bash
#
# Run the FULL-CHAIN smoke (xerosere ddm-69y.7): gun -> edep-sim (PDHD GDML)
# -> observables -> tracksegmentset -> WCT (TrackSegmentSampler -> drift ->
# sim -> sigproc) -> wc.frame -> HDF5.  Success = the HDF5 holds a wc.frame
# traces table with nonzero rows.
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

workdir="$(mktemp -d)"
echo "workdir: $workdir"
cd "$workdir"

"$view/bin/phlex" -c "$here/smoke-fullchain-pdhd.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/fullchain-pdhd.h5"
if [ ! -s "$h5" ]; then
    echo "FULL-CHAIN TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

h5_contents="$("$view/bin/h5ls" -r "$h5" 2>/dev/null)"
traces_line="$(printf '%s\n' "$h5_contents" | grep -m1 'frame/traces/wc.trace.charge')"
if [ -z "$traces_line" ]; then
    echo "FULL-CHAIN TEST FAILED: no wc.frame traces table in $h5"
    printf '%s\n' "$h5_contents" | head -20
    exit 1
fi
ntraces="$(printf '%s\n' "$traces_line" | grep -o '{[0-9]*' | tr -d '{')"
echo "traces=$ntraces"
if [ -z "$ntraces" ] || [ "$ntraces" -lt 1 ]; then
    echo "FULL-CHAIN TEST FAILED: zero traces (gun/anode mismatch?)"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "FULL-CHAIN TEST PASSED: gun -> edep-sim -> sampler -> sim+sigproc -> HDF5."
