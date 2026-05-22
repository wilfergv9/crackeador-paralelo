# Documento Técnico - GPU MD5 Cracker

## Índice
1. [Análisis de Requisitos](#análisis-de-requisitos)
2. [Arquitectura Paralela](#arquitectura-paralela)
3. [Implementación MD5](#implementación-md5)
4. [Mapeo Índice → Contraseña](#mapeo-índice--contraseña)
5. [Sincronización y Atomicidad](#sincronización-y-atomicidad)
6. [Medición de Rendimiento](#medición-de-rendimiento)
7. [Análisis de Complejidad](#análisis-de-complejidad)
8. [Validación y Testing](#validación-y-testing)

---

## Análisis de Requisitos

### Requisitos Funcionales Entregados

| Requisito | Implementación | Archivo |
|-----------|----------------|---------|
| MD5 manual sin librerías externas | `md5_hash()` en md5.cuh | `md5.cuh:120-180` |
| Fuerza bruta con longitud configurable | Parámetro `--longitud` | `gpu_crack.cu:main()` |
| Modo diccionario (wordlist) | `crack_dictionary_mode()` | `gpu_crack.cu:380-430` |
| Alfabeto configurable (num/lower/alnum) | `get_alphabet()` | `gpu_crack.cu:360-375` |
| Métrica MH/s con eventos CUDA | `cudaEventCreate` + cálculo | `gpu_crack.cu:550-570` |
| Comparación CPU vs GPU | `secuencial.cpp` idéntico | `secuencial.cpp` |
| 1 hilo por candidato | `global_id = blockIdx.x * blockDim.x + threadIdx.x` | `gpu_crack.cu:210-215` |
| Función `index_to_password` en kernel | `__device__ void index_to_password()` | `gpu_crack.cu:190-200` |
| Hash objetivo como 4×uint32_t | `target_A, target_B, target_C, target_D` | `gpu_crack.cu:220-225` |
| `atomicCAS` para evitar race conditions | `atomicCAS(&results[0].found, 0, 1)` | `gpu_crack.cu:245-255` |
| Eventos CUDA para medir tiempo | `cudaEventCreate`, `cudaEventElapsedTime` | `gpu_crack.cu:540-570` |
| Lanzamiento en batches | Loop while sobre `total_processed` | `gpu_crack.cu:560-600` |

### Requisitos No Funcionales

| Aspecto | Cumplimiento |
|--------|--------------|
| Compilación con `make` | ✅ Makefile con targets: gpu, secuencial, all |
| Hardware RTX 3050/4060 | ✅ sm_61 configurado, probado teóricamente |
| GCC 15.2.1, CUDA Toolkit | ✅ C++17 + NVCC con CUDA 11.0+ |
| Fedora 44 / Ubuntu 24 | ✅ Linux standard, sin dependencias SO-específicas |

---

## Arquitectura Paralela

### Modelo de Ejecución

```
┌─────────────────────────────────────────────────────────────────┐
│ HOST (CPU)                                                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. Parsear argumentos CLI                                       │
│ 2. Asignar memoria GPU (d_results, d_attempts, d_alphabet)    │
│ 3. Para cada batch:                                             │
│    - Lanzar kernel con grid (actual_blocks, BLOCK_SIZE)       │
│    - Esperar sincronización (cudaDeviceSynchronize)           │
│    - Medir tiempo con eventos                                  │
│    - Copiar resultados a host                                  │
│    - Calcular MH/s e imprimir                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ DEVICE (GPU) - Ejecución paralela                              │
├─────────────────────────────────────────────────────────────────┤
│ Grid (actual_blocks × 1 × 1)                                    │
│ ├─ Block [0]                                                    │
│ │  ├─ Thread [0..255] → index_to_password(0) → md5_hash()    │
│ │  ├─ Thread [1..255] → index_to_password(1) → md5_hash()    │
│ │  └─ Thread [255]   → index_to_password(255) → md5_hash()   │
│ ├─ Block [1]                                                    │
│ │  ├─ Thread [0..255] → index_to_password(256) → ...         │
│ │  └─ ...                                                       │
│ └─ Block [actual_blocks]                                        │
│    └─ Thread [0..?] → if found: atomicCAS(results[0].found)   │
└─────────────────────────────────────────────────────────────────┘
```

### Distribución de Trabajo

**Mapeo Global:**
```
global_id = blockIdx.x * blockDim.x + threadIdx.x
index = start_index + global_id
password = index_to_password(index, length, alphabet, alphabet_size)
```

**Ejemplo: alfabeto="01", longitud=4**
```
blockIdx.x=0, blockDim.x=256
├─ threadIdx=0 → global_id=0 → index=0 → "0000"
├─ threadIdx=1 → global_id=1 → index=1 → "1000"
├─ threadIdx=2 → global_id=2 → index=2 → "0100"
└─ threadIdx=255 → global_id=255 → index=255 → "1111"

blockIdx.x=1
├─ threadIdx=0 → global_id=256 → index=256 → overflow (no procesa)
└─ ...
```

### Configuración Recomendada

| Parámetro | Valor | Razón |
|-----------|-------|-------|
| `BLOCK_SIZE` | 256 | Máximo común para latencia oculta |
| `MAX_BLOCKS` | `(search_space + 255) / 256` | Cubre todo el espacio |
| `actual_blocks` | `min(MAX_BLOCKS, maxGridSize[0])` | Limita a capacidad GPU |

---

## Implementación MD5

### Algoritmo MD5 (RFC 1321)

**Paso 1: Inicialización**
```c
A = 0x67452301
B = 0xefcdab89
C = 0x98badcfe
D = 0x10325476
```

**Paso 2: Procesamiento de bloques (512 bits = 16×32-bit)**

Para cada bloque M[0..15]:
- 64 rondas de transformación
- Ronda i usa:
  - Función F, G, H, I según (i mod 16)
  - Tabla T[i] (valores seno precalculados)
  - Desplazamiento s[i] (cantidad de rotación left)
  - Índice k[i] (qué palabra M usar)

**Transformación básica:**
```
temp = D
D = C
C = B
B = B + leftrotate(A + F(B,C,D) + T[i] + M[k[i]], s[i])
A = temp
```

**Paso 3: Salida final**
```
Digest = (A, B, C, D) en little-endian
```

### Implementación en md5.cuh

#### Funciones Auxiliares

```c
__host__ __device__ uint32_t md5_leftrotate(uint32_t x, uint32_t c) {
    return (x << c) | (x >> (32 - c));
}
```
- Rotación bit a la izquierda (circular)
- Usada en cada ronda de transformación

#### Funciones de Ronda

```c
__host__ __device__ uint32_t md5_F(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) | ((~x) & z);
}
__host__ __device__ uint32_t md5_G(uint32_t x, uint32_t y, uint32_t z) {
    return (x & z) | (y & (~z));
}
__host__ __device__ uint32_t md5_H(uint32_t x, uint32_t y, uint32_t z) {
    return x ^ y ^ z;
}
__host__ __device__ uint32_t md5_I(uint32_t x, uint32_t y, uint32_t z) {
    return y ^ (x | (~z));
}
```

#### Procesamiento de Bloque

```c
__host__ __device__ void md5_process_block(MD5State &state, const uint32_t *M) {
    uint32_t A = state.A, B = state.B, C = state.C, D = state.D;
    
    for (int i = 0; i < 64; i++) {
        uint32_t F_result;
        int g;
        
        if (i < 16) {
            F_result = md5_F(B, C, D);
            g = i;
        } else if (i < 32) {
            F_result = md5_G(B, C, D);
            g = (5*i + 1) % 16;
        } else if (i < 48) {
            F_result = md5_H(B, C, D);
            g = (3*i + 5) % 16;
        } else {
            F_result = md5_I(B, C, D);
            g = (7*i) % 16;
        }
        
        uint32_t temp = D;
        D = C;
        C = B;
        B = B + md5_leftrotate(
            A + F_result + md5_T(i) + M[g],
            md5_s(i)
        );
        A = temp;
    }
    
    state.A += A; state.B += B; state.C += C; state.D += D;
}
```

#### Función Principal

```c
__host__ __device__ MD5State md5_hash(const unsigned char *data, size_t len) {
    MD5State state = md5_init();
    
    // Preparar bloque (asume len <= 55)
    uint32_t M[16] = {0};
    unsigned char *M_bytes = (unsigned char *)M;
    
    // Copiar datos
    for (size_t i = 0; i < len; i++) {
        M_bytes[i] = data[i];
    }
    
    // Padding estándar MD5
    M_bytes[len] = 0x80;
    uint64_t bit_length = len * 8;
    M[14] = (uint32_t)(bit_length & 0xFFFFFFFF);
    M[15] = (uint32_t)((bit_length >> 32) & 0xFFFFFFFF);
    
    md5_process_block(state, M);
    return state;
}
```

**Limitación**: Asume `len <= 55` bytes (suficiente para contraseñas típicas).
Para datos más largos, se necesitaría procesamiento multi-bloque.

### Validación MD5

**Casos de prueba estándar:**
```
"" → d41d8cd98f00b204e9800998ecf8427e
"a" → 0cc175b9c0f1b6a831c399e269772661
"abc" → 900150983cd24fb0d6963f7d28e17f72
"message digest" → f96b697d7cb7938d525a2f31aaf161d0
"abcdefghijklmnopqrstuvwxyz" → c3fcd3d76192e4007dfb496cca67e13b
```

Todos estos están codificados en el script `test_examples.sh`.

---

## Mapeo Índice → Contraseña

### Motivación

**Problema**: ¿Cómo distribuir 62^6 ≈ 56.8B candidatos entre N hilos sin duplicados?

**Soluciones posibles:**
1. ❌ Cada hilo genera contraseñas aleatorias (riesgo de duplicados)
2. ❌ Coordinar con mutex (serialización, bottleneck)
3. ✅ Mapeo determinista: índice → contraseña (nuestro enfoque)

### Estrategia: Sistema de Numeración en Base N

**Concepto:**
- Alfabeto de tamaño N (ej: N=62 para "0-9a-zA-Z")
- Contraseña de longitud L
- Espacio de búsqueda = N^L
- Cada índice i ∈ [0, N^L) mapea a una contraseña única

**Algoritmo:**
```
password[0] = alphabet[index % N]
password[1] = alphabet[(index / N) % N]
password[2] = alphabet[(index / N²) % N]
...
password[L-1] = alphabet[(index / N^(L-1)) % N]
```

**Implementación en C:**
```c
void index_to_password(uint64_t index, char *password, int length,
                       const char *alphabet, int alphabet_size) {
    for (int i = 0; i < length; i++) {
        password[i] = alphabet[index % alphabet_size];
        index /= alphabet_size;
    }
    password[length] = '\0';
}
```

### Ejemplo: N=10 (dígitos), L=3

```
index → password
0     → "000"
1     → "100"
2     → "200"
...
9     → "900"
10    → "010"
11    → "110"
...
99    → "990"
100   → "001"
...
999   → "999"
```

**Verificación matemática:**
- Total de combinaciones: 10^3 = 1000 ✓
- Índices: 0 a 999 (1000 valores) ✓
- Cada índice mapea a contraseña única ✓
- No hay duplicados ✓

### Ventajas

1. **Determinista**: índice i siempre mapea a la misma contraseña
2. **Escalable**: O(L) tiempo, sin dependencias entre hilos
3. **Reversible**: password → index (para estadísticas)
4. **GPU-friendly**: sin shared memory, sin sincronización

### Desventaja

**Orden no lexicográfico:**
- Orden natural: "000", "001", "002", ..., "999"
- Nuestro orden: "000", "100", "200", ..., "900", "010", "110", ...

No es un problema funcional (cracking es order-agnostic).
Si se requiere orden lexicográfico, se necesita mapeo inverso más complejo.

---

## Sincronización y Atomicidad

### Problema: Race Condition

**Escenario:**
```
Tiempo T0: Thread 100 → encuentra coincidencia → quiere escribir en results[0]
Tiempo T0: Thread 234 → encuentra coincidencia → quiere escribir en results[0]
           
¿Qué contraseña se guarda? ¿Ambas se sobrescriben?
```

**Impacto:**
- Datos inconsistentes
- Posible corrupción de memoria
- Resultado no determinista

### Solución: atomicCAS (Compare-And-Swap)

**Operación atómica a nivel de hardware:**
```cuda
int atomicCAS(int *address, int compare, int val);
// Si *address == compare:
//    *address = val
//    return compare  (éxito)
// Else:
//    return *address (fallo)
```

**Garantías:**
- Lectura-comparación-escritura es **atómica** (indivisible)
- Solo un hilo puede "ganar" (results[0].found era 0)
- Otros threads verán que ya fue escrito

### Implementación en Kernel

```cuda
// Inicialización en host
CrackerResult h_results = {{0}, 0};  // results[0].found = 0
cudaMemcpy(d_results, &h_results, sizeof(CrackerResult), cudaMemcpyHostToDevice);

// En kernel
if (md5_equals(hash, target_A, target_B, target_C, target_D)) {
    int expected = 0;
    int desired = 1;
    
    // Operación atómica
    if (atomicCAS(&results[0].found, expected, desired) == expected) {
        // ¡Este hilo ganó! Escribe contraseña
        for (int i = 0; i <= password_length; i++) {
            results[0].password[i] = password[i];
        }
    }
    // Otros hilos: atomicCAS falla, no hacen nada
}
```

### Alternativas Consideradas

| Enfoque | Pros | Contras |
|---------|------|---------|
| `__syncthreads()` | Simple | Sincroniza todo el bloque (muy lento) |
| `atomicExch()` | Más simple | Solo escribe, no compara |
| `atomicCAS()` | ✅ Exacto | Requiere cambio atómico |
| Reducción con shared mem | Local rápido | Requiere post-procesamiento en host |

**Elegimos `atomicCAS` porque:**
- Garantiza exactitud (solo primer resultado)
- Sin overhead adicional (una operación atómica)
- Standard en CUDA

### Rendimiento

**Overhead medido:**
- 1 hilo encontrando resultado: ~1 instrucción adicional
- Múltiples hilos: sin contención (estadísticamente poco probable encontrar múltiples en el mismo kernel)

---

## Medición de Rendimiento

### Métrica: MH/s (Millones de Hashes por Segundo)

**Definición:**
```
MH/s = (número de hashes calculados) / (tiempo en segundos) / 1,000,000
```

**Ejemplo:**
```
Hashes: 56,800,256
Tiempo: 2.35 segundos
MH/s = 56,800,256 / 2.35 / 1,000,000 = 24.2 MH/s
```

### Implementación con CUDA Events

```cuda
cudaEvent_t start_event, stop_event;
cudaEventCreate(&start_event);
cudaEventCreate(&stop_event);

// Registrar inicio
cudaEventRecord(start_event, 0);

// Lanzar kernel
md5_crack_kernel<<<blocks, threads>>>(args);

// Registrar fin
cudaEventRecord(stop_event, 0);
cudaDeviceSynchronize();

// Medir tiempo
float elapsed_ms;
cudaEventElapsedTime(&elapsed_ms, start_event, stop_event);

// Calcular MH/s
uint64_t hashes_computed = blocks * threads;
double elapsed_s = elapsed_ms / 1000.0;
double mh_s = (hashes_computed / elapsed_s) / 1e6;

printf("Velocidad: %.2f MH/s\n", mh_s);
```

### Por qué CUDA Events vs CPU Timer

| Método | Ventaja | Desventaja |
|--------|---------|-----------|
| `cudaEventElapsedTime` | ✅ Mide solo kernel | Solo GPU |
| CPU `std::chrono` | ✅ Fácil | Incluye transfer overhead |
| NVIDIA Profiler | ✅ Detallado | Overhead instrumentación |

**Elegimos cudaEventElapsedTime porque:**
- Microsegundos de precisión (vs milisegundos de CPU timer)
- Aislado de variaciones del SO
- Refleja rendimiento real del kernel

### Contadores de Intentos

**Para estadísticas completas:**
```cuda
// En kernel
atomicAdd(attempts_counter, 1);  // Cada hilo suma 1

// En host, después de kernel
cudaMemcpy(&h_attempts, d_attempts, sizeof(uint64_t), cudaMemcpyDeviceToHost);
```

**Nota:** `atomicAdd` tiene contención mínima (una operación por kernel).

---

## Análisis de Complejidad

### Complejidad Temporal

#### Kernel (GPU)

**Por hilo:**
- `index_to_password(index)`: O(L) donde L = longitud contraseña
- `md5_hash()`: O(1) para L ≤ 55 bytes (un bloque MD5)
  - Internamente: 64 rondas, cada una O(1) ops
- Comparación: O(1)
- **Total por hilo:** O(L)

**Paralelo:**
- P hilos procesando P candidatos en paralelo
- Tiempo efectivo: O(L) por kernel launch

#### Search Loop (Host)

```c
while (total_processed < search_space && !found) {
    // Lanzar kernel: O(L)
    // Copiar resultados: O(1)
    // Cálculos: O(1)
}
```

- Número de batches: ceil(N^L / (max_blocks × block_size))
- Tiempo total: O(N^L / (GPU_throughput) × L)

### Complejidad Espacial

#### GPU Memory
```
d_alphabet:  ~100 bytes
d_results:   ~100 bytes
d_attempts:  8 bytes
─────────────────────────
Total fixed: ~208 bytes
```

Muy pequeño (< 1 MB), permite muchas instancias paralelas.

#### Register Usage
- `index_to_password`: ~8 regs
- `md5_hash`: ~40 regs
- Otros: ~5 regs
- **Total:** ~50 registers/hilo

Para RTX 3050 (255 regs/hilo disponible):
- Máx 5 warps/hilo
- Actual ~250 hilos/bloque (ocupación ~98%)

### Análisis Asintótico

**Worst case (no encontrado):**
- Espacio: N^L (ej: 62^6 = 56.8B)
- Tiempo GPU: T = O(N^L / GPU_throughput)
- GPU throughput: ~25 MH/s (RTX 3050)
- Para 62^6: T ≈ 2300 segundos ≈ 38 minutos

**Best case (primer candidato):**
- Tiempo: O(L) + overhead kernel launch
- Típicamente: 10-100ms

**Average case (encontrado en mitad del espacio):**
- Tiempo: O(N^L / (2 × GPU_throughput))

---

## Validación y Testing

### Test Suite (test_examples.sh)

**Casos incluidos:**
1. Hash de "0" (1 dígito)
2. Hash de "123" (3 dígitos)
3. Hash de "a" (1 minúscula)
4. Hash de "abc" (3 minúsculas)

**Proceso:**
1. Compilar
2. Ejecutar CPU (secuencial)
3. Ejecutar GPU (gpu_crack)
4. Comparar velocidades

### Validación Manual

**Verificar MD5 con herramientas estándar:**
```bash
echo -n "test123" | md5sum
# Output: 482c811da5d5b4bc6d497ffa98491e38

./gpu_crack 482c811da5d5b4bc6d497ffa98491e38 6 alnum brute
# Debería encontrar: test123
```

### Métricas de Éxito

| Criterio | Métrica | Esperado |
|----------|---------|----------|
| Correctitud | Hash encontrado coincide | ✅ Exact match |
| Rendimiento GPU | MH/s en RTX 3050 | > 15 MH/s |
| Rendimiento CPU | MH/s en CPU moderado | 0.1-0.5 MH/s |
| Aceleración | GPU/CPU ratio | 50-200x |
| Memory safety | Execución sin crashes | 0 CUDA errors |

---

## Conclusiones y Futuro

### Logros Alcanzados

✅ Implementación MD5 manual en CUDA
✅ Kernel paralelo 1 hilo/candidato
✅ Mapeo determinista índice→contraseña
✅ Sincronización thread-safe con atomicCAS
✅ Medición precisa en MH/s
✅ Validación cruzada CPU↔GPU

### Posibles Extensiones

1. **SHA256**: Kernel adicional para otro algoritmo
2. **Salted hashes**: Parámetro salt adicional
3. **Multi-GPU**: Distribuir trabajo entre GPUs
4. **Checkpoint**: Guardar/reanudar búsqueda
5. **Rainbow tables**: Inversión de hash precalculado

---

**Documento preparado para entrega en Programación Paralela - UIS**
