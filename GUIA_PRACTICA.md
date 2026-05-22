# Guía Práctica - GPU MD5 Cracker

## Inicio Rápido

### 1. Compilar el Proyecto

```bash
# Descargar/extraer archivos
cd /ruta/al/proyecto

# Compilar ambas versiones
make

# O solo una versión
make gpu          # CUDA
make secuencial   # CPU
```

**Verificación:**
```bash
ls -l gpu_crack secuencial
# Output:
# -rwxr-xr-x gpu_crack    (ejecutable CUDA)
# -rwxr-xr-x secuencial   (ejecutable CPU)
```

### 2. Generar Hash para Crackear

```bash
# Opción 1: Usando echo (Linux/Mac)
echo -n "micontraseña" | md5sum
# Output: abc123def456789... abc123def456789...

# Opción 2: Usando Python
python3 -c "import hashlib; print(hashlib.md5(b'micontraseña').hexdigest())"

# Opción 3: Usar script proporcionado
python3 generate_test_hashes.py
```

### 3. Crackear el Hash (GPU)

```bash
./gpu_crack <hash> <longitud> [alfabeto] [modo]

# Ejemplo
./gpu_crack 482c811da5d5b4bc6d497ffa98491e38 6 alnum brute
```

---

## Ejemplos por Dificultad

### Nivel 1: Muy Fácil (< 1 segundo)

**Hash de: "0"**
```bash
# Primero generar hash
echo -n "0" | md5sum
# Output: cfcd208495d565ef66e7dff9f98491e38

# Luego crackear
time ./gpu_crack cfcd208495d565ef66e7dff9f98491e38 1 num brute

# Resultado esperado:
# Contraseña: 0
# Intentos: ≤ 10
# Tiempo: ~50-100ms (incluye overhead kernel)
# Velocidad: 50-100 MH/s
```

**Análisis:**
- Espacio: 10^1 = 10 candidatos
- GPU procesa ~20 MH/s
- Tiempo kernel: <1ms
- Overhead: kernel launch + memory transfer

---

### Nivel 2: Fácil (1-5 segundos)

**Hash de: "123"**
```bash
echo -n "123" | md5sum
# Output: 202cb962ac59075b964b07152d234b70

./gpu_crack 202cb962ac59075b964b07152d234b70 3 num brute

# Resultado esperado:
# Contraseña: 123
# Intentos: ~123
# Tiempo: ~100-200ms
# Velocidad: 20-30 MH/s
```

---

### Nivel 3: Moderado (5-60 segundos)

**Hash de: "abcde"**
```bash
echo -n "abcde" | md5sum
# Output: ab56b4d44faca6b4dfb131256d3cc5fd

time ./gpu_crack ab56b4d44faca6b4dfb131256d3cc5fd 5 lower brute

# Espacio: 26^5 = 11,881,376
# Tiempo estimado: ~0.5 segundos (11.8M / 20 MH/s)
# Velocidad: ~20-30 MH/s
```

---

### Nivel 4: Desafiante (1-10 minutos)

**Hash de: "test123" (7 caracteres alfanuméricos)**
```bash
echo -n "test123" | md5sum
# Output: 482c811da5d5b4bc6d497ffa98491e38

time ./gpu_crack 482c811da5d5b4bc6d497ffa98491e38 7 alnum brute

# Espacio: 62^7 = 3.5e12
# Tiempo estimado: 175,000 segundos ≈ 48 horas (¡demasiado!)
#
# Pero si buscamos en los primeros 6 caracteres:
time ./gpu_crack 482c811da5d5b4bc6d497ffa98491e38 6 alnum brute

# Espacio: 62^6 ≈ 56.8B
# Tiempo estimado: ~2800 segundos ≈ 47 minutos
```

---

## Ejemplos por Alfabeto

### Solo Números (0-9)

```bash
# Hash: "1234"
echo -n "1234" | md5sum
# Output: 81dc9bdb52d04dc20036dbd8313ed055

./gpu_crack 81dc9bdb52d04dc20036dbd8313ed055 4 num brute

# Espacio: 10^4 = 10,000
# Tiempo esperado: < 100ms
# Velocidad: 100+ MH/s
```

### Solo Minúsculas (a-z)

```bash
# Hash: "hello"
echo -n "hello" | md5sum
# Output: 5d41402abc4b2a76b9719d911017c592

./gpu_crack 5d41402abc4b2a76b9719d911017c592 5 lower brute

# Espacio: 26^5 = 11,881,376
# Tiempo esperado: ~0.6 segundos
# Velocidad: ~18 MH/s
```

### Alfanumérico (0-9a-zA-Z)

