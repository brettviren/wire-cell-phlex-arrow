#!/usr/bin/env bash
#
# Run the SPLIT full-chain smoke + post-drift depos (xerosere ddm-0hk): the
# run-fullchain-split.sh graph (sim island -> ADC Frame, sigproc island ->
# signal Frame) with an ADDED lightweight drift island that taps the DRIFTED
# depos (the input to DepoTransform) and writes them to the same HDF5 next to
# the ADC and signal-processed frames.  Success = the HDF5 holds nonzero-row
# tables from to_arrow_depo (wc.deposet) AND to_arrow_adc / to_arrow_sig
# (wc.frame traces).
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

# Run single-threaded (-j 1).  Each WCT island's executor evaluates its
# wct_config via the embedded go-jsonnet through a cgo entrypoint; evaluating
# from multiple phlex worker threads concurrently crashes the Go runtime
# ("fatal error: traceback did not unwind completely").  This pre-existing
# issue also aborts the default-parallelism run-fullchain-split.sh here; -j 1
# serializes the config evaluations so the smoke test runs deterministically.
"$view/bin/phlex" -j 1 -c "$here/smoke-fullchain-pdhd-split-depos.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/fullchain-pdhd-split-depos.h5"
if [ ! -s "$h5" ]; then
    echo "SPLIT FULL-CHAIN+DEPOS TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

h5_contents="$("$view/bin/h5ls" -r "$h5" 2>/dev/null)"
fail=0

# The drifted depos: to_arrow_depo -> wc.deposet table with wc.depo.* columns.
depo_line="$(printf '%s\n' "$h5_contents" | grep -m1 'to_arrow_depo.*deposet/wc.depo.charge')"
if [ -z "$depo_line" ]; then
    echo "SPLIT FULL-CHAIN+DEPOS TEST FAILED: no wc.deposet table from to_arrow_depo in $h5"
    fail=1
else
    ndepos="$(printf '%s\n' "$depo_line" | grep -o '{[0-9]*' | tr -d '{')"
    echo "to_arrow_depo: depos=$ndepos"
    if [ -z "$ndepos" ] || [ "$ndepos" -lt 1 ]; then
        echo "SPLIT FULL-CHAIN+DEPOS TEST FAILED: zero drifted depos from to_arrow_depo"
        fail=1
    fi
fi

# The ADC and signal frames, as in run-fullchain-split.sh.
for tap in to_arrow_adc to_arrow_sig; do
    traces_line="$(printf '%s\n' "$h5_contents" | grep -m1 "$tap.*frame/traces/wc.trace.charge")"
    if [ -z "$traces_line" ]; then
        echo "SPLIT FULL-CHAIN+DEPOS TEST FAILED: no wc.frame traces table from $tap in $h5"
        fail=1
        continue
    fi
    ntraces="$(printf '%s\n' "$traces_line" | grep -o '{[0-9]*' | tr -d '{')"
    echo "$tap: traces=$ntraces"
    if [ -z "$ntraces" ] || [ "$ntraces" -lt 1 ]; then
        echo "SPLIT FULL-CHAIN+DEPOS TEST FAILED: zero traces from $tap"
        fail=1
    fi
done
if [ "$fail" -ne 0 ]; then
    printf '%s\n' "$h5_contents" | head -40
    exit 1
fi

echo "----------------------------------------------------------------"
echo "SPLIT FULL-CHAIN+DEPOS TEST PASSED: drift island (depos) + sim island (ADC)"
echo "  + sigproc island -> HDF5."
echo "view with: adove gui $h5"
