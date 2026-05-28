#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cuda_runtime.h>
#include <chrono>
#include "md5.cuh"

/*
 * GPU MD5 Cracker - CUDA Implementation
 * 
 * Decisión arquitectónica principal:
 * - 1 hilo CUDA = 1 candidato de contraseña
 * - Cada hilo genera su contraseña a partir de su índice global threadIdx.x + blockIdx.x*blockDim.x
 * - Función index_to_password convierte índice numérico a string de contraseña en el alfabeto especificado
 * - Kernel procesa datos de forma data-parallel: cada hilo calcula MD5(contraseña) de forma independiente
 * - Si coincide con target, usa atomicCAS para escribir en buffer de salida evitando race conditions
 */

// ============================================================================
// Definiciones y límites
// ============================================================================

#define MAX_PASSWORD_LENGTH 64
#define MAX_RESULTS 100
#define BLOCK_SIZE 256  // Hilos por bloque

// Estructura para almacenar resultados
struct CrackerResult {
    char password[MAX_PASSWORD_LENGTH + 1];
    int found;
};

// ============================================================================
// Kernel Device Functions
// ============================================================================

/*
 * FUNCIÓN CRÍTICA: index_to_password
 * Transforma un índice numérico a una contraseña en base al alfabeto
 * 
 * Ejemplo: alfabeto="01", longitud=3
 *   idx=0 -> "000"
 *   idx=1 -> "100"
 *   idx=2 -> "010"
 *   idx=3 -> "110"
 *   idx=4 -> "001"
 *   ...
 * 
 * Matemática: sistema de numeración en base N (donde N = |alfabeto|)
 */
__device__ void index_to_password(uint64_t index, char *password, int length,
                                   const char *alphabet, int alphabet_size) {
    // Trabajar de derecha a izquierda (dígito menos significativo primero)
    for (int i = 0; i < length; i++) {
        password[i] = alphabet[index % alphabet_size];
        index /= alphabet_size;
    }
    password[length] = '\0';
}

// ============================================================================
// Kernel Principal
// ============================================================================

__global__ void md5_crack_kernel(
    uint32_t target_A, uint32_t target_B, uint32_t target_C, uint32_t target_D,
    int password_length,
    const char *alphabet_ptr,
    int alphabet_size,
    uint64_t start_index,
    uint64_t max_index,
    CrackerResult *results,
    uint64_t *attempts_counter
) {
    /*
     * Decisión de mapeo: threadIdx.x + blockIdx.x * blockDim.x
     * Esto permite escalar a múltiples bloques si el espacio de búsqueda
     * supera MaxThreadsPerBlock * MaxBlocksPerGrid
     */
    uint64_t global_id = blockIdx.x * blockDim.x + threadIdx.x;
    uint64_t index = start_index + global_id;
    
    // Limitar al máximo
    if (index >= max_index) return;
    
    // Buffer local para contraseña (cada hilo tiene su propia copia en registros)
    char password[MAX_PASSWORD_LENGTH + 1];
    
    // Generar contraseña a partir del índice
    index_to_password(index, password, password_length, alphabet_ptr, alphabet_size);
    
    // Calcular MD5 de la contraseña
    MD5State hash = md5_hash((unsigned char *)password, password_length);
    
    // Incrementar contador de intentos (para calcular MH/s)
    // atomicAdd para 64-bit usa unsigned long long en device
    atomicAdd((unsigned long long*)attempts_counter, 1ULL);
    
    // Comparar con target
    if (md5_equals(hash, target_A, target_B, target_C, target_D)) {
        /*
         * Decisión de sincronización: atomicCAS (Compare-And-Set)
         * Garantiza que solo un hilo escribe en results[0].found
         * Evita condiciones de carrera en escritura de resultado
         */
        int expected = 0;
        int desired = 1;
        if (atomicCAS(&results[0].found, expected, desired) == expected) {
            // Este hilo ganó: copia la contraseña
            for (int i = 0; i <= password_length; i++) {
                results[0].password[i] = password[i];
            }
        }
    }
}

// ============================================================================
// Funciones Helper de Host
// ============================================================================

void check_cuda_error(cudaError_t error, const char *message) {
    if (error != cudaSuccess) {
        fprintf(stderr, "CUDA Error en %s: %s\n", message, cudaGetErrorString(error));
        exit(1);
    }
}

/*
 * Parsear un string hex de 32 caracteres (128 bits MD5) en 4 uint32_t
 * Formato esperado: "482c811da5d5b4bc6d497ffa98491e38"
 */
