#!/usr/bin/env python3
"""Verify field-driven quanta physics in an E-field quanta-mode full-chain HDF5.

Reads the edep.observables 'segments' table (edep's field-driven photon/electron
split) and the WCT deposet (the electrons the TrackSegmentSampler emitted in
"quanta" mode) from the HDF5 produced by smoke-efield-quanta-pdhd.jsonnet, and
HARD-checks (all must pass -- this is the test that the E-field handling is now
correct, so there is no "known gap" tolerance):

  1. FINITE: no NaN/Inf in the segment quanta (the DokeBirks LAr path must fall
     back cleanly in zero-field volumes; edep-sim issue #99).
  2. QUANTA CONSERVATION: per segment, n_electrons + n_photons == energy/(19.5 eV).
  3. FIELD IS LIVE: the ionization fraction Sum(n_e)/Sum(n_q) is in the physical
     MIP range (0.40..0.95).  With the drift field unregistered this was ~0; a
     500 V/cm LAr MIP recombines to ~0.7.
  4. QUANTA-MODE PASSTHROUGH: |Sum(depo charge)| == Sum(n_electrons), i.e. the
     WCT sampler carried edep's field-driven electron count through unchanged.

Requires h5py + numpy (run via `uv run --project python/adove`).
"""
import sys
import h5py
import numpy as np

W_QUANTA_MEV = 19.5e-6  # mean energy per quantum in LAr, MeV

# Physical MIP ionization fraction window for a ~500 V/cm LAr drift field.
FRAC_LO, FRAC_HI = 0.40, 0.95


def _find(h5, suffix):
    """Concatenate every dataset whose path ends with `suffix`, over all events."""
    hits = []
    h5.visititems(lambda name, obj: hits.append(name)
                  if isinstance(obj, h5py.Dataset) and name.endswith(suffix) else None)
    if not hits:
        raise KeyError("no dataset path ending in %r" % suffix)
    return np.concatenate([h5[p][:] for p in sorted(hits)]) if len(hits) > 1 else h5[hits[0]][:]


def main(path):
    f = h5py.File(path, 'r')
    energy = _find(f, "observables/segments/energy_deposit")  # MeV
    n_e = _find(f, "observables/segments/n_electrons")
    n_ph = _find(f, "observables/segments/n_photons")
    charge = _find(f, "deposet/wc.depo.charge")  # electrons, negative

    n_q = np.where(energy > 0, energy / W_QUANTA_MEV, 0.0)
    sum_ne, sum_nph, sum_nq = n_e.sum(), n_ph.sum(), n_q.sum()
    frac = sum_ne / sum_nq if sum_nq > 0 else 0.0
    qcharge = abs(charge.sum())

    print("segments=%d  depos=%d" % (len(energy), len(charge)))
    print("Sum n_electrons = %.6g" % sum_ne)
    print("Sum n_photons   = %.6g" % sum_nph)
    print("Sum n_quanta    = %.6g  (Sum energy / 19.5 eV)" % sum_nq)
    print("ionization fraction Sum(n_e)/Sum(n_q) = %.4f" % frac)
    print("|Sum depo charge| (WCT electrons)     = %.6g" % qcharge)

    ok = True

    # 1. FINITE: the field-driven DokeBirks path must not leak NaN/Inf.
    n_bad = int(np.count_nonzero(~np.isfinite(n_e)) + np.count_nonzero(~np.isfinite(n_ph)))
    if n_bad:
        print("FAIL: %d non-finite (NaN/Inf) segment quanta" % n_bad)
        ok = False

    # 2. QUANTA CONSERVATION: per segment, n_e + n_ph == energy/(19.5 eV).
    with np.errstate(divide='ignore', invalid='ignore'):
        resid = np.where(n_q > 0, np.abs(n_e + n_ph - n_q) / n_q, 0.0)
    max_resid = float(np.nanmax(resid)) if len(resid) else 0.0
    print("max per-segment |n_e+n_ph-n_q|/n_q = %.3e" % max_resid)
    if not np.isfinite(max_resid) or max_resid > 1e-6:
        print("FAIL: quanta not conserved (n_e + n_ph != energy/19.5eV)")
        ok = False

    # 3. FIELD IS LIVE: physical MIP ionization fraction.  This is the crux --
    #    it was ~0 while the drift field was unregistered (ddm-496 / #99).
    if FRAC_LO <= frac <= FRAC_HI:
        print("OK: physical MIP ionization fraction %.4f -- drift field is live." % frac)
    else:
        print("FAIL: ionization fraction %.4f outside physical MIP range "
              "[%.2f, %.2f] -- drift field not driving recombination "
              "(the edep-sim E-field handling is not correct)."
              % (frac, FRAC_LO, FRAC_HI))
        ok = False

    # 4. QUANTA-MODE PASSTHROUGH: the WCT TrackSegmentSampler (quanta mode)
    #    emits exactly the segment's electrons, applying no recombination model.
    if abs(qcharge - max(sum_ne, 0.0)) > 1.0 + 1e-4 * abs(sum_ne):
        print("FAIL: WCT depo charge %.6g != edep Sum(n_e) %.6g "
              "(sampler not passing electrons through?)" % (qcharge, sum_ne))
        ok = False

    print("E-FIELD QUANTA CHECK", "PASSED" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
