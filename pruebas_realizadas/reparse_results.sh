#!/usr/bin/env bash
set -euo pipefail

OUT='pruebas_realizadas/resultados_raw.tsv'
RAW='pruebas_realizadas/raw'

echo -e "test_id\tdescripcion\talfabeto\tlongitud\ttipo\tpassword\thash\tprograma\tencontrado\tintentos\ttiempo_s\tmh_s" > "$OUT"

append_row() {
  local test_id="$1" descripcion="$2" alfabeto="$3" longitud="$4" tipo="$5" password="$6" hash="$7" prog="$8" file="$9"

  local found attempts time mhs
  local normalized
  normalized=$(mktemp)
  tr '\r' '\n' < "$file" > "$normalized"

  if grep -q '¡HASH CRACKEADO!' "$normalized"; then found='si'; else found='no'; fi
  attempts=$(grep -E '^  Intentos: [0-9]+' "$normalized" | tail -n1 | awk '{print $2}')
  time=$(grep -E '^  Tiempo total: [0-9]+(\.[0-9]+)? segundos$' "$normalized" | tail -n1 | awk '{print $3}')

  if [[ "$prog" == 'CPU' ]]; then
    mhs=$(grep -E '^  Velocidad: [0-9]+(\.[0-9]+)? MH/s' "$normalized" | tail -n1 | awk '{print $2}')
  else
    mhs=$(grep -E '^  Velocidad media: [0-9]+(\.[0-9]+)? MH/s$' "$normalized" | tail -n1 | awk '{print $3}')
  fi

  rm -f "$normalized"
  echo -e "${test_id}\t${descripcion}\t${alfabeto}\t${longitud}\t${tipo}\t${password}\t${hash}\t${prog}\t${found}\t${attempts}\t${time}\t${mhs}" >> "$OUT"
}

append_row T1 'num len6 encontrado' num 6 encontrado 654321 c33367701511b4f6020ec61ded352059 CPU "$RAW/T1_cpu.txt"
append_row T1 'num len6 encontrado' num 6 encontrado 654321 c33367701511b4f6020ec61ded352059 GPU "$RAW/T1_gpu.txt"
append_row T2 'num len6 no_encontrado (hash de abcdef)' num 6 no_encontrado abcdef e80b5017098950fc58aad83c8c14978e CPU "$RAW/T2_cpu.txt"
append_row T2 'num len6 no_encontrado (hash de abcdef)' num 6 no_encontrado abcdef e80b5017098950fc58aad83c8c14978e GPU "$RAW/T2_gpu.txt"
append_row T3 'lower len5 encontrado' lower 5 encontrado amigo d94729ce13f4ee6395bfc6f1080cc986 CPU "$RAW/T3_cpu.txt"
append_row T3 'lower len5 encontrado' lower 5 encontrado amigo d94729ce13f4ee6395bfc6f1080cc986 GPU "$RAW/T3_gpu.txt"
append_row T4 'lower len5 no_encontrado (hash de amigo1)' lower 5 no_encontrado amigo1 6a0200fb6c5a16966766a660df7f5cde CPU "$RAW/T4_cpu.txt"
append_row T4 'lower len5 no_encontrado (hash de amigo1)' lower 5 no_encontrado amigo1 6a0200fb6c5a16966766a660df7f5cde GPU "$RAW/T4_gpu.txt"
append_row T5 'alnum len6 encontrado' alnum 6 encontrado zzzz00 6e7c381877a55d80afe68cb1e9bf1ad5 CPU "$RAW/T5_cpu.txt"
append_row T5 'alnum len6 encontrado' alnum 6 encontrado zzzz00 6e7c381877a55d80afe68cb1e9bf1ad5 GPU "$RAW/T5_gpu.txt"
append_row T6 'alnum len4 no_encontrado (hash de abcde)' alnum 4 no_encontrado abcde ab56b4d92b40713acc5af89985d4b786 CPU "$RAW/T6_cpu.txt"
append_row T6 'alnum len4 no_encontrado (hash de abcde)' alnum 4 no_encontrado abcde ab56b4d92b40713acc5af89985d4b786 GPU "$RAW/T6_gpu.txt"

echo 'OK'