void parse_md5_hash(const char *hex_str, uint32_t *A, uint32_t *B, uint32_t *C, uint32_t *D) {
    if (strlen(hex_str) != 32) {
        fprintf(stderr, "Error: hash debe tener 32 caracteres hexadecimales\n");
        exit(1);
    }
    
    // MD5 es little-endian: primeros 8 caracteres hex = A (en orden de bytes inverso)
    *A = hex_to_uint32(&hex_str[0]);
    *B = hex_to_uint32(&hex_str[8]);
    *C = hex_to_uint32(&hex_str[16]);
    *D = hex_to_uint32(&hex_str[24]);
}

/*
 * Obtener alfabeto según nombre: "num", "lower", "alnum"
 */
const char* get_alphabet(const char *name, int *size) {
    static const char *num_alphabet = "0123456789";
    static const char *lower_alphabet = "abcdefghijklmnopqrstuvwxyz";
    static const char *alnum_alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    
    if (strcmp(name, "num") == 0) {
        *size = 10;
        return num_alphabet;
    } else if (strcmp(name, "lower") == 0) {
        *size = 26;
        return lower_alphabet;
    } else if (strcmp(name, "alnum") == 0) {
        *size = 62;
        return alnum_alphabet;
    } else {
        fprintf(stderr, "Error: alfabeto desconocido '%s' (usa: num, lower, alnum)\n", name);
        exit(1);
    }
}

/*
 * Calcular número total de candidatos posibles
 * Para alfabeto de tamaño N y longitud L: N^L
 */
uint64_t calculate_search_space(int alphabet_size, int length) {
    uint64_t space = 1;
    for (int i = 0; i < length; i++) {
        space *= alphabet_size;
        // Protección contra overflow (si space > 10^18, es demasiado)
        if (space > 1e18) {
            fprintf(stderr, "Advertencia: espacio de búsqueda muy grande (>10^18)\n");
            return ULLONG_MAX;
        }
    }
    return space;
}

/*
 * Modo diccionario: leer palabras desde archivo y comprobación secuencial en GPU
 */
void crack_dictionary_mode(const char *hash_str, const char *wordlist_file,
                           uint32_t target_A, uint32_t target_B, 
                           uint32_t target_C, uint32_t target_D) {
    FILE *fp = fopen(wordlist_file, "r");
    if (!fp) {
        perror("Error al abrir wordlist");
        exit(1);
    }
    
    printf("[DICT MODE] Leyendo wordlist: %s\n", wordlist_file);
    
    // Contar líneas para determinar tamaño de bloque
    int line_count = 0;
    char line[MAX_PASSWORD_LENGTH + 1];
    while (fgets(line, sizeof(line), fp)) {
        line_count++;
    }
    
    printf("[DICT MODE] Total de palabras: %d\n", line_count);
    rewind(fp);
    
    // Preparar GPU
    CrackerResult *d_results;
    uint64_t *d_attempts;
    cudaMalloc(&d_results, sizeof(CrackerResult));
    cudaMalloc(&d_attempts, sizeof(uint64_t));
    
    CrackerResult h_results = {{0}, 0};
    uint64_t h_attempts = 0;
    
    cudaMemcpy(d_results, &h_results, sizeof(CrackerResult), cudaMemcpyHostToDevice);
    cudaMemcpy(d_attempts, &h_attempts, sizeof(uint64_t), cudaMemcpyHostToDevice);
    
    auto start_time = std::chrono::high_resolution_clock::now();
    
    // Procesar wordlist
    int word_idx = 0;
    char **d_words = nullptr;
    int batch_size = 1024;  // Palabras por batch
    
    while (fgets(line, sizeof(line), fp)) {
        // Remover newline
        int len = strlen(line);
        if (line[len-1] == '\n') line[len-1] = '\0';
        
        // En modo simple: comprobación secuencial en host
        MD5State hash = md5_hash((unsigned char *)line, strlen(line));
        h_attempts++;
        
        if (md5_equals(hash, target_A, target_B, target_C, target_D)) {
            printf("\n[✓] ¡ENCONTRADO! Contraseña: %s\n", line);
            printf("Intentos: %lu\n", h_attempts);
            h_results.found = 1;
            strcpy(h_results.password, line);
            break;
        }
        
        if (word_idx % 10000 == 0) {
            printf("\rProcesadas: %d palabras...", word_idx);
            fflush(stdout);
        }
        word_idx++;
    }
    
    auto end_time = std::chrono::high_resolution_clock::now();
    double elapsed = std::chrono::duration<double>(end_time - start_time).count();
    
    if (h_results.found) {
        printf("Tiempo: %.2f segundos\n", elapsed);
        printf("Velocidad: %.2f kH/s\n", h_attempts / (elapsed * 1000));
    } else {
        printf("\n[✗] No encontrado en wordlist\n");
    }
    
    fclose(fp);
    cudaFree(d_results);
    cudaFree(d_attempts);
}

