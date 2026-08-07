{
  // SPLIT full-chain smoke + post-drift depos (xerosere ddm-0hk): the
  // smoke-fullchain-pdhd-split.jsonnet graph (sim island -> ADC Frame, sigproc
  // island -> signal Frame) with an ADDED third, lightweight island that taps
  // the DRIFTED depos — the depos DepoTransform consumes to make the ADC — and
  // writes them to the same HDF5:
  //
  //   hmp_gen_event_gun -> esp_tracking (protodunehd_v8 GDML) -> esp_observables
  //   -> edep_segments_to_tracksegmentset
  //   -> depo_drift    (wcph_tracksegmentset_to_deposet, dune/wct/job/drift.jsonnet:
  //                     TrackSegmentSampler -> DepoSetDrifter)  => DepoSet product
  //   -> frame_sim     (wcph_tracksegmentset_to_frame, dune/wct/job/sim.jsonnet:
  //                     TrackSegmentSampler -> drift -> DepoTransform -> Reframer
  //                     -> AddNoise -> Digitizer)               => ADC Frame product
  //   -> frame_sigproc (wcph_frame_filter, dune/wct/job/sigproc.jsonnet:
  //                     OmnibusSigProc)                         => signal Frame product
  //
  // The DepoSet AND both Frames are converted to wc.deposet / wc.frame
  // TableGroups (to_arrow_depo / to_arrow_adc / to_arrow_sig) and written to one
  // HDF5, so the adove display can overlay the drifted-depo truth against the
  // ADC-level and signal-processed waveforms.
  //
  // The depo_drift island uses its OWN service_prefix ("drift_") so it gets a
  // fresh, independently-seeded rng.  Because that rng is the drifter's only
  // consumer, its drift draws match frame_sim's own fresh-rng drift draws, so
  // the persisted depos are exactly those frame_sim drifted internally (drift
  // fluctuation is on) — without perturbing frame_sim's shared bare-name rng.

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
    // Island 0: sampler + drift only, tapping the post-drift depos.  Its own
    // service_prefix keeps its rng independent of (yet reproducing) frame_sim's.
    depo_drift: {
      cpp: 'wcph_tracksegmentset_to_deposet',
      wct_config: 'dune/wct/job/drift.jsonnet',
      wct_plugins: ['WireCellPgraph', 'WireCellGen', 'WireCellAux'],
      inputs: [{ creator: 'segments_to_tracksegmentset', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'deposet' }],
      wct_tla: {
        detector: 'pdhd',
        anode_index: '0',
        input: 'tracksegmentset',
        service_prefix: 'drift_',
      },
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
    // Arrow conversions: the drifted DepoSet AND both frames go to HDF5.
    to_arrow_depo: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'depo_drift',
      types: ['deposet'],
    },
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
      output_file: 'fullchain-pdhd-split-depos.h5',
    },
  },
}