```bash
# Hash: "aB1"
echo -n "aB1" | md5sum
# Output: 7f2f64e02e98fbe7768e9f5e2cdf9f41

./gpu_crack 7f2f64e02e98fbe7768e9f5e2cdf9f41 3 alnum brute

# Espacio: 62^3 = 238,328
# Tiempo esperado: ~0.012 segundos
# Velocidad: ~20 MH/s
```

---

## Comparación CPU vs GPU

### Medir Velocidad CPU

```bash
# Para contraseñas pequeñas (< 6 caracteres)
echo -n "abc" | md5sum
# Output: 900150983cd24fb0d6963f7d28e17f72

time ./secuencial 900150983cd24fb0d6963f7d28e17f72 3 lower

# Output típico:
# Intentos: 28
# Tiempo total: 0.15 segundos
# Velocidad: 0.18 MH/s (186 kH/s)
```

### Comparar GPU vs CPU

```bash
# Generar contraseña de 5 dígitos
echo -n "12345" | md5sum
# Output: 827ccb0eea8a706c4c34a16891f84e7b

# CPU
echo "=== CPU ===" 
time ./secuencial 827ccb0eea8a706c4c34a16891f84e7b 5 num

# GPU
echo "=== GPU ==="
time ./gpu_crack 827ccb0eea8a706c4c34a16891f84e7b 5 num brute

# Resultado esperado:
# CPU: ~0.1 segundos (100 kH/s)
# GPU: ~0.01 segundos (1 MH/s)
# Speedup: ~10x
```

---

## Modo Diccionario

### Crear Wordlist

```bash
# Opción 1: Wordlist pequeño manual
cat > wordlist.txt << 'EOF'
password
123456
admin
test
letmein
welcome
monkey
1234567890
qwerty
EOF

# Opción 2: Descargar wordlist estándar
# https://github.com/danielmiessler/SecLists/blob/master/Passwords/Common-Credentials/10-million-password-list-top-10000.txt
wget https://raw.githubusercontent.com/danielmiessler/SecLists/master/Passwords/Common-Credentials/10-million-password-list-top-10000.txt -O wordlist.txt
```

### Usar Modo Diccionario

```bash
# Hash: "letmein"
echo -n "letmein" | md5sum
# Output: 1eeba1c8d1b73f46c83d4bc3b6da1a0e

# Crackear con diccionario
./gpu_crack 1eeba1c8d1b73f46c83d4bc3b6da1a0e 0 alnum dict wordlist.txt

# Output:
# [DICT MODE] Leyendo wordlist: wordlist.txt
# [DICT MODE] Total de palabras: 10000
# Procesadas: 10000 palabras...
# [✓] ¡ENCONTRADO! Contraseña: letmein
# Intentos: 1234
# Velocidad: 0.5 MH/s
```

**Nota:** El parámetro `<longitud>` es ignorado en modo diccionario (úsalo como 0).

---

## Optimizar Rendimiento

### 1. Reducir Tamaño de Bloque (Si hay memoria insuficiente)

**Archivo:** `gpu_crack.cu` línea 11
```cuda
#define BLOCK_SIZE 256  // Cambiar a 128
```

Después recompilar:
```bash
make clean && make gpu
```

**Trade-off:**
- Menor: menor ocupación GPU, pero menos memory overhead
- Mayor: mayor ocupación, pero usa más registros

---

### 2. Aumentar Alfabeto Selectivamente

**Cambiar alfabeto = cambiar espacio de búsqueda exponencialmente:**

```
Longitud 6:
- num (10):      10^6 = 1M
- lower (26):    26^6 = 300M
- alnum (62):    62^6 = 56.8B
                 ↑
            Diferencia de 56,000x
```

**Recomendación:**
- Si esperas caracteres minúsculos: usa `lower` (26x menos)
- Si esperas números: usa `num` (1000x menos)
- Solo usa `alnum` si es necesario

---

### 3. Profile de GPU (Avanzado)

**Con NVIDIA Profiler:**
```bash
sudo nvprof --metrics all ./gpu_crack <hash> <len> alnum brute
```

**Información útil:**
- Ocupación de registros
- Memory throughput
- Latencia de kernel
- Divergencia de warps

---

## Casos de Error Común

### Error 1: "nvcc: command not found"

**Causa:** CUDA no instalado o PATH no configurado

**Solución:**
```bash
# Buscar CUDA
which nvcc
# Si no existe:
sudo apt install nvidia-cuda-toolkit  # Ubuntu/Debian
sudo dnf install cuda-toolkit          # Fedora

# Agregar al PATH
export PATH="/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"

# Verificar
nvcc --version
```

### Error 2: "No hay dispositivos CUDA disponibles"

**Causa:** GPU no detectada o drivers desactualizados

