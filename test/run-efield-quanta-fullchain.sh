#!/usr/bin/env bash
#
# E-field quanta-mode full-chain test (xerosere ddm-496 / edep-sim issue #99).
#
# This is the "the fix is in" test: it proves that edep-sim now registers the
# drift E-field from the ORIGINAL, UNMODIFIED LArSoft/dunecore GDML (scalar
# "Efield" auxiliaries) and produces a PHYSICAL ionization/scintillation split,
# which the WCT TrackSegmentSampler then carries through unchanged in "quanta"
# mode.
#
# Contrast run-quanta-fullchain.sh, the predecessor, which had to PRE-PROCESS
# the GDML (scalar "Efield" -> vector "EField") AND still only saw a ~0 split
# (its check tolerated that "known gap").  Here there is NO preprocessing and
# the check HARD-fails unless the ionization fraction is physical.  The three
# edep-sim fixes this exercises (all in devel/edep-sim):
#   1. EDepSimUserDetectorConstruction: parse scalar "Efield"/"EfieldDir".
#   2. EDepSimDokeBirksSaturation: accept the dunecore LAr material (its GDML
#      omits the liquid state, so Geant4 imports it as solid) instead of
#      bailing to the field-independent base model.
#   3. EDepSimDokeBirksSaturation: fall back cleanly (no NaN) in volumes with
#      no/zero registered field.
#
# It (1) runs gun -> edep-sim -> observables -> sampler(quanta) -> depos,
# persisting the edep.observables segments AND the WCT deposet to HDF5; and
# (2) CHECKS that quanta are conserved and finite, that the field-driven
# ionization fraction is in the physical MIP range, and that the WCT sampler
# passed edep-sim's electron count through unchanged (quanta passthrough).
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

# The ORIGINAL dunecore GDML: scalar LArSoft "Efield" auxiliaries, consumed
# as-is (no scalar->vector rewrite).
src_gdml="$root/reference/dunecore/dunecore/Geometry/gdml/protodunehd_v8_refactored_nowires.gdml"
if [ ! -s "$src_gdml" ]; then
    echo "E-FIELD QUANTA TEST FAILED: reference GDML not found: $src_gdml"
    exit 1
fi

workdir="${1:-$(mktemp -d)}"
mkdir -p "$workdir"
echo "workdir: $workdir"
cd "$workdir"

# Point the job config at the unmodified GDML (no preprocessing step).
sed "s|@GDML@|$src_gdml|" "$here/smoke-efield-quanta-pdhd.jsonnet" > "$workdir/job.jsonnet"

# Run the chain.
"$view/bin/phlex" -c "$workdir/job.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/efield-quanta-pdhd.h5"
if [ ! -s "$h5" ]; then
    echo "E-FIELD QUANTA TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

# Check the field-driven quanta physics (needs h5py+numpy; use the adove uv env).
echo "----------------------------------------------------------------"
if ! ( cd "$root/python/adove" && uv run --quiet python "$here/check-efield-quanta.py" "$h5" ); then
    echo "E-FIELD QUANTA TEST FAILED: field-driven quanta check did not pass"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "E-FIELD QUANTA TEST PASSED: unmodified scalar-Efield GDML -> edep-sim"
echo "registered the drift field -> physical ionization split -> WCT sampler"
echo "carried edep's electrons through in quanta mode.  (ddm-496 / edep-sim #99)"
