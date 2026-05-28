#!/usr/bin/env bash
set -euo pipefail

OUT='pruebas_realizadas/resultados_raw.tsv'
RAW_DIR='pruebas_realizadas/raw'
mkdir -p "$RAW_DIR"

echo -e "test_id\tdescripcion\talfabeto\tlongitud\ttipo\tpassword\thash\tprograma\tencontrado\tintentos\ttiempo_s\tmh_s" > "$OUT"

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
  local test_id="$1"
  local descripcion="$2"
  local alfabeto="$3"
  local longitud="$4"
  local tipo="$5"
  local password="$6"
  local hash="$7"

  local cpu_out="$RAW_DIR/${test_id}_cpu.txt"
  local gpu_out="$RAW_DIR/${test_id}_gpu.txt"

  ./secuencial "$hash" "$longitud" "$alfabeto" > "$cpu_out" 2>&1 || true
  ./gpu_crack "$hash" "$longitud" "$alfabeto" brute > "$gpu_out" 2>&1 || true

  local cpu_found cpu_attempts cpu_time cpu_mhs
  local gpu_found gpu_attempts gpu_time gpu_mhs

  IFS=$'\t' read -r cpu_found cpu_attempts cpu_time cpu_mhs < <(extract_metrics CPU "$cpu_out")
  IFS=$'\t' read -r gpu_found gpu_attempts gpu_time gpu_mhs < <(extract_metrics GPU "$gpu_out")

  echo -e "${test_id}\t${descripcion}\t${alfabeto}\t${longitud}\t${tipo}\t${password}\t${hash}\tCPU\t${cpu_found}\t${cpu_attempts}\t${cpu_time}\t${cpu_mhs}" >> "$OUT"
  echo -e "${test_id}\t${descripcion}\t${alfabeto}\t${longitud}\t${tipo}\t${password}\t${hash}\tGPU\t${gpu_found}\t${gpu_attempts}\t${gpu_time}\t${gpu_mhs}" >> "$OUT"
}

# Casos num
P1='654321'; H1=$(hash_of "$P1")
run_case 'T1' 'num len6 encontrado' 'num' '6' 'encontrado' "$P1" "$H1"

S2='abcdef'; H2=$(hash_of "$S2")
run_case 'T2' 'num len6 no_encontrado (hash de abcdef)' 'num' '6' 'no_encontrado' "$S2" "$H2"

# Casos lower
P3='amigo'; H3=$(hash_of "$P3")
run_case 'T3' 'lower len5 encontrado' 'lower' '5' 'encontrado' "$P3" "$H3"

S4='amigo1'; H4=$(hash_of "$S4")
run_case 'T4' 'lower len5 no_encontrado (hash de amigo1)' 'lower' '5' 'no_encontrado' "$S4" "$H4"

# Casos alnum (max len 6)
P5='zzzz00'; H5=$(hash_of "$P5")
run_case 'T5' 'alnum len6 encontrado' 'alnum' '6' 'encontrado' "$P5" "$H5"

S6='abcde'; H6=$(hash_of "$S6")
run_case 'T6' 'alnum len4 no_encontrado (hash de abcde)' 'alnum' '4' 'no_encontrado' "$S6" "$H6"

echo 'LISTO'
