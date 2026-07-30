#!/usr/bin/env bash
#
# Run the segment-sampler chain smoke test (xerosere ddm-69y.5):
# gun -> edep-sim -> observables -> tracksegmentset -> WCT TrackSegmentSampler
# -> deposet, with wc.tracksegmentset + wc.deposet persisted to HDF5.
#
# Assumes the gcc15 view and that hepmc-phlex, edep-sim-phlex, wire-cell-phlex
# and wire-cell-phlex-arrow have standalone builds under builds/envs/gcc15/
# and that WCT + phlex-arrow-hdf are installed in installs/envs/gcc15/.
#
# Success is judged by the OUTPUT (HDF5 contents), not phlex's exit code.
set -uo pipefail

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

view="$root/extern/envs/gcc15/view"
install="$root/installs/envs/gcc15"
builds="$root/builds/envs/gcc15"
edepsim_root="$(echo "$root"/extern/spack/opt/spack/*/edepsim-*/ | awk '{print $1}')"

export PHLEX_PLUGIN_PATH="$builds/hepmc-phlex:$builds/edep-sim-phlex:$builds/wire-cell-phlex:$builds/wire-cell-phlex-arrow:$install/lib:$view/lib"
export LD_LIBRARY_PATH="$install/lib:$view/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WIRECELL_PATH="$root/devel/wire-cell-phlex/cfg:$install/share/wirecell:$view/share/wirecell"
export EDEPSIM_ROOT="$edepsim_root"

workdir="$(mktemp -d)"
echo "workdir: $workdir"
cd "$workdir"

"$view/bin/phlex" -c "$here/smoke-segments-to-depos.jsonnet" > phlex.log 2>&1 || true
grep -E 'error|Error|what\(\)' phlex.log | head -5 || true

h5="$workdir/segments-to-depos.h5"
if [ ! -s "$h5" ]; then
    echo "SMOKE TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

# Capture-first (grep -q + pipefail SIGPIPE-kills h5ls otherwise).
h5_contents="$("$view/bin/h5ls" -r "$h5" 2>/dev/null)"
if ! printf '%s\n' "$h5_contents" | grep -q 'tracksegmentset/wc.tracksegment.n_electrons'; then
    echo "SMOKE TEST FAILED: no wc.tracksegmentset table in $h5"
    printf '%s\n' "$h5_contents" | head -20
    exit 1
fi
if ! printf '%s\n' "$h5_contents" | grep -q 'deposet/wc.depo.charge'; then
    echo "SMOKE TEST FAILED: no wc.deposet table in $h5"
    printf '%s\n' "$h5_contents" | head -20
    exit 1
fi

# The depo count must be >= the segment count (>=1 sample per segment).
nseg="$(printf '%s\n' "$h5_contents" | grep -m1 'tracksegmentset/wc.tracksegment.n_electrons' | grep -o '{[0-9]*}' | tr -d '{}')"
ndep="$(printf '%s\n' "$h5_contents" | grep -m1 'deposet/wc.depo.charge' | grep -o '{[0-9]*}' | tr -d '{}')"
echo "segments=$nseg depos=$ndep"
if [ -z "$nseg" ] || [ -z "$ndep" ] || [ "$nseg" -lt 1 ] || [ "$ndep" -lt "$nseg" ]; then
    echo "SMOKE TEST FAILED: implausible segment/depo counts"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "SMOKE TEST PASSED: segments sampled to depos AND persisted to HDF5."
