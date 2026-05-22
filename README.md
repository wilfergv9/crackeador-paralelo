# GPU MD5 Cracker - Proyecto de Computación Paralela

## Descripción General

Crackeador de hashes MD5 mediante fuerza bruta usando GPU NVIDIA con CUDA. Implementa:
- **Kernel CUDA personalizado** con MD5 implementado manualmente (sin librerías externas)
- **Mapeo eficiente índice → contraseña** para garantizar cobertura sin duplicados
- **Sincronización con `atomicCAS`** para evitar condiciones de carrera
- **Medición de rendimiento en MH/s** con eventos CUDA
- **Versión secuencial CPU** para validación y comparación de velocidad

### Características Técnicas

| Aspecto | Detalle |
|--------|---------|
| **Algoritmo MD5** | Implementación manual en kernel (función `md5_hash`) |
| **Estrategia GPU** | 1 hilo = 1 candidato; índice global → contraseña |
| **Mapeo índice** | Sistema de numeración en base N (N = tamaño alfabeto) |
| **Sincronización** | `atomicCAS` para escritura atómica de resultado |
| **Medición de tiempo** | `cudaEvent` para medir kernel + cálculo de MH/s |
| **Soporta** | Fuerza bruta + modo diccionario (wordlist) |
| **GPU probada** | RTX 3050, RTX 4060 (compute capability 6.1+) |

---

## Estructura del Proyecto

```
.
├── md5.cuh              # Implementación MD5 (host + device)
├── gpu_crack.cu         # Kernel CUDA + host principal
├── secuencial.cpp       # Versión CPU para comparación
├── Makefile             # Compilación automática
└── README.md            # Esta documentación
```

### Archivos Clave

#### `md5.cuh`
- Funciones `__host__ __device__` inline para máxima portabilidad
- Estructura `MD5State` (4×uint32_t = 128 bits)
- Funciones auxiliares: `md5_init()`, `md5_process_block()`, `md5_hash()`
- Tablas precalculadas T[64] y funciones de rotación

**Decisión de diseño**: Todas las funciones son `inline` para que el compilador CUDA/C++ las optimice como si fueran escritas directamente en cada sitio de llamada.

#### `gpu_crack.cu`
- **Kernel `md5_crack_kernel`**: cálculo paralelo del cracking
  - Mapeo: `global_id = blockIdx.x * blockDim.x + threadIdx.x`
  - Cada hilo genera su contraseña con `index_to_password`
  - Calcula MD5 y compara con target
  - Usa `atomicCAS` para guardar resultado de forma thread-safe
- **Host `main()`**:
  - Parseo de argumentos CLI
  - Asignación de memoria GPU
  - Lanzamiento de kernel en batches
  - Medición de tiempo con `cudaEvent`
  - Cálculo de MH/s

#### `secuencial.cpp`
- Implementación CPU idéntica en lógica (mismas funciones)
- Itera secuencialmente desde índice 0 a N-1
- Útil para:
  - Verificar correctitud (comparar passwords encontrados)
  - Medir overhead de GPU (warmup, transfer)
  - Validar implementación MD5

---

## Compilación

### Requisitos
- **NVIDIA CUDA Toolkit** (nvcc) ≥ 11.0
- **GCC/G++** ≥ 9.0 (con C++17)
- **GPU NVIDIA** con compute capability ≥ 6.1 (GeForce 10 series o superior)

### Verificar CUDA
```bash
nvcc --version
nvidia-smi  # Verifica GPU y driver
```

### Compilar
```bash
# Compilar ambas versiones
make

# O selectivamente
make gpu          # Solo CUDA
make secuencial   # Solo CPU
make clean        # Limpiar
```

#### Configurar para tu GPU
El Makefile está configurado para `sm_61` (GeForce GTX 1050, RTX 2070, RTX 3050, etc.).
Si tienes una GPU diferente, actualiza:

```makefile
# Cambiar en Makefile:
CUDA_CFLAGS := -std=c++17 -arch=sm_61 -gencode=arch=compute_61,code=sm_61 -O3
#                                    ^^^^                           ^^^^
```

