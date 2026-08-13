{
  // E-field quanta-mode full-chain smoke (xerosere ddm-496 / edep-sim issue #99).
  // Driven by run-efield-quanta-fullchain.sh.
  //
  // This is the "the fix is in" successor to smoke-quanta-pdhd.jsonnet.  The
  // latter had to PRE-PROCESS the protodunehd_v8 GDML (rewriting the LArSoft
  // scalar "Efield" auxiliaries into edep-sim "EField" vectors) and still only
  // observed a ~0 ionization split.  With the edep-sim fixes landed
  //
  //   1. scalar "Efield"/"EfieldDir" auxiliaries are parsed natively
  //      (EDepSimUserDetectorConstruction),
  //   2. DokeBirks accepts the dunecore LAr material (whose GDML omits the
  //      liquid state) instead of bailing to the field-independent model, and
  //   3. DokeBirks falls back cleanly (no NaN) in volumes with no/zero field,
  //
  // this job consumes the ORIGINAL, UNMODIFIED dunecore GDML (@GDML@) directly:
  // no preprocessing, no vector rewrite.  edep-sim registers the 500 V/cm drift
  // field straight from the scalar auxiliary and produces a PHYSICAL
  // ionization/scintillation split.
  //
  //   hmp_gen_event_gun     1 GeV mu+ fired through the PDHD APA0 drift volume
  //                         (volTPCActiveInner, 500 V/cm)
  //   esp_tracking          edep-sim/Geant4 -> TG4Event, ORIGINAL scalar-Efield
  //                         GDML (@GDML@)
  //   esp_observables       TG4Event -> edep.observables (segments carry the
  //                         quanta split: energy_deposit, n_photons, n_electrons)
  //   segments_to_tracksegmentset   edep.segments -> wcphlex::TrackSegmentSet
  //   sampler               wcph_tracksegmentset_to_deposet running
  //                         Gen::TrackSegmentSampler in "quanta" mode: it takes
  //                         n_electrons DIRECTLY from the segment and applies NO
  //                         recombination model, so the electrons it emits are
  //                         exactly edep-sim's field-driven split.
  //   to_arrow_* + hdf_out  persist edep.observables + wc.tracksegmentset +
  //                         wc.deposet to HDF5.
  //
  // The @GDML@ token is substituted by run-efield-quanta-fullchain.sh with the
  // path of the unmodified reference dunecore GDML.

  driver: {
    cpp: 'generate_layers',
    layers: {
      event: { parent: 'job', total: 1, starting_number: 0 },
    },
  },
  sources: {
    gun: {
      cpp: 'hmp_gen_event_gun',
      output_layer: 'event',
      pdg: 13,
      mass: 105.658,
      energy: 1000.0,
      direction: [0, 0, 1],
      position: [-1000, 2000, 0],  // mm: x in APA0 drift volume, mid-height
      number: 1,
      momentum_unit: 'MeV',
      length_unit: 'mm',
    },
  },
  modules: {
    edep_sim_tracking: {
      cpp: 'esp_tracking',
      input_layer: 'event',
      gdml: '@GDML@',  // ORIGINAL protodunehd_v8 (scalar LArSoft "Efield" auxiliaries)
    },
    edep_observables: {
      cpp: 'esp_observables',
      input_layer: 'event',
      input_from: 'edep_sim_tracking',
    },
    segments_to_tracksegmentset: {
      cpp: 'wire_cell_phlex_arrow_edep_segments',
      input_layer: 'event',
    },
    sampler: {
      cpp: 'wcph_tracksegmentset_to_deposet',
      wct_config: 'tracksegmentset-sampler.jsonnet',
      wct_plugins: ['WireCellGen', 'WireCellPgraph'],
      inputs: [{ creator: 'segments_to_tracksegmentset', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'deposet' }],
      wct_tla: { ionization: 'quanta' },  // take n_electrons from the segment; no recombination model
    },
    to_arrow_segments: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'segments_to_tracksegmentset',
      types: ['tracksegmentset'],
    },
    to_arrow_depos: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'sampler',
      types: ['deposet'],
    },
    hdf_out: {
      cpp: 'phlex_arrow_hdf_output',
      output_file: 'efield-quanta-pdhd.h5',
    },
  },
}
