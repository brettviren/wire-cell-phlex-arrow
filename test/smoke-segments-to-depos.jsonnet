{
  // Segment-sampler chain smoke test (xerosere ddm-69y.5):
  //
  //   hmp_gen_event_gun     1 GeV mu- as HepMC3::GenEvent
  //   esp_tracking          edep-sim/Geant4 -> TG4Event
  //   esp_observables       TG4Event -> edep.observables TableGroup
  //   segments_to_tracksegmentset  (this package) edep.segments -> wcphlex::TrackSegmentSet
  //   sampler               wcph_tracksegmentset_to_deposet: WCT graph running
  //                         Gen::TrackSegmentSampler (recombination mode)
  //   deposet_observer      asserts a non-null IDepoSet per event
  //   to_arrow_*  + hdf_out persist wc.tracksegmentset AND wc.deposet to HDF5
  //
  // Requires WIRECELL_PATH to include wire-cell-phlex/cfg (the sampler WCT
  // graph) and the WCT share/wirecell (wirecell.jsonnet); see run-smoke.sh.

  stage: 'smoke-segments-to-depos',  // the job's stage name (required since Phlex 0.4)
  driver: {
    cpp: 'generate_layers',
    layers: {
      event: { parent: 'job', total: 2, starting_number: 0 },
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
      position: [0, 0, -2500],
      number: 1,
      momentum_unit: 'MeV',
      length_unit: 'mm',
    },
  },
  modules: {
    edep_sim_tracking: {
      cpp: 'esp_tracking',
      input_layer: 'event',
      // Hard-coded path per the sibling edep-sim-phlex smoke convention
      // (host-specific test paths are tracked by ddm-iuc).
      gdml: '/home/bviren/dune/xerosere/devel/edep-sim/inputs/example.gdml',
    },
    edep_observables: {
      cpp: 'esp_observables',
      input_layer: 'event',
      input_from: 'edep_sim_tracking',
    },
    segments_to_tracksegmentset: {
      cpp: 'wire_cell_phlex_arrow_edep_segments',
      input_layer: 'event',
      // input_creator defaults to 'edep_observables', input_suffix to 'observables'
    },
    sampler: {
      cpp: 'wcph_tracksegmentset_to_deposet',
      wct_config: 'tracksegmentset-sampler.jsonnet',
      wct_plugins: ['WireCellGen', 'WireCellPgraph'],
      inputs: [{ creator: 'segments_to_tracksegmentset', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'deposet' }],
    },
    deposet_observer: {
      cpp: 'wcph_deposet_observer',
      input_layer: 'event',
      input_from: 'sampler',
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
      output_file: 'segments-to-depos.h5',
    },
  },
}
