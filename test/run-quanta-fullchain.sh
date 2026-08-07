#!/usr/bin/env bash
#
# GDML-fix + quanta-mode variant of run-fullchain.sh (xerosere ddm-496 /
# edep-sim issue #99).
#
# It (1) PRE-PROCESSES the protodunehd_v8 GDML, rewriting the LArSoft scalar
# "Efield" auxiliaries to edep-sim "EField" vectors so edep-sim registers the
# drift field and produces a PHYSICAL ionization/scintillation split; (2) runs
# gun -> edep-sim -> observables -> sampler(quanta) -> depos, persisting the
# edep.observables segments AND the WCT deposet to HDF5; and (3) CHECKS that the
# photon and electron numbers preserve the quanta relationship
# n_e + n_ph = energy/(19.5 eV), that the field fix moved the ionization
# fraction into the physical MIP range, and that the WCT sampler carried
# edep-sim's electron count through unchanged (quanta passthrough).
#
# Contrast run-fullchain.sh, which runs the sampler in recombination mode and so
# masks the edep-sim split entirely.
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

src_gdml="$root/reference/dunecore/dunecore/Geometry/gdml/protodunehd_v8_refactored_nowires.gdml"

workdir="$(mktemp -d)"
echo "workdir: $workdir"
cd "$workdir"

# (1) Preprocess the GDML: scalar LArSoft "Efield" -> vector edep-sim "EField".
fixed_gdml="$workdir/protodunehd_v8_efield.gdml"
if ! python3 "$here/fix-gdml-efield.py" "$src_gdml" "$fixed_gdml"; then
    echo "QUANTA TEST FAILED: GDML preprocessing failed"
    exit 1
fi

# Point the job config at the preprocessed GDML.
sed "s|@GDML@|$fixed_gdml|" "$here/smoke-quanta-pdhd.jsonnet" > "$workdir/job.jsonnet"

# (2) Run the chain.
"$view/bin/phlex" -c "$workdir/job.jsonnet" > phlex.log 2>&1 || true
grep -iE '\[error\]|what\(\)' phlex.log | head -5 || true

h5="$workdir/quanta-pdhd.h5"
if [ ! -s "$h5" ]; then
    echo "QUANTA TEST FAILED: no HDF5 output produced"
    tail -20 phlex.log
    exit 1
fi

# (3) Check the quanta relationship (needs h5py+numpy; use the adove uv env).
echo "----------------------------------------------------------------"
if ! ( cd "$root/python/adove" && uv run --quiet python "$here/check-quanta.py" "$h5" ); then
    echo "QUANTA TEST FAILED: quanta relationship / field-fix check did not pass"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "QUANTA TEST PASSED: GDML preprocessed, chain ran, quanta conserved"
echo "(n_e + n_ph = E/(19.5 eV)) and the WCT sampler passed edep's electrons"
echo "through in quanta mode.  See the KNOWN GAP note above for whether the"
echo "drift field yet yields a physical (non-zero) ionization split (ddm-496)."
