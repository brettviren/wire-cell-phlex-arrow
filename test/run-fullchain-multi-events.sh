#!/usr/bin/env bash
#
# Run the MULTI-EVENT split full-chain + initial/post-drift depos (xerosere):
# smoke-fullchain-pdhd-multi-events.jsonnet drives SIX distinct events from a
# single GenEventSequence source and, for EACH event, taps four products into one
# HDF5 -- initial (pre-drift) depos (depo_sample), post-drift depos (depo_drift),
# the ADC frame (frame_sim) and the signal-processed frame (frame_sigproc).
#
# This is the first test exercising phlex multi-"event" execution and multi-event
# output, so success requires that ALL SIX events (0..5) produced nonzero-row
# tables for ALL FOUR taps:
#   to_arrow_sampledepo / to_arrow_depo -> wc.deposet (wc.depo.charge)
#   to_arrow_adc        / to_arrow_sig  -> wc.frame traces (wc.trace.charge)
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

# The embedded go-jsonnet engine (used by each WCT island to evaluate its
# wct_config) intermittently crashes the Go runtime with "fatal error: traceback
# did not unwind completely" when it runs after the Geant4 stage: Go's
# async-preemption signals conflict with the foreign native threads Geant4/TBB
# leave behind.  Disabling async preemption removes the conflict (project memory
# go-jsonnet-gc-flake).  This is more likely to bite here than in the
# single-event smoke because six events drive many more evaluations.
export GODEBUG="${GODEBUG:+$GODEBUG,}asyncpreemptoff=1"

workdir="${1:-$(mktemp -d)}"
mkdir -p "$workdir"
echo "workdir: $workdir"
cd "$workdir"

nevents=6

# Run single-threaded (-j 1).  Each WCT island's executor evaluates its
# wct_config via the embedded go-jsonnet through a cgo entrypoint; evaluating
# from multiple phlex worker threads concurrently crashes the Go runtime.  -j 1
# serializes the config evaluations so the smoke test runs deterministically.
"$view/bin/phlex" -j 1 -c "$here/smoke-fullchain-pdhd-multi-events.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/fullchain-pdhd-multi-events.h5"
if [ ! -s "$h5" ]; then
    echo "MULTI-EVENT FULL-CHAIN TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

h5_contents="$("$view/bin/h5ls" -r "$h5" 2>/dev/null)"
fail=0

# check_tap <module-label> <path-tail>
#   Verify every event 0..(nevents-1) has a line matching the module label and
#   the product-table tail, with a nonzero first dimension (row count).
check_tap() {
    local tap="$1" tail_pat="$2"
    local missing="" n line count
    for ((n = 0; n < nevents; n++)); do
        line="$(printf '%s\n' "$h5_contents" | grep -m1 "/event/$n/.*$tap.*$tail_pat")"
        if [ -z "$line" ]; then
            missing="$missing $n"
            continue
        fi
        count="$(printf '%s\n' "$line" | grep -o '{[0-9]*' | head -1 | tr -d '{')"
        if [ -z "$count" ] || [ "$count" -lt 1 ]; then
            echo "  $tap event $n: ZERO rows"
            fail=1
        else
            echo "  $tap event $n: rows=$count"
        fi
    done
    if [ -n "$missing" ]; then
        echo "MULTI-EVENT FULL-CHAIN TEST FAILED: $tap missing events:$missing"
        fail=1
    fi
}

echo "initial (pre-drift) depos:"
check_tap to_arrow_sampledepo 'deposet/wc.depo.charge'
echo "post-drift depos:"
check_tap to_arrow_depo 'deposet/wc.depo.charge'
echo "ADC frame:"
check_tap to_arrow_adc 'frame/traces/wc.trace.charge'
echo "signal frame:"
check_tap to_arrow_sig 'frame/traces/wc.trace.charge'

if [ "$fail" -ne 0 ]; then
    echo "----------------------------------------------------------------"
    echo "h5ls (first 60 lines):"
    printf '%s\n' "$h5_contents" | head -60
    exit 1
fi

echo "----------------------------------------------------------------"
echo "MULTI-EVENT FULL-CHAIN TEST PASSED: $nevents events x 4 taps"
echo "  (initial depos + drifted depos + ADC + sigproc) -> HDF5."
echo "view with: adove gui $h5"
