#!/usr/bin/env python3
"""Rewrite a LArSoft/dunecore GDML into an edep-sim-consumable one.

edep-sim registers a drift E-field only from a GDML <auxiliary> whose auxtype
is exactly "EField" (case-sensitive) carrying a VECTOR value "(x, y, z) unit"
(see edep-sim src/EDepSimUserDetectorConstruction.cc).  dunecore/LArG4 GDML
instead uses the LArSoft convention auxtype="Efield" (lower-case f) with a
SCALAR magnitude "<N>*V/cm".  edep-sim silently ignores that, falls back to the
zero-field G4EmSaturation branch, and yields ~0 ionization electrons (see
xerosere ddm-496 and edep-sim issue #99).

This maps every scalar "Efield" auxiliary onto the edep-sim "EField" vector
convention, placing the magnitude on the drift axis (X for PDHD/PDVD).  Only
the field MAGNITUDE enters edep-sim's Doke-Birks recombination, so the axis
choice does not change the ionization result.  Both the input and output are
fully GDML-schema-valid: <auxiliary> is a generic string extension point and
GDML has no field concept, so this is a consumer-convention translation, not a
compliance fix.
"""
import re
import sys

# Matches e.g.  <auxiliary auxtype="Efield" auxunit="V/cm" auxvalue="500*V/cm"/>
# (auxunit optional; attribute order per the dunecore GDML writer).
_AUX = re.compile(
    r'<auxiliary\s+auxtype="Efield"\s+(?:auxunit="[^"]*"\s+)?auxvalue="([^"]*)"\s*/>'
)


def _magnitude_vcm(value):
    """Extract the leading numeric magnitude (in V/cm) from a scalar auxvalue.

    Accepts the "500*V/cm" and "500 V/cm" spellings; the unit is assumed V/cm
    (matching the LArSoft convention and the auxunit attribute)."""
    m = re.match(r'\s*([-+0-9.eE]+)', value.replace('*', ' '))
    if not m:
        raise ValueError("cannot parse Efield magnitude from %r" % value)
    return float(m.group(1))


def convert(text, axis='x'):
    comp = {'x': '(%g V/cm, 0 V/cm, 0 V/cm)',
            'y': '(0 V/cm, %g V/cm, 0 V/cm)',
            'z': '(0 V/cm, 0 V/cm, %g V/cm)'}[axis]

    def repl(m):
        mag = _magnitude_vcm(m.group(1))
        return '<auxiliary auxtype="EField" auxvalue="%s"/>' % (comp % mag)

    return _AUX.subn(repl, text)


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: fix-gdml-efield.py IN.gdml OUT.gdml")
    with open(argv[1]) as fp:
        src = fp.read()
    out, n = convert(src)
    with open(argv[2], 'w') as fp:
        fp.write(out)
    print("fix-gdml-efield: converted %d scalar 'Efield' -> vector 'EField' auxiliaries" % n)
    if n == 0:
        sys.exit("ERROR: no scalar Efield auxiliaries found to convert")


if __name__ == '__main__':
    main(sys.argv)