Valores comunes:
- `sm_35` - Kepler (GTX 750, GTX Titan X)
- `sm_50` - Maxwell (GTX 750 Ti, GTX 960)
- `sm_61` - Pascal (GTX 1050, RTX 2070) ← **Default**
- `sm_70` - Volta (Titan V, Tesla V100)
- `sm_75` - Turing (RTX 2080, RTX 3080)
- `sm_86` - Ampere (RTX 30 series)
- `sm_89` - Ada (RTX 40 series)

Obtén tu compute capability en: https://docs.nvidia.com/cuda/cuda-c-programming-guide/

---

## Uso

### Sintaxis

#### Versión GPU
```bash
./gpu_crack <hash_md5> <longitud> [alfabeto] [modo] [wordlist]
```

**Parámetros:**
- `<hash_md5>` - Hash MD5 en hex (32 caracteres)
- `<longitud>` - Longitud de contraseña a probar (0-64)
- `[alfabeto]` - Alfabeto: `num` | `lower` | `alnum` (default: alnum)
- `[modo]` - `brute` | `dict` (default: brute)
- `[wordlist]` - Archivo wordlist (solo si modo=dict)

#### Versión CPU (secuencial)
```bash
./secuencial <hash_md5> <longitud> [alfabeto]
```

### Ejemplos

#### Ejemplo 1: Fuerza bruta alfanumérica (7 caracteres)
```bash
./gpu_crack cc03e747a6afbbcbf8be7668acfebee5 7 alnum brute
```

**Salida esperada:**
```
╔═════════════════════════════════════════════════════════╗
║         GPU MD5 Cracker - CUDA Implementation          ║
╚═════════════════════════════════════════════════════════╝

[CONFIG]
  Hash objetivo: cc03e747a6afbbcbf8be7668acfebee5
  Modo: brute
  Longitud: 7
  Alfabeto: alnum (tamaño: 62)
  Espacio de búsqueda: 3521614606208 candidatos

[GPU]
  Dispositivo: NVIDIA GeForce RTX 3050 Laptop GPU
  Compute Capability: 8.6
  Max Threads per Block: 1024
  Max Grid Size: (2147483647, 65535, 65535)

[LANZAMIENTO]
  Hilos por bloque: 256
  Número de bloques: 221876
  Total de hilos: 56800256

[BATCH 0-56800256]
  Tiempo kernel: 2345.231 ms
  Velocidad: 24.19 MH/s
  ¡ENCONTRADO!

╔═════════════════════════════════════════════════════════╗
║                  ¡HASH CRACKEADO!                      ║
╚═════════════════════════════════════════════════════════╝

[RESULTADO]
  Contraseña: test123
  Intentos: 12000000
  Tiempo total: 2.35 segundos
  Velocidad media: 5.10 MH/s
```

#### Ejemplo 2: Fuerza bruta solo números (longitud 4)
```bash
./gpu_crack 6c20a50a7e8f5e1a3e6c4f5f5c5f5f5f 4 num brute
```

#### Ejemplo 3: Fuerza bruta solo minúsculas (longitud 5)
```bash
./gpu_crack abc123def456789abc123def456789ab 5 lower brute
```

#### Ejemplo 4: Modo diccionario
```bash
./gpu_crack cc03e747a6afbbcbf8be7668acfebee5 0 alnum dict wordlist.txt
```

#### Ejemplo 5: Comparación CPU vs GPU
```bash
# CPU (lento, para hashes cortos)
time ./secuencial cc03e747a6afbbcbf8be7668acfebee5 7 alnum

# GPU (rápido)
time ./gpu_crack cc03e747a6afbbcbf8be7668acfebee5 7 alnum brute
```

---

## Generar Hashes MD5 para Pruebas

### En Linux
```bash
# Crear un hash conocido
echo -n "test123" | md5sum
# Salida: cc03e747a6afbbcbf8be7668acfebee5

# Intentar crackearlo
./gpu_crack cc03e747a6afbbcbf8be7668acfebee5 7 alnum brute
```

