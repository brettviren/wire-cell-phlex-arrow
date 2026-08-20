// wire-cell-phlex-arrow/test/smoke-imaging-pdhd.jsonnet
//
// Standalone 3D-imaging smoke (ddm-3bu.6): exercise the imaging island
// (wcph_frame_to_blobsets) + wc.blobs Arrow schema + convert path end-to-end,
// minimally and without edep-sim/Geant4.
//
//   edp_line_gen            one ideal ionization line in PDHD APA0 drift volume
//     -> wire_cell_phlex_arrow_edep_segments   Arrow segments -> WCT TrackSegmentSet
//     -> wcph_tracksegmentset_to_deposet       sample depos (quanta)
//     -> wcph_deposet_to_frame (splat)         DepoFluxSplat "true" frame
//     -> wcph_frame_to_blobsets (img, sum)     charge>0 slicing -> vector<IBlobSet>
//     -> wire_cell_phlex_arrow_convert         wc.frame (splat) + wc.blobs
//     -> phlex_arrow_hdf_output                imaging-smoke.h5
//
// The splat frame is noise-free ideal true signal, so SumSlices (charge>0,
// slicer='sum') tiles it into blobs with no gauss/wiener/error/summary needed.
//
// Run with test/run-imaging-smoke.sh (sets PHLEX_PLUGIN_PATH/WIRECELL_PATH/GODEBUG).
// No jsonnet imports at top level, so it runs under `phlex -c` directly.

local deg = 3.141592653589793 / 180.0;
local det = 'pdhd';
local ai = '0';

{
  driver: {
    cpp: 'generate_layers',
    layers: { event: { parent: 'job', total: 1, starting_number: 0 } },
  },

  sources: {
    lines: {
      cpp: 'edp_line_gen',
      output_layer: 'event',
      center: [-1000.0, 2000.0, 1000.0],  // mm, inside PDHD anode-0 drift volume
      length: 500.0,                       // mm
      theta_y: [90 * deg],
      theta_xz: [0 * deg],
      coords: 'global',
    },
  },

  modules: {
    segs: {
      cpp: 'wire_cell_phlex_arrow_edep_segments',
      input_layer: 'event',
      input_creator: 'input',
      input_suffix: 'observables',
    },

    sampler: {
      cpp: 'wcph_tracksegmentset_to_deposet',
      inputs: [{ creator: 'segs', layer: 'event', suffix: 'tracksegmentset' }],
      outputs: [{ suffix: 'deposet' }],
      wct_config: 'tracksegmentset-sampler.jsonnet',
      wct_plugins: ['WireCellGen', 'WireCellPgraph'],
      wct_tla: { ionization: 'quanta' },
    },

    // DepoFluxSplat "true" frame (input='deposet': drifts internally).
    splat: {
      cpp: 'wcph_deposet_to_frame',
      inputs: [{ creator: 'sampler', layer: 'event', suffix: 'deposet' }],
      outputs: [{ suffix: 'frame' }],
      wct_config: 'dune/wct/job/splat.jsonnet',
      wct_plugins: ['WireCellGen', 'WireCellSigProc', 'WireCellAux', 'WireCellPgraph'],
      wct_tla: { detector: det, anode_index: ai, input: 'deposet' },
    },

    // Imaging island: true frame -> vector<IBlobSet> (charge>0 slicing).
    img: {
      cpp: 'wcph_frame_to_blobsets',
      inputs: [{ creator: 'splat', layer: 'event', suffix: 'frame' }],
      outputs: [{ suffix: 'blobs' }],
      wct_config: 'dune/wct/job/img.jsonnet',
      wct_plugins: ['WireCellGen', 'WireCellImg', 'WireCellAux', 'WireCellPgraph'],
      wct_tla: { detector: det, anode_index: ai, slicer: 'sum' },
    },

    // Arrow taps + HDF5 persistence.
    a_splat: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'splat',
      types: ['frame'],
    },
    a_img: {
      cpp: 'wire_cell_phlex_arrow_convert',
      input_layer: 'event',
      input_creator: 'img',
      types: ['blobs'],
    },
    hdf_out: {
      cpp: 'phlex_arrow_hdf_output',
      output_file: 'imaging-smoke.h5',
    },
  },
}
