#!/usr/bin/env bash
set -euo pipefail

REPS=5
OUT='pruebas_realizadas/resultados_repeticiones.tsv'
RAW_DIR='pruebas_realizadas/raw_repeticiones'
mkdir -p "$RAW_DIR"

echo -e "rep\ttest_id\tdescripcion\talfabeto\tlongitud\ttipo\tpassword\thash\tprograma\tencontrado\tintentos\ttiempo_s\tmh_s" > "$OUT"

hash_of() {
  printf "%s" "$1" | md5sum | awk '{print $1}'
}

extract_metrics() {
  local prog="$1"
  local file="$2"
  local normalized
  normalized=$(mktemp)
  tr '\r' '\n' < "$file" > "$normalized"

  local found attempts time mhs
  if grep -q '¡HASH CRACKEADO!' "$normalized"; then found='si'; else found='no'; fi
  attempts=$(grep -E '^  Intentos: [0-9]+' "$normalized" | tail -n1 | awk '{print $2}')
  time=$(grep -E '^  Tiempo total: [0-9]+(\.[0-9]+)? segundos$' "$normalized" | tail -n1 | awk '{print $3}')

  if [[ "$prog" == 'CPU' ]]; then
    mhs=$(grep -E '^  Velocidad: [0-9]+(\.[0-9]+)? MH/s' "$normalized" | tail -n1 | awk '{print $2}')
  else
    mhs=$(grep -E '^  Velocidad media: [0-9]+(\.[0-9]+)? MH/s$' "$normalized" | tail -n1 | awk '{print $3}')
  fi

  rm -f "$normalized"
  echo -e "${found}\t${attempts}\t${time}\t${mhs}"
}

run_case() {
  local rep="$1"
  local test_id="$2"
  local descripcion="$3"
  local alfabeto="$4"
  local longitud="$5"
  local tipo="$6"
  local password="$7"
  local hash="$8"

  local cpu_out="$RAW_DIR/${test_id}_rep${rep}_cpu.txt"
  local gpu_out="$RAW_DIR/${test_id}_rep${rep}_gpu.txt"

  ./secuencial "$hash" "$longitud" "$alfabeto" > "$cpu_out" 2>&1 || true
  ./gpu_crack "$hash" "$longitud" "$alfabeto" brute > "$gpu_out" 2>&1 || true

  IFS=$'\t' read -r cpu_found cpu_attempts cpu_time cpu_mhs < <(extract_metrics CPU "$cpu_out")
  IFS=$'\t' read -r gpu_found gpu_attempts gpu_time gpu_mhs < <(extract_metrics GPU "$gpu_out")

  echo -e "${rep}\t${test_id}\t${descripcion}\t${alfabeto}\t${longitud}\t${tipo}\t${password}\t${hash}\tCPU\t${cpu_found}\t${cpu_attempts}\t${cpu_time}\t${cpu_mhs}" >> "$OUT"
  echo -e "${rep}\t${test_id}\t${descripcion}\t${alfabeto}\t${longitud}\t${tipo}\t${password}\t${hash}\tGPU\t${gpu_found}\t${gpu_attempts}\t${gpu_time}\t${gpu_mhs}" >> "$OUT"
}

P1='654321'; H1=$(hash_of "$P1")
S2='abcdef'; H2=$(hash_of "$S2")
P3='amigo'; H3=$(hash_of "$P3")
S4='amigo1'; H4=$(hash_of "$S4")
P5='zzzz00'; H5=$(hash_of "$P5")
S6='abcde'; H6=$(hash_of "$S6")

for rep in $(seq 1 "$REPS"); do
  echo "[REP ${rep}/${REPS}] Ejecutando bateria..."
  run_case "$rep" 'T1' 'num len6 encontrado' 'num' '6' 'encontrado' "$P1" "$H1"
  run_case "$rep" 'T2' 'num len6 no_encontrado (hash de abcdef)' 'num' '6' 'no_encontrado' "$S2" "$H2"
  run_case "$rep" 'T3' 'lower len5 encontrado' 'lower' '5' 'encontrado' "$P3" "$H3"
  run_case "$rep" 'T4' 'lower len5 no_encontrado (hash de amigo1)' 'lower' '5' 'no_encontrado' "$S4" "$H4"
  run_case "$rep" 'T5' 'alnum len6 encontrado' 'alnum' '6' 'encontrado' "$P5" "$H5"
  run_case "$rep" 'T6' 'alnum len4 no_encontrado (hash de abcde)' 'alnum' '4' 'no_encontrado' "$S6" "$H6"
done

echo "LISTO: $OUT"