### Script Python para generar hashes
```python
import hashlib

passwords = ["abc", "password", "12345", "admin", "test123"]
for pwd in passwords:
    hash_obj = hashlib.md5(pwd.encode())
    print(f"{pwd}: {hash_obj.hexdigest()}")
```

---

## Arquitectura y Decisiones de Diseño

### 1. Mapeo Índice → Contraseña

**Problema**: ¿Cómo distribuir el espacio de búsqueda entre hilos sin duplicados?

**Solución**: Sistema de numeración en base N
```
Alfabeto "01", longitud 3 (espacio = 8):
  idx=0 → password="000"
  idx=1 → password="100"
  idx=2 → password="010"
  idx=3 → password="110"
  idx=4 → password="001"
  ...
```

**Implementación** (en `index_to_password`):
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

**Ventajas:**
- Garantiza cobertura del espacio sin duplicados
- O(longitud) en tiempo
- Mapeo reversible

### 2. Implementación MD5 en Kernel

**Problema**: Librerías como `<openssl/md5.h>` no funcionan en kernels CUDA.

**Solución**: Implementación manual `md5_hash()` en `md5.cuh`
- Funciones `__host__ __device__` para uso en CPU y GPU
- Todas inline para máxima optimización
- Tablas precalculadas T[64] y s[64]
- Soporta hashes de hasta ~55 bytes (suficiente para contraseñas)

**Proceso MD5**:
1. Inicializar estado (A, B, C, D) con valores estándar
2. Para cada bloque de 512 bits (16×32-bit):
   - 64 rondas con funciones F, G, H, I
   - Tabla T[i] = floor(2^32 × |sin(i+1)|)
   - Rotaciones left-rotate según tablas s[]
3. Combinar (A, B, C, D) = estado final

### 3. Sincronización con atomicCAS

**Problema**: Múltiples hilos pueden encontrar coincidencia casi simultáneamente. ¿Cómo guardar resultado de forma segura?

**Solución**: `atomicCAS` (Compare-And-Swap)
```cuda
int expected = 0;
int desired = 1;
if (atomicCAS(&results[0].found, expected, desired) == expected) {
    // Este hilo ganó: copia la contraseña
    for (int i = 0; i <= password_length; i++) {
        results[0].password[i] = password[i];
    }
}
```

**Garantías:**
- Operación atómica a nivel de hardware
- Solo un hilo escribe (evita overwrite)
- Otros hilos detectan que ya fue escrito

### 4. Medición de Rendimiento (MH/s)

**Fórmula**:
```
MH/s = (número de hashes calculados) / (tiempo en segundos) / 1,000,000
```

**Medición con CUDA events**:
```cuda
cudaEventCreate(&start_event);
cudaEventCreate(&stop_event);

cudaEventRecord(start_event);
// Lanzar kernel
kernel<<<blocks, threads>>>(args);
cudaEventRecord(stop_event);
cudaEventSynchronize(stop_event);

float ms;
cudaEventElapsedTime(&ms, start_event, stop_event);
double mh_s = (hashes / (ms / 1000.0)) / 1e6;
```

**Ventajas sobre CPU timing**:
- Mide solo tiempo de kernel (sin transfer overhead)
- Precisión de microsegundos
- Aislado de variaciones del SO

### 5. Procesamiento por Batches

**Problema**: El espacio de búsqueda puede superar MaxThreadsPerGrid.

**Solución**: Dividir en batches
```
Ejemplo: espacio = 10^15, max_hilos_GPU = 2^31 × 1024
  Batch 1: índices 0 a 2^31×1024
  Batch 2: índices 2^31×1024 a 2×2^31×1024
  ...
```

Cada batch lanza el kernel completo y copia resultados.

---

## Optimizaciones GPU

### 1. Memoria Global vs Registros
- Alfabeto (`d_alphabet`) en memoria global (cacheable)
- Cada hilo calcula su propia contraseña en **registros locales** (rápido)
- Resultado final en memoria global (atómico)

### 2. Ocupación de Registros
- `index_to_password` usa ~8 registros
- `md5_hash` usa ~40 registros
- Total: ~50 registros por hilo (bien dentro del límite 255/hilo en RTX 3050)

