"""Gera as fontes estáticas de assets/fonts/ a partir das variáveis do
google/fonts (licença OFL, em assets/fonts/OFL-*.txt).

O Flutter não aplica o eixo wght de uma fonte variável a partir de
FontWeight, por isso guardam-se instâncias fixas.

  python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools==4.55.0
  curl -fsSLO 'https://raw.githubusercontent.com/google/fonts/main/ofl/dmsans/DMSans%5Bopsz,wght%5D.ttf'
  curl -fsSLO 'https://raw.githubusercontent.com/google/fonts/main/ofl/fraunces/Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf'
  /tmp/ft/bin/python tool/fonts/instance_fonts.py <pasta dos ttf> assets/fonts
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

NAMES = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}
JOBS = [
    ("DMSans[opsz,wght].ttf", "DMSans", {"opsz": 14}, [400, 500, 600, 700]),
    ("Fraunces[SOFT,WONK,opsz,wght].ttf", "Fraunces",
     {"opsz": 72, "SOFT": 50, "WONK": 0}, [500, 600]),
]

src, out = Path(sys.argv[1]), Path(sys.argv[2])
for file, family, fixed, weights in JOBS:
    for w in weights:
        font = instantiateVariableFont(
            TTFont(src / file), {**fixed, "wght": w}, updateFontNames=False)
        font.save(out / f"{family}-{NAMES[w]}.ttf")
        print(f"{family}-{NAMES[w]}.ttf")
