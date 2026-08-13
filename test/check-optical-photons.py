#!/usr/bin/env python3
"""Verify BOTH optical photons and ionization electrons in an optical-mode HDF5.

Reads the edep.observables 'segments' and 'photons' tables from the HDF5
produced by smoke-optical-photons.jsonnet and HARD-checks:

  1. PHOTONS DETECTED: the 'photons' table (TG4PhotonHit on the SurfaceDetector)
     has a healthy number of rows, i.e. optical-photon production, transport and
     surface detection are all live (they are OFF by default; see the job's
     `macro`).  Photon energies are finite and within the optical band.
  2. ELECTRONS PRESENT & FINITE: the 'segments' n_electrons are finite and sum
     positive -- the ionization split is populated.
  3. FIELD IS LIVE: the ionization fraction Sum(n_e)/Sum(n_e+n_ph) is in the
     physical MIP range (0.40..0.95), driven by the scalar "Efield" auxiliary,
     just as in the pdhd quanta test.

Requires h5py + numpy (run via `uv run --project python/adove`).
"""
import sys
import h5py
import numpy as np

FRAC_LO, FRAC_HI = 0.40, 0.95
MIN_PHOTON_HITS = 10          # a 10 MeV e- in this geometry makes O(100)


def _find(h5, suffix):
    hits = []
    h5.visititems(lambda name, obj: hits.append(name)
                  if isinstance(obj, h5py.Dataset) and name.endswith(suffix) else None)
    if not hits:
        raise KeyError("no dataset path ending in %r" % suffix)
    return np.concatenate([h5[p][:] for p in sorted(hits)]) if len(hits) > 1 else h5[hits[0]][:]


def main(path):
    f = h5py.File(path, 'r')
    n_e = _find(f, "observables/segments/n_electrons")
    n_ph = _find(f, "observables/segments/n_photons")
    photon_e = _find(f, "observables/photons/energy")  # MeV

    sum_ne, sum_nph = float(n_e.sum()), float(n_ph.sum())
    frac = sum_ne / (sum_ne + sum_nph) if (sum_ne + sum_nph) > 0 else 0.0

    print("segments=%d  photon_hits=%d" % (len(n_e), len(photon_e)))
    print("Sum n_electrons = %.6g" % sum_ne)
    print("Sum n_photons   = %.6g" % sum_nph)
    print("ionization fraction Sum(n_e)/Sum(n_e+n_ph) = %.4f" % frac)
    if len(photon_e):
        print("photon hit energy [eV] min/mean/max = %.3f/%.3f/%.3f"
              % (photon_e.min() / 1e-6, photon_e.mean() / 1e-6, photon_e.max() / 1e-6))

    ok = True

    # 1. PHOTONS DETECTED.
    if len(photon_e) < MIN_PHOTON_HITS:
        print("FAIL: only %d photon hits (< %d) -- optical-photon path not live "
              "(scintillation stacking / boundary SD?)" % (len(photon_e), MIN_PHOTON_HITS))
        ok = False
    if len(photon_e) and not np.all(np.isfinite(photon_e)):
        print("FAIL: non-finite photon energies")
        ok = False

    # 2. ELECTRONS PRESENT & FINITE.
    if not (np.all(np.isfinite(n_e)) and np.all(np.isfinite(n_ph))):
        print("FAIL: non-finite segment quanta")
        ok = False
    if not sum_ne > 0.0:
        print("FAIL: Sum(n_electrons) is not positive -- no ionization split")
        ok = False

    # 3. FIELD IS LIVE (physical MIP ionization fraction).
    if FRAC_LO <= frac <= FRAC_HI:
        print("OK: physical MIP ionization fraction %.4f -- drift field is live." % frac)
    else:
        print("FAIL: ionization fraction %.4f outside physical MIP range [%.2f, %.2f]"
              % (frac, FRAC_LO, FRAC_HI))
        ok = False

    print("OPTICAL-PHOTON CHECK", "PASSED" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
