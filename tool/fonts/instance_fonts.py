"""Gera as fontes estáticas de assets/fonts/ a partir das variáveis do
google/fonts (licença OFL, em assets/fonts/OFL-*.txt).

O Flutter não aplica o eixo wght de uma fonte variável a partir de
FontWeight, por isso guardam-se instâncias fixas.

  python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools==4.55.0
  curl -fsSL -o 'Manrope[wght].ttf' 'https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope%5Bwght%5D.ttf'
  /tmp/ft/bin/python tool/fonts/instance_fonts.py <pasta dos ttf> assets/fonts
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

NAMES = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}
JOBS = [
    ("Manrope[wght].ttf", "Manrope", {}, [400, 500, 600, 700]),
]

src, out = Path(sys.argv[1]), Path(sys.argv[2])
for file, family, fixed, weights in JOBS:
    for w in weights:
        font = instantiateVariableFont(
            TTFont(src / file), {**fixed, "wght": w}, updateFontNames=False)
        font.save(out / f"{family}-{NAMES[w]}.ttf")
        print(f"{family}-{NAMES[w]}.ttf")
