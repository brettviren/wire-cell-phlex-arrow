{
  // MULTI-EVENT SPLIT full-chain + initial/post-drift depos (xerosere).
  //
  // This is the multi-"event" generalization of smoke-fullchain-pdhd-split-depos.jsonnet.
  // Instead of one fixed muon it drives SIX distinct events from a single
  // GenEventSequence source (hmp_gen_event_sequence), and for EACH event taps
  // and persists FOUR products to one HDF5:
  //
  //   * initial (pre-drift) depos      -- depo_sample  (sample.jsonnet: sampler only)
  //   * post-drift depos               -- depo_drift   (drift.jsonnet:  sampler -> drifter)
  //   * ADC frame                      -- frame_sim    (sim.jsonnet:    ... -> Digitizer)
  //   * signal-processed frame         -- frame_sigproc(sigproc.jsonnet: OmnibusSigProc)
  //
  // Graph (per event N = 0..5):
  //   hmp_gen_event_sequence -> esp_tracking (protodunehd_v8 GDML) -> esp_observables
  //   -> edep_segments_to_tracksegmentset
  //   -> depo_sample   (wcph_tracksegmentset_to_deposet, sample.jsonnet)  => initial DepoSet
  //   -> depo_drift    (wcph_tracksegmentset_to_deposet, drift.jsonnet)   => drifted DepoSet
  //   -> frame_sim     (wcph_tracksegmentset_to_frame,   sim.jsonnet)     => ADC Frame
  //   -> frame_sigproc (wcph_frame_filter,               sigproc.jsonnet) => signal Frame
  //
  // Each product is Arrow-converted (to_arrow_*) and written to one HDF5.  Because
  // the HDF5 address includes each layer cell's number, the six events land in
  // six distinct groups per product (.../event/0/... .../event/5/...): this is
  // the first test exercising phlex multi-"event" execution and multi-event
  // output, so it also serves to shake out bugs there.
  //
  // The six events (kinetic energies):
  //   0: 1000 MeV muon        (the same muon as the single-event split-depos smoke)
  //   1:  100 MeV electron
  //   2: 1000 MeV electron
  //   3:  100 MeV pi-zero     (G4 decays it to 2 gammas -> EM showers)
  //   4: 1000 MeV pi-zero
  //   5: TWO 100 MeV muons overlapping in the readout (see note below)
  //
  // Overlap construction (event 5): two muons share the same transverse (y,z)
  // vertex but muon B is dx = v_drift * dt closer to the anode AND fired dt
  // later.  Since drift time = distance / v_drift, B's shorter drift exactly
  // cancels its later start, so both arrive at the same readout tick; their
  // differing z-directions make the tracks cross at the shared projected vertex.
  //   pdhd v_drift = 1.6 mm/us; choose dt = 250 us  =>  dx = 400 mm.
  //   A: x = -1000 mm, t = 0;    dir [0, 1,  1]
  //   B: x = -1400 mm, t = 250 us; dir [0, 1, -1]
  // (Both x are inside APA0 face-0 drift volume, anode ~ -3521 mm, cathode ~ 0.)

  stage: 'smoke-fullchain-pdhd-multi-events',  // the job's stage name (required since Phlex 0.4)
  driver: {
    cpp: 'generate_layers',
    layers: {
      event: { parent: 'job', total: 6, starting_number: 0 },
    },
  },
  sources: {
    gun: {
      cpp: 'hmp_gen_event_sequence',
      output_layer: 'event',
      momentum_unit: 'MeV',
      length_unit: 'mm',
      events: [
        // 0: 1000 MeV muon (matches the single-event split-depos smoke).
        { particles: [
          { pdg: 13, mass: 105.658, energy: 1000.0, direction: [0, 0, 1], position: [-1000, 2000, 0] },
        ] },
        // 1: 100 MeV electron.
        { particles: [
          { pdg: 11, mass: 0.511, energy: 100.0, direction: [0, 0, 1], position: [-1000, 2000, 0] },
        ] },
        // 2: 1000 MeV electron.
        { particles: [
          { pdg: 11, mass: 0.511, energy: 1000.0, direction: [0, 0, 1], position: [-1000, 2000, 0] },
        ] },
        // 3: 100 MeV pi-zero.
        { particles: [
          { pdg: 111, mass: 134.9768, energy: 100.0, direction: [0, 0, 1], position: [-1000, 2000, 0] },
        ] },
        // 4: 1000 MeV pi-zero.
        { particles: [
          { pdg: 111, mass: 134.9768, energy: 1000.0, direction: [0, 0, 1], position: [-1000, 2000, 0] },
        ] },
        // 5: two overlapping 100 MeV muons (see overlap construction above).
        { particles: [
          { pdg: 13, mass: 105.658, energy: 100.0, direction: [0, 1,  1], position: [-1000, 2000, 2000], time: 0,   time_unit: 'us' },
          { pdg: 13, mass: 105.658, energy: 100.0, direction: [0, 1, -1], position: [-1400, 2000, 2000], time: 250, time_unit: 'us' },
        ] },
      ],
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
    // Island: sampler only, tapping the INITIAL (pre-drift) depos.  Its own
    // service_prefix keeps its component names distinct from the other islands.
    depo_sample: {
      cpp: 'wcph_tracksegmentset_to_deposet',
      wct_config: 'dune/wct/job/sample.jsonnet',
      wct_plugins: ['WireCellPgraph', 'WireCellGen', 'WireCellAux'],
      inputs: [{ creator: 'segments_to_tracksegmentset', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'deposet' }],
      wct_tla: {
        detector: 'pdhd',
        anode_index: '0',
        input: 'tracksegmentset',
        service_prefix: 'sample_',
      },
    },
    // Island: sampler + drift, tapping the POST-DRIFT depos.  Its own
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
    // Island: sampler + drift + detector sim, ending at ADC waveforms.
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
    // Island: signal processing on the ADC Frame from frame_sim.
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
    // Arrow conversions: initial depos, drifted depos, ADC frame, signal frame.
    to_arrow_sampledepo: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'depo_sample',
      types: ['deposet'],
    },
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
      output_file: 'fullchain-pdhd-multi-events.h5',
    },
  },
}
