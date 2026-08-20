#!/usr/bin/env bash
#
# test/run-imaging-smoke.sh — standalone 3D-imaging smoke test (ddm-3bu.6).
#
# Runs smoke-imaging-pdhd.jsonnet: edp_line_gen -> segments -> sampler ->
# DepoFluxSplat "true" frame -> wcph_frame_to_blobsets (img, slicer=sum) ->
# wire_cell_phlex_arrow_convert types=['blobs'] -> phlex_arrow_hdf_output, then
# asserts imaging-smoke.h5 holds a NON-EMPTY wc.blobs table (plus the splat frame).
#
# Success is judged by the OUTPUT (HDF5 contents), not phlex's exit code.
#
# Exit codes: 0 = pass, 1 = failure, 77 = skipped (env/build not present).

set -uo pipefail

SKIP=77
name="imaging-smoke"

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

say()  { echo "[$name] $*" >&2; }
skip() { say "SKIP: $*"; exit "$SKIP"; }
die()  { say "ERROR: $*"; exit 1; }

view="$root/extern/envs/gcc15/view"
install="$root/installs/envs/gcc15"
builds="$root/builds/envs/gcc15"

phlex="$view/bin/phlex"
h5ls="$view/bin/h5ls"

# --- required artifacts (skip cleanly if the env/build is not present) --------
[ -x "$phlex" ]                                             || skip "phlex not found ($phlex)"
[ -e "$builds/edep-phlex/libedp_line_gen.so" ]             || skip "edep-phlex not built"
[ -e "$builds/wire-cell-phlex/libwcph_frame_to_blobsets.so" ] || skip "imaging island (wcph_frame_to_blobsets) not built"
[ -e "$builds/wire-cell-phlex-arrow/libwire_cell_phlex_arrow_convert.so" ] || skip "wire-cell-phlex-arrow not built"
[ -e "$install/lib/libphlex_arrow_hdf_output.so" ]         || skip "phlex-arrow-hdf not installed"
[ -d "$root/reference/wire-cell-data" ]                    || skip "wire-cell-data not present"

export PHLEX_PLUGIN_PATH="$builds/edep-phlex:$builds/wire-cell-phlex:$builds/wire-cell-phlex-arrow:$install/lib:$view/lib"
export LD_LIBRARY_PATH="$builds/edep-phlex:$install/lib:$install/lib64:$view/lib:$view/lib64:${LD_LIBRARY_PATH:-}"
export WIRECELL_PATH="$root/devel/wire-cell-phlex/cfg:$root/reference/wire-cell-data:$install/share/wirecell:$view/share/wirecell"
export GODEBUG="${GODEBUG:+$GODEBUG,}asyncpreemptoff=1"

workdir="$(mktemp -d)"
say "workdir: $workdir"
cd "$workdir" || die "cannot cd $workdir"

out="$workdir/imaging-smoke.h5"
"$phlex" -c "$here/smoke-imaging-pdhd.jsonnet" > phlex.log 2>&1 || true
grep -iE 'error|what\(\)|throw|abort' phlex.log | head -8 >&2 || true

[ -s "$out" ] || { say "no HDF5 output produced"; tail -30 phlex.log >&2; die "FAILED"; }

say "## h5ls -r $out"
listing="$("$h5ls" -r "$out" 2>/dev/null)"
echo "$listing" >&2

have() { printf '%s\n' "$listing" | grep -q "$1" || die "missing $1"; }

# The splat "true" frame and a wc.blobs table must both be present.
have "/a_splat/.*/frame/traces/wc.trace.charge Dataset"
have "/a_img/.*/blobs/blobs/wc.blob.value Dataset"

# Non-empty: the wc.blob.value dataset dimension must be > 0 (a blob was tiled).
# h5ls prints the row count as "Dataset {N}"; an empty table shows "{0}".
value_line="$(printf '%s\n' "$listing" | grep -E '/a_img/.*/blobs/blobs/wc.blob.value Dataset' | head -1)"
[ -n "$value_line" ] || die "no wc.blob.value dataset found"
nblob="$(printf '%s\n' "$value_line" | grep -oE '\{[0-9]+\}' | grep -oE '[0-9]+' | head -1)"
say "wc.blobs rows (blobs tiled): ${nblob:-?}"
[ "${nblob:-0}" -gt 0 ] || die "wc.blobs table is EMPTY (0 blobs tiled) — imaging produced no blobs"

say "PASS"
exit 0
