{
  // FULL-CHAIN smoke (xerosere ddm-69y.7), PDHD, single anode:
  //
  //   hmp_gen_event_gun -> esp_tracking (protodunehd_v8 GDML) -> esp_observables
  //   -> edep_segments_to_tracksegmentset
  //   -> wcph_tracksegmentset_to_frame (WCT: TrackSegmentSampler -> drift ->
  //      sim -> sigproc, dune/wct/job/sim-sigproc.jsonnet input=tracksegmentset)
  //   -> wc.frame TableGroup -> HDF5.
  //
  // The gun fires along +z through the TPC actives at y=200cm (inside the
  // PDHD active volume); anode_index selects which APA's frame is simulated.

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
    frame_sim_sigproc: {
      cpp: 'wcph_tracksegmentset_to_frame',
      wct_config: 'dune/wct/job/sim-sigproc.jsonnet',
      wct_plugins: ['WireCellPgraph', 'WireCellGen', 'WireCellSigProc', 'WireCellAux'],
      inputs: [{ creator: 'segments_to_tracksegmentset', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'frame' }],
      wct_tla: {
        detector: 'pdhd',
        anode_index: '0',
        input: 'tracksegmentset',
      },
    },
    to_arrow_frame: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'frame_sim_sigproc',
      types: ['frame'],
    },
    hdf_out: {
      cpp: 'phlex_arrow_hdf_output',
      output_file: 'fullchain-pdhd.h5',
    },
  },
}