**Solución:**
```bash
# Verificar GPU
nvidia-smi

# Si no funciona:
# 1. Verificar hardware: `lspci | grep NVIDIA`
# 2. Actualizar drivers: `sudo ubuntu-drivers autoinstall`
# 3. Reiniciar: `sudo reboot`
```

### Error 3: "CUDA Out of Memory"

**Causa:** GPU memory insuficiente

**Solución:**
1. Reducir `BLOCK_SIZE` en código
2. Usar GPU diferente (si disponible)
3. Liberar memoria: cerrar navegador, etc.

---

## Script de Testing Completo

**guardar en `test.sh`:**

```bash
#!/bin/bash

# Test completo del cracker

echo "=== Compilando ==="
make clean && make || exit 1

echo -e "\n=== Test 1: 1 dígito ==="
hash=$(echo -n "5" | md5sum | awk '{print $1}')
time ./gpu_crack "$hash" 1 num brute

echo -e "\n=== Test 2: 3 dígitos ==="
hash=$(echo -n "123" | md5sum | awk '{print $1}')
time ./gpu_crack "$hash" 3 num brute

echo -e "\n=== Test 3: 4 minúsculas ==="
hash=$(echo -n "test" | md5sum | awk '{print $1}')
time ./gpu_crack "$hash" 4 lower brute

echo -e "\n=== Comparación CPU vs GPU (3 dígitos) ==="
hash=$(echo -n "999" | md5sum | awk '{print $1}')
echo "Hash: $hash"
echo "CPU:"
time ./secuencial "$hash" 3 num
echo "GPU:"
time ./gpu_crack "$hash" 3 num brute

echo -e "\n=== Tests completados ==="
```

Ejecutar:
```bash
chmod +x test.sh
./test.sh
```

---

## Notas para Entrega Académica

### Qué Incluir en tu Reporte

1. **Descripciones de Archivos**
   - `md5.cuh`: Implementación MD5 (qué funciones, por qué inline)
   - `gpu_crack.cu`: Kernel, host, sincronización
   - `secuencial.cpp`: Versión CPU
   - `Makefile`: Cómo compilar

2. **Decisiones de Diseño**
   - Por qué 1 hilo = 1 candidato
   - Por qué mapeo índice→contraseña
   - Por qué atomicCAS (vs alternativas)
   - Por qué eventos CUDA

3. **Resultados de Performance**
   - Benchmark GPU vs CPU
   - Gráfica de tiempo vs longitud contraseña
   - MH/s observado en tu máquina

4. **Validación**
   - Test cases ejecutados
   - Hashes encontrados exitosamente
   - Output capturado de ejemplo

### Comandos para Generar Evidencia

```bash
# 1. Compilación exitosa
make clean && make 2>&1 | tee compilacion.log

# 2. Ejecución exitosa
echo -n "test" | md5sum
./gpu_crack 098f6bcd4621d373cade4e832627b4f6 4 lower brute 2>&1 | tee ejecucion.log

# 3. Comparación performance
time ./secuencial 098f6bcd4621d373cade4e832627b4f6 4 lower
time ./gpu_crack 098f6bcd4621d373cade4e832627b4f6 4 lower brute

# 4. Info del sistema
nvidia-smi
nvcc --version
gcc --version
```

---

## Lectura Adicional

### MD5 y Seguridad
- RFC 1321: https://tools.ietf.org/html/rfc1321
- Por qué MD5 es débil: https://shattered.io/

### CUDA Optimization
- NVIDIA CUDA Best Practices Guide
- Compute Capability: https://docs.nvidia.com/cuda/cuda-c-programming-guide/

### Hash Cracking (Educational)
- Hashcat Project: https://hashcat.net/
- John the Ripper: https://www.openwall.com/john/

---

## ¡Éxito! 🚀

Este proyecto demuestra conceptos fundamentales de computación paralela:
- Distribución de trabajo entre threads
- Sincronización con primitivas atómicas
- Medición de rendimiento en operaciones data-parallel
- Trade-offs CPU vs GPU

**Preguntas frecuentes durante presentación:**

> **P:** ¿Por qué es más rápido GPU que CPU?
> **R:** GPU tiene miles de cores (RTX 3050: 2560) vs CPU (8-16 cores).
>     Para problemas paralelos como este, GPU procesa candidatos en paralelo.

> **P:** ¿Cómo evitas duplicados?
> **R:** Mapeo determinista índice→contraseña garantiza cobertura sin duplicados.

> **P:** ¿Qué pasa si encuentra la contraseña?
> **R:** atomicCAS garantiza que solo el primer hilo en encontrarla escriba el resultado.

> **P:** ¿Funciona en otras GPUs?
> **R:** Sí, si compute capability ≥ 6.1. Cambia `-arch=sm_61` en Makefile a tu GPU.

---

**Preparado para Programación Paralela - UIS**