// ============================================================================
// Función Principal
// ============================================================================

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Uso: %s <hash_md5> <longitud> [alfabeto: num|lower|alnum] [modo: brute|dict] [wordlist.txt]\n", argv[0]);
        printf("Ejemplo fuerza bruta:\n");
        printf("  %s 482c811da5d5b4bc6d497ffa98491e38 6 alnum brute\n", argv[0]);
        printf("Ejemplo diccionario:\n");
        printf("  %s 482c811da5d5b4bc6d497ffa98491e38 0 alnum dict wordlist.txt\n", argv[0]);
        return 1;
    }
    
    const char *hash_str = argv[1];
    int password_length = atoi(argv[2]);
    const char *alphabet_name = (argc > 3) ? argv[3] : "alnum";
    const char *mode = (argc > 4) ? argv[4] : "brute";
    const char *wordlist_file = (argc > 5) ? argv[5] : nullptr;
    
    // Parsear hash objetivo
    uint32_t target_A, target_B, target_C, target_D;
    parse_md5_hash(hash_str, &target_A, &target_B, &target_C, &target_D);
    
    printf("╔═════════════════════════════════════════════════════════╗\n");
    printf("║         GPU MD5 Cracker - CUDA Implementation          ║\n");
    printf("╚═════════════════════════════════════════════════════════╝\n\n");
    
    printf("[CONFIG]\n");
    printf("  Hash objetivo: %s\n", hash_str);
    printf("  Modo: %s\n", mode);
    
    // Modo diccionario
    if (strcmp(mode, "dict") == 0 || strcmp(mode, "dictionary") == 0) {
        crack_dictionary_mode(hash_str, wordlist_file, target_A, target_B, target_C, target_D);
        return 0;
    }
    
    // Modo fuerza bruta
    int alphabet_size;
    const char *alphabet = get_alphabet(alphabet_name, &alphabet_size);
    
    printf("  Longitud: %d\n", password_length);
    printf("  Alfabeto: %s (tamaño: %d)\n", alphabet_name, alphabet_size);
    
    uint64_t search_space = calculate_search_space(alphabet_size, password_length);
    printf("  Espacio de búsqueda: %lu candidatos\n\n", search_space);
    
    // Obtener información de GPU
    int device_count;
    cudaGetDeviceCount(&device_count);
    if (device_count == 0) {
        fprintf(stderr, "Error: No hay dispositivos CUDA disponibles\n");
        return 1;
    }
    
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, 0);
    printf("[GPU]\n");
    printf("  Dispositivo: %s\n", prop.name);
    printf("  Compute Capability: %d.%d\n", prop.major, prop.minor);
    printf("  Max Threads per Block: %d\n", prop.maxThreadsPerBlock);
    printf("  Max Grid Size: (%d, %d, %d)\n\n", 
           prop.maxGridSize[0], prop.maxGridSize[1], prop.maxGridSize[2]);
    
    // Asignación de memoria GPU
    CrackerResult *d_results;
    uint64_t *d_attempts;
    char *d_alphabet;
    
    check_cuda_error(cudaMalloc(&d_results, sizeof(CrackerResult)), "malloc d_results");
    check_cuda_error(cudaMalloc(&d_attempts, sizeof(uint64_t)), "malloc d_attempts");
    check_cuda_error(cudaMalloc(&d_alphabet, alphabet_size + 1), "malloc d_alphabet");
    
    // Inicializar resultados en GPU
    CrackerResult h_results = {{0}, 0};
    uint64_t h_attempts = 0;
    
    check_cuda_error(cudaMemcpy(d_results, &h_results, sizeof(CrackerResult), cudaMemcpyHostToDevice),
                     "memcpy h_results to device");
    check_cuda_error(cudaMemcpy(d_attempts, &h_attempts, sizeof(uint64_t), cudaMemcpyHostToDevice),
                     "memcpy h_attempts to device");
    check_cuda_error(cudaMemcpy(d_alphabet, alphabet, alphabet_size + 1, cudaMemcpyHostToDevice),
                     "memcpy alphabet to device");
    
    // Crear eventos CUDA para medir tiempo
    cudaEvent_t start_event, stop_event;
    check_cuda_error(cudaEventCreate(&start_event), "create start event");
    check_cuda_error(cudaEventCreate(&stop_event), "create stop event");
    
    // Calcular configuración de grid/block
    int block_size = BLOCK_SIZE;
    int max_blocks = (search_space + block_size - 1) / block_size;
    
    // Limitar a máximo de bloques que GPU puede lanzar
    int max_grid_size = prop.maxGridSize[0];
    int actual_blocks = (max_blocks > max_grid_size) ? max_grid_size : max_blocks;
    
    printf("[LANZAMIENTO]\n");
    printf("  Hilos por bloque: %d\n", block_size);
    printf("  Número de bloques: %d\n", actual_blocks);
    printf("  Total de hilos: %d\n\n", actual_blocks * block_size);
    
    // Procesamiento por batches si es necesario
    uint64_t total_processed = 0;
    uint64_t total_attempts = 0;
    auto global_start = std::chrono::high_resolution_clock::now();
    
    while (total_processed < search_space && h_results.found == 0) {
        uint64_t batch_size = (uint64_t)actual_blocks * block_size;
        uint64_t remaining = search_space - total_processed;
        uint64_t batch_end = total_processed + ((remaining < batch_size) ? remaining : batch_size);
        
        // Registrar evento de inicio
        check_cuda_error(cudaEventRecord(start_event, 0), "record start event");
        
        // Lanzar kernel
        md5_crack_kernel<<<actual_blocks, block_size>>>(
            target_A, target_B, target_C, target_D,
            password_length,
            d_alphabet,
            alphabet_size,
            total_processed,
            batch_end,
            d_results,
            d_attempts
        );
        
        // Sincronizar y registrar evento de fin
        check_cuda_error(cudaEventRecord(stop_event, 0), "record stop event");
        check_cuda_error(cudaDeviceSynchronize(), "kernel sync");
        
        // Medir tiempo del kernel
        float kernel_time_ms;
        check_cuda_error(cudaEventElapsedTime(&kernel_time_ms, start_event, stop_event), "event elapsed");
        double kernel_time_s = kernel_time_ms / 1000.0;
        
        // Copiar resultados
        check_cuda_error(cudaMemcpy(&h_results, d_results, sizeof(CrackerResult), cudaMemcpyDeviceToHost),
                         "memcpy results to host");
        check_cuda_error(cudaMemcpy(&h_attempts, d_attempts, sizeof(uint64_t), cudaMemcpyDeviceToHost),
                         "memcpy attempts to host");
        
        total_attempts = h_attempts;
        uint64_t batch_hashes = batch_end - total_processed;
        double mh_per_s = (batch_hashes / kernel_time_s) / 1e6;
        
        printf("[BATCH %llu-%llu]\n", total_processed, batch_end);
        printf("  Tiempo kernel: %.3f ms\n", kernel_time_ms);
        printf("  Velocidad: %.2f MH/s\n", mh_per_s);
        
        if (h_results.found) {
            printf("  ¡ENCONTRADO!\n\n");
            break;
        }
        
        total_processed = batch_end;
        printf("\n");
    }
    
    auto global_end = std::chrono::high_resolution_clock::now();
    double total_time = std::chrono::duration<double>(global_end - global_start).count();
    
    // Resultados finales
    printf("╔═════════════════════════════════════════════════════════╗\n");
    if (h_results.found) {
        printf("║                  ¡HASH CRACKEADO!                      ║\n");
        printf("╚═════════════════════════════════════════════════════════╝\n\n");
        printf("[RESULTADO]\n");
        printf("  Contraseña: %s\n", h_results.password);
        printf("  Intentos: %lu\n", total_attempts);
        printf("  Tiempo total: %.2f segundos\n", total_time);
        printf("  Velocidad media: %.2f MH/s\n\n", (total_attempts / total_time) / 1e6);
    } else {
        printf("║                    NO ENCONTRADO                      ║\n");
        printf("╚═════════════════════════════════════════════════════════╝\n\n");
        printf("[RESULTADO]\n");
        printf("  Intentos: %lu\n", total_attempts);
        printf("  Tiempo total: %.2f segundos\n", total_time);
        printf("  Velocidad media: %.2f MH/s\n\n", (total_attempts / total_time) / 1e6);
    }
    
    // Limpiar
    cudaFree(d_results);
    cudaFree(d_attempts);
    cudaFree(d_alphabet);
    cudaEventDestroy(start_event);
    cudaEventDestroy(stop_event);
    
    return h_results.found ? 0 : 1;
}
