# Tutorial PDF: An Open Bitstream Pipeline for the ALINX AX7020
#
#   make          build both PDFs (English and Simplified Chinese)
#   make en       build ax7020-open-bitstream-pipeline.pdf only
#   make zh       build ax7020-open-bitstream-pipeline-zh.pdf only
#   make watch    rebuild the English PDF on every change (latexmk -pvc)
#   make clean    remove build artefacts, keep the PDFs
#   make distclean  remove everything including the PDFs
#
# Needs: texlive with xelatex, latexmk, fontspec, fontawesome5, tcolorbox,
# xeCJK (for the Chinese version) and the Inter and JetBrains Mono fonts
# installed system-wide (Debian: fonts-inter, fonts-jetbrains-mono), plus
# Noto Sans CJK SC for the Chinese version (Debian: fonts-noto-cjk).

DOC     := ax7020-open-bitstream-pipeline
DOCZH   := $(DOC)-zh
AVATAR  := avatar.jpg
LATEXMK := latexmk -xelatex -interaction=nonstopmode -halt-on-error -file-line-error

.PHONY: all en zh watch clean distclean check-fonts check-fonts-cjk

all: $(DOC).pdf $(DOCZH).pdf

en: $(DOC).pdf

zh: $(DOCZH).pdf

$(DOC).pdf: $(DOC).tex $(AVATAR) | check-fonts
	$(LATEXMK) $(DOC).tex

$(DOCZH).pdf: $(DOCZH).tex $(AVATAR) | check-fonts check-fonts-cjk
	$(LATEXMK) $(DOCZH).tex

$(AVATAR):
	@echo "missing $(AVATAR): copy the author photo here (e.g. from the blog repo, slides/Avatar.jpg)" >&2; exit 1

check-fonts:
	@fc-list | grep -qi 'Inter' || { echo "font 'Inter' not installed" >&2; exit 1; }
	@fc-list | grep -qi 'JetBrains Mono' || { echo "font 'JetBrains Mono' not installed" >&2; exit 1; }

check-fonts-cjk:
	@fc-list | grep -qi 'Noto Sans CJK SC' || { echo "font 'Noto Sans CJK SC' not installed (Debian: fonts-noto-cjk)" >&2; exit 1; }
	@fc-list | grep -qi 'Noto Sans Mono CJK SC' || { echo "font 'Noto Sans Mono CJK SC' not installed (Debian: fonts-noto-cjk)" >&2; exit 1; }

watch: $(AVATAR) | check-fonts
	$(LATEXMK) -pvc $(DOC).tex

clean:
	latexmk -c $(DOC).tex 2>/dev/null || true
	latexmk -c $(DOCZH).tex 2>/dev/null || true
	rm -f $(DOC).xdv $(DOCZH).xdv

distclean: clean
	rm -f $(DOC).pdf $(DOCZH).pdf
