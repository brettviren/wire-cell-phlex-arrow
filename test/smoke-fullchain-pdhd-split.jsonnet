{
  // SPLIT full-chain smoke (xerosere ddm-0hk.1): the run-fullchain.sh WCT
  // graph separated into TWO WCT islands, each run from its own flex node,
  // connected through the Phlex data layer by a Frame product holding the
  // ADC-level IFrame from the sim:
  //
  //   hmp_gen_event_gun -> esp_tracking (protodunehd_v8 GDML) -> esp_observables
  //   -> edep_segments_to_tracksegmentset
  //   -> frame_sim     (wcph_tracksegmentset_to_frame, dune/wct/job/sim.jsonnet:
  //                     TrackSegmentSampler -> drift -> DepoTransform -> Reframer
  //                     -> AddNoise -> Digitizer)           => ADC Frame product
  //   -> frame_sigproc (wcph_frame_filter, dune/wct/job/sigproc.jsonnet:
  //                     OmnibusSigProc)                     => signal Frame product
  //
  // BOTH frames are converted to wc.frame TableGroups (to_arrow_adc /
  // to_arrow_sig) and written to one HDF5, so the adove display can compare
  // the W plane (channels 1600+) at ADC level against the signal-processed
  // gauss/wiener output to localize the apparent corruption (ddm-0hk).
  //
  // The two islands share WCT service components (AnodePlane, DFT, wires,
  // FieldResponse, elec) via bare names (service_prefix default ""), same as
  // wire-cell-phlex test/sim-sigproc-workflow.jsonnet.in.

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
      // Host-specific path per current smoke convention (ddm-iuc).
      gdml: '/home/bviren/dune/xerosere/reference/dunecore/dunecore/Geometry/gdml/protodunehd_v8_refactored_nowires.gdml',
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
    // Island 1: sampler + drift + detector sim, ending at ADC waveforms.
    frame_sim: {
      cpp: 'wcph_tracksegmentset_to_frame',
      wct_config: 'dune/wct/job/sim.jsonnet',
      wct_plugins: ['WireCellPgraph', 'WireCellGen', 'WireCellSigProc', 'WireCellAux'],
      inputs: [{ creator: 'segments_to_tracksegmentset', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'frame' }],
      wct_tla: {
        detector: 'pdhd',
        anode_index: '0',
        input: 'tracksegmentset',
      },
    },
    // Island 2: signal processing on the ADC Frame from island 1.
    frame_sigproc: {
      cpp: 'wcph_frame_filter',
      wct_config: 'dune/wct/job/sigproc.jsonnet',
      wct_plugins: ['WireCellPgraph', 'WireCellGen', 'WireCellSigProc', 'WireCellAux'],
      inputs: [{ creator: 'frame_sim', layer: 'event', suffix: 'frame' }],
      outputs: [{ suffix: 'frame' }],
      wct_tla: {
        detector: 'pdhd',
        anode_index: '0',
      },
    },
    // Arrow conversions: the ADC frame AND the signal frame both go to HDF5.
    to_arrow_adc: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'frame_sim',
      types: ['frame'],
    },
    to_arrow_sig: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'frame_sigproc',
      types: ['frame'],
    },
    hdf_out: {
      cpp: 'phlex_arrow_hdf_output',
      output_file: 'fullchain-pdhd-split.h5',
    },
  },
}
