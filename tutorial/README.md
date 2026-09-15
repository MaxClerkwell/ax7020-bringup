# Tutorial: An Open Bitstream Pipeline for the ALINX AX7020

The clean path through the whole project as one document: every command in
the order it is needed, a checkpoint after each step, and the few rules you
cannot get through without. No detours; those are in the
[article series](https://maxclerkwell.tech/alinx/).

| File | |
|---|---|
| `ax7020-open-bitstream-pipeline.pdf` | English, 17 pages |
| `ax7020-open-bitstream-pipeline-zh.pdf` | Simplified Chinese |
| `ax7020-open-bitstream-pipeline.tex`, `-zh.tex` | LaTeX sources |
| `Makefile` | `make` builds both, `make zh` only the Chinese one |

Build needs XeLaTeX (`latexmk`), the Inter and JetBrains Mono fonts, and a
CJK font for the Chinese edition (see the Makefile's font check).

## Licence

Unlike the code in this repository (GPL-2.0), the tutorial documents in this
directory are licensed under
[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/):
use, share and adapt them freely, as long as you credit
**Stephan Bökelmann (MaxClerkwell)** and link to <https://maxclerkwell.tech/alinx/>.
