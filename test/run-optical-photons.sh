#!/usr/bin/env bash
#
# Optical-photon + ionization test (xerosere, edep-sim issue #99 follow-up).
#
# Companion to run-efield-quanta-fullchain.sh.  That test proves the drift field
# drives the ionization split; this one additionally proves edep-sim's
# OPTICAL-PHOTON path is alive.  It fires a 10 MeV electron into a small
# scintillating-LAr geometry (optical-lar.gdml) and checks the edep.observables
# hold BOTH:
#   * ionization electrons  (segments n_electrons, field-driven), AND
#   * detected optical photons (photons table, TG4PhotonHit on a SurfaceDetector).
#
# WHY A SEPARATE, PURPOSE-BUILT GEOMETRY: the pdhd full-chain shows ZERO photons
# not because of any bug but because (a) the dunecore GDML defines no
# scintillation optical properties and no SurfaceDetector volume, and (b)
# edep-sim's defaults disable optical-photon STACKING
# (/process/optical/scintillation/setStackPhotons false) and the boundary SD.
# Here optical-lar.gdml supplies the optical properties + a photon-detector
# plate, and the job's `macro` re-enables stacking and boundary SD invocation.
# A low-energy electron keeps the (slow) Geant4 photon transport cheap.
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

gdml="$here/optical-lar.gdml"
if [ ! -s "$gdml" ]; then
    echo "OPTICAL TEST FAILED: geometry not found: $gdml"
    exit 1
fi

workdir="${1:-$(mktemp -d)}"
mkdir -p "$workdir"
echo "workdir: $workdir"
cd "$workdir"

sed "s|@GDML@|$gdml|" "$here/smoke-optical-photons.jsonnet" > "$workdir/job.jsonnet"

"$view/bin/phlex" -c "$workdir/job.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/optical-photons.h5"
if [ ! -s "$h5" ]; then
    echo "OPTICAL TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

echo "----------------------------------------------------------------"
if ! ( cd "$root/python/adove" && uv run --quiet python "$here/check-optical-photons.py" "$h5" ); then
    echo "OPTICAL TEST FAILED: photon+electron check did not pass"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "OPTICAL TEST PASSED: 10 MeV e- in scintillating LAr produced BOTH detected"
echo "optical photons AND a physical, field-driven ionization split.  (edep-sim #99)"
