{
  // GDML-fix + quanta-mode variant of the full-chain smoke
  // (xerosere ddm-496 / edep-sim issue #99).  Driven by run-quanta-fullchain.sh.
  //
  //   hmp_gen_event_gun     1 GeV mu+ fired through the PDHD APA0 drift volume
  //   esp_tracking          edep-sim/Geant4 -> TG4Event, using a PREPROCESSED
  //                         protodunehd_v8 GDML (@GDML@) whose scalar LArSoft
  //                         "Efield" auxiliaries were rewritten to edep-sim
  //                         "EField" vectors, so edep-sim REGISTERS the drift
  //                         field and produces a PHYSICAL ionization split.
  //   esp_observables       TG4Event -> edep.observables (segments carry the
  //                         quanta split: energy_deposit, n_photons, n_electrons)
  //   segments_to_tracksegmentset   edep.segments -> wcphlex::TrackSegmentSet
  //   sampler               wcph_tracksegmentset_to_deposet running
  //                         Gen::TrackSegmentSampler in "quanta" mode: it takes
  //                         n_electrons DIRECTLY from the segment and applies NO
  //                         recombination model, so the electrons it emits are
  //                         exactly edep-sim's split.
  //   to_arrow_* + hdf_out  persist edep.observables + wc.tracksegmentset +
  //                         wc.deposet to HDF5.
  //
  // The @GDML@ token is substituted by run-quanta-fullchain.sh with the path of
  // the preprocessed GDML written into the test workdir.

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
      gdml: '@GDML@',  // preprocessed protodunehd_v8 (vector EField auxiliaries)
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
      output_file: 'quanta-pdhd.h5',
    },
  },
}
