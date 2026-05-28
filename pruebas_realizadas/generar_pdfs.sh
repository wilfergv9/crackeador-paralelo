#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

latexmk -pdf -interaction=nonstopmode -file-line-error reporte_pruebas.tex
latexmk -pdf -interaction=nonstopmode -file-line-error tabla_resultados_doc.tex
latexmk -pdf -interaction=nonstopmode -file-line-error graficas_pgfplots_doc.tex

echo "PDFs generados:"
ls -lh reporte_pruebas.pdf tabla_resultados_doc.pdf graficas_pgfplots_doc.pdf