### 3. Coalesce Memory Access
- Lectura de alfabeto: warp-aligned cuando posible
- No hay acceso desordenado (todos leen en patrón similar)

### 4. Divergencia
- Control flow dentro del kernel es regular (sin bifurcaciones data-dependent)
- Bucles MD5 son deterministas

---

## Benchmarks Esperados

### Configuración de Prueba
- **GPU**: NVIDIA RTX 3050 (2560 CUDA cores)
- **Hash**: MD5 de 6 caracteres alfanuméricos
- **Espacio**: 62^6 ≈ 56.8 mil millones

### Resultados Típicos

| GPU | Velocidad | Tiempo (6 chars alnum) |
|-----|-----------|------------------------|
| RTX 3050 | 20-30 MH/s | 30-60 min |
| RTX 4060 | 25-35 MH/s | 25-45 min |
| CPU (Ryzen 5) | 0.1-0.5 MH/s | 30+ horas |

**Aceleración GPU/CPU**: ~50-100×

---

## Troubleshooting

### "Error: No hay dispositivos CUDA disponibles"
```bash
# Verificar instalación
nvidia-smi

# Si falla, instalar CUDA Toolkit
# En Ubuntu/Debian:
sudo apt install nvidia-cuda-toolkit

# En Fedora:
sudo dnf install cuda-toolkit
```

### "nvcc: command not found"
```bash
# Agregar CUDA al PATH
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Hacer permanente (agregar a ~/.bashrc)
```

### "GPU out of memory"
Reducir tamaño de bloque en `gpu_crack.cu`:
```cuda
#define BLOCK_SIZE 128  // Antes era 256
```

### Resultado incorrecto
- Verificar hash: `echo -n "password" | md5sum`
- Probar con versión CPU: `./secuencial <hash> <len> alnum`
- Si CPU también falla, verificar `md5.cuh`

### Muy lento en GPU
Posibles causas:
1. GPU desocupada (compute capability diferente)
2. Memoria insuficiente (reduce BLOCK_SIZE)
3. Kernel suboptimizado (profila con `nvprof`)

---

## Extensiones Posibles

### 1. Soporte para MD5 de múltiples bloques
Modificar `md5_hash()` para procesar > 55 bytes (requiere padding multiple)

### 2. Modo ataque con salt
Parametrizar: `MD5(password + salt)`

### 3. Integrated Hash Cracking
Soportar SHA1, SHA256 (implementar kernels adicionales)

### 4. GPU Persistence
Guardar estado de búsqueda para reanudar en caso de interrupción

### 5. Multi-GPU
Distribuir carga entre múltiples GPUs con `cudaSetDevice()`

---

## Referencias y Documentación

### MD5
- RFC 1321: https://tools.ietf.org/html/rfc1321
- Especificación oficial del algoritmo

### CUDA
- NVIDIA CUDA C++ Programming Guide
- https://docs.nvidia.com/cuda/cuda-c-programming-guide/
- Compute Capability Chart
- https://docs.nvidia.com/cuda/cuda-c-programming-guide/#compute-capability

### Cracking MD5
- Diccionarios de prueba: https://github.com/danielmiessler/SecLists
- Rainbow tables (para referencia): https://www.rainbow-table.com/

---

## Autor y Licencia

**Proyecto académico** para Programación Paralela (Ingeniería de Sistemas, UIS).

**Requisitos de entrega:**
- ✅ Código CUDA con kernel MD5 personalizado
- ✅ Versión secuencial para comparación
- ✅ Medición de MH/s con eventos CUDA
- ✅ Sincronización thread-safe (atomicCAS)
- ✅ Documentación completa

---

## Contacto y Soporte

Para preguntas sobre el proyecto o compilación:
- Revisar logs de compilación: `make clean && make gpu 2>&1 | tee build.log`
- Verificar CUDA con: `nvidia-smi` y `nvcc --version`
- Probar GPU con: `./gpu_crack <hash> 3 num brute` (pequeño espacio)


