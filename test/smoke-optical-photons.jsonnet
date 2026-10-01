{
  // Optical-photon + ionization smoke (xerosere, edep-sim issue #99 follow-up).
  // Driven by run-optical-photons.sh.
  //
  // Companion to smoke-efield-quanta-pdhd.jsonnet.  That test shows the drift
  // field drives the IONIZATION split (electrons); this one additionally shows
  // edep-sim's OPTICAL-PHOTON path is alive: a low-energy electron in a small
  // scintillating-LAr geometry (optical-lar.gdml) makes BOTH
  //
  //   * ionization electrons  -> observables 'segments' table (n_electrons),
  //     field-driven via the same scalar "Efield" auxiliary, AND
  //   * detected optical photons -> observables 'photons' table (one row per
  //     TG4PhotonHit on the SurfaceDetector plate).
  //
  //   hmp_gen_event_gun  10 MeV e- fired into the LAr block toward the plate
  //   esp_tracking       edep-sim/Geant4 -> TG4Event, optical-lar.gdml (@GDML@).
  //                      The `macro` re-enables optical-photon STACKING and the
  //                      boundary SD invocation, both of which the edep-sim
  //                      defaults (edepsim-defaults-1.0.mac) turn OFF for speed:
  //                        /process/optical/scintillation/setStackPhotons true
  //                        /process/optical/boundary/setInvokeSD      true
  //                      Without these the geometry is silent on photons (which
  //                      is exactly why the pdhd full-chain runs fast).
  //   esp_observables    TG4Event -> edep.observables (segments + photons)
  //   hdf_out            persist observables to HDF5.
  //
  // Low energy (10 MeV) and a modest scintillation yield keep the optical-photon
  // transport -- which is slow in Geant4 -- cheap.
  //
  // The @GDML@ token is substituted by run-optical-photons.sh with the path of
  // optical-lar.gdml (alongside this file).

  stage: 'smoke-optical-photons',  // the job's stage name (required since Phlex 0.4)
  driver: {
    cpp: 'generate_layers',
    layers: { event: { parent: 'job', total: 1, starting_number: 0 } },
  },
  sources: {
    gun: {
      cpp: 'hmp_gen_event_gun',
      output_layer: 'event',
      pdg: 11,
      mass: 0.511,
      energy: 10.0,
      direction: [1, 0, 0],
      position: [-400, 0, 0],  // mm: inside the LAr block, aimed at the +x plate
      number: 1,
      momentum_unit: 'MeV',
      length_unit: 'mm',
    },
  },
  modules: {
    edep_sim_tracking: {
      cpp: 'esp_tracking',
      input_layer: 'event',
      gdml: '@GDML@',
      // Re-enable optical-photon production+detection (off by default for speed).
      macro: '/process/optical/scintillation/setStackPhotons true\n/process/optical/boundary/setInvokeSD true',
    },
    edep_observables: {
      cpp: 'esp_observables',
      input_layer: 'event',
      input_from: 'edep_sim_tracking',
    },
    hdf_out: {
      cpp: 'phlex_arrow_hdf_output',
      output_file: 'optical-photons.h5',
    },
  },
}
