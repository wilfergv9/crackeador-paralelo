#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <climits>
#include <chrono>
#include <vector>
#include "md5.cuh"

/*
 * Crackeador MD5 Secuencial (CPU)
 * 
 * Decisión de diseño:
 * - Implementación idéntica a GPU pero con un único hilo
 * - Mismo mapeo índice → contraseña para garantizar resultados comparables
 * - Misma función MD5 para validación cruzada
 * - Útil para verificar correctitud y medir diferencia de velocidad CPU vs GPU
 */

// ============================================================================
// Funciones Helper (mismas que GPU)
// ============================================================================

void check_error(bool ok, const char *message) {
    if (!ok) {
        fprintf(stderr, "Error: %s\n", message);
        exit(1);
    }
}

/*
 * Transformar índice numérico a contraseña
 * Mismo algoritmo que el kernel GPU para garantizar equivalencia
 */
void index_to_password(uint64_t index, char *password, int length,
                       const char *alphabet, int alphabet_size) {
    for (int i = 0; i < length; i++) {
        password[i] = alphabet[index % alphabet_size];
        index /= alphabet_size;
    }
    password[length] = '\0';
}

void parse_md5_hash(const char *hex_str, uint32_t *A, uint32_t *B, uint32_t *C, uint32_t *D) {
    if (strlen(hex_str) != 32) {
        fprintf(stderr, "Error: hash debe tener 32 caracteres hexadecimales\n");
        exit(1);
    }
    
    *A = hex_to_uint32(&hex_str[0]);
    *B = hex_to_uint32(&hex_str[8]);
    *C = hex_to_uint32(&hex_str[16]);
    *D = hex_to_uint32(&hex_str[24]);
}

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

uint64_t calculate_search_space(int alphabet_size, int length) {
    uint64_t space = 1;
    for (int i = 0; i < length; i++) {
        space *= alphabet_size;
        if (space > 1e18) {
            fprintf(stderr, "Advertencia: espacio de búsqueda muy grande (>10^18)\n");
            return ULLONG_MAX;
        }
    }
    return space;
}

// ============================================================================
// Función Principal - Búsqueda Secuencial
// ============================================================================

int main(int argc, char **argv) {
    if (argc < 3) {
        printf("Uso: %s <hash_md5> <longitud> [alfabeto: num|lower|alnum]\n", argv[0]);
        printf("Ejemplo:\n");
        printf("  %s 482c811da5d5b4bc6d497ffa98491e38 6 alnum\n", argv[0]);
        return 1;
    }
    
    const char *hash_str = argv[1];
    int password_length = atoi(argv[2]);
    const char *alphabet_name = (argc > 3) ? argv[3] : "alnum";
    
    // Parsear hash objetivo
    uint32_t target_A, target_B, target_C, target_D;
    parse_md5_hash(hash_str, &target_A, &target_B, &target_C, &target_D);
    
    int alphabet_size;
    const char *alphabet = get_alphabet(alphabet_name, &alphabet_size);
    
    uint64_t search_space = calculate_search_space(alphabet_size, password_length);
    
    printf("╔═════════════════════════════════════════════════════════╗\n");
    printf("║      MD5 Cracker - Implementación Secuencial CPU       ║\n");
    printf("╚═════════════════════════════════════════════════════════╝\n\n");
    
    printf("[CONFIG]\n");
    printf("  Hash objetivo: %s\n", hash_str);
    printf("  Longitud: %d\n", password_length);
    printf("  Alfabeto: %s (tamaño: %d)\n", alphabet_name, alphabet_size);
    printf("  Espacio de búsqueda: %lu candidatos\n\n", search_space);
    
    // Buffer para la contraseña candidata
    char password[65];
    
    // Contadores
    uint64_t attempts = 0;
    bool found = false;
    
    auto start = std::chrono::high_resolution_clock::now();
    
    // Búsqueda secuencial
    printf("[BÚSQUEDA]\n");
    printf("Procesando");
    
    for (uint64_t index = 0; index < search_space; index++) {
        // Generar contraseña a partir del índice
        index_to_password(index, password, password_length, alphabet, alphabet_size);
        
        // Calcular MD5
        MD5State hash = md5_hash((unsigned char *)password, password_length);
        attempts++;
        
        // Comparar con target
        if (md5_equals(hash, target_A, target_B, target_C, target_D)) {
            found = true;
            printf("\r[✓] ¡ENCONTRADO! Contraseña: %s\n", password);
            break;
        }
        
        // Mostrar progreso cada 100k intentos
        if (attempts % 100000 == 0) {
            double progress = (100.0 * index) / search_space;
            printf("\r[BÚSQUEDA] Progreso: %.1f%% | Intentos: %lu", progress, attempts);
            fflush(stdout);
        }
    }
    
    auto end = std::chrono::high_resolution_clock::now();
    double elapsed = std::chrono::duration<double>(end - start).count();
    
    printf("\n\n");
    printf("╔═════════════════════════════════════════════════════════╗\n");
    if (found) {
        printf("║                  ¡HASH CRACKEADO!                      ║\n");
    } else {
        printf("║                    NO ENCONTRADO                      ║\n");
    }
    printf("╚═════════════════════════════════════════════════════════╝\n\n");
    
    printf("[RESULTADO]\n");
    printf("  Intentos: %lu\n", attempts);
    printf("  Tiempo total: %.2f segundos\n", elapsed);
    printf("  Velocidad: %.2f kH/s (kilos hashes por segundo)\n", (attempts / elapsed) / 1000);
    printf("  Velocidad: %.4f MH/s (millones hashes por segundo)\n\n", (attempts / elapsed) / 1e6);
    
    return found ? 0 : 1;
}
