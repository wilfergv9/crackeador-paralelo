#ifndef MD5_CUH
#define MD5_CUH

#include <cstdint>
#include <cstring>

#ifndef __CUDACC__
#define __host__
#define __device__
#endif

/*
 * MD5 Implementation - Portable entre CPU y GPU
 * Decisión de diseño: MD5 como funciones device/host inline permite uso tanto
 * en kernels CUDA como en código secuencial C++. Los state constants y funciones
 * de transformación están inlined para máximo rendimiento en GPU.
 * 
 * Estructura MD5State: 128 bits = 4x uint32_t (A, B, C, D)
 * Entrada: 512 bits de datos divididos en 16 palabras de 32 bits
 */

// ============================================================================
// Constantes MD5 (valores iniciales y tabla de seno)
// ============================================================================

__host__ __device__ inline uint32_t md5_leftrotate(uint32_t x, uint32_t c) {
    return (x << c) | (x >> (32 - c));
}

// Tabla T[i] = floor(2^32 * abs(sin(i+1)))
__host__ __device__ inline uint32_t md5_T(int i) {
    static const uint32_t T[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };
    return T[i];
}

// Tabla de desplazamientos para rotaciones (rondas 1-4)
__host__ __device__ inline int md5_s(int i) {
    static const int s[64] = {
        7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
        5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
        4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
        6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
    };
    return s[i];
}

// Tabla de índices de entrada (qué palabra de entrada M se usa en cada ronda)
__host__ __device__ inline int md5_k(int i) {
    static const int k[64] = {
        0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
        1,  6, 11,  0,  5, 10, 15,  4,  9, 14,  3,  8, 13,  2,  7, 12,
        5,  8, 11, 14,  1,  4,  7, 10, 13,  0,  3,  6,  9, 12, 15,  2,
        0,  7, 14,  5, 12,  3, 10,  1,  8, 15,  6, 13,  4, 11,  2,  9
    };
    return k[i];
}

// ============================================================================
// Funciones auxiliares de MD5 (F, G, H, I)
// ============================================================================

__host__ __device__ inline uint32_t md5_F(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) | ((~x) & z);
}

__host__ __device__ inline uint32_t md5_G(uint32_t x, uint32_t y, uint32_t z) {
    return (x & z) | (y & (~z));
}

__host__ __device__ inline uint32_t md5_H(uint32_t x, uint32_t y, uint32_t z) {
    return x ^ y ^ z;
}

__host__ __device__ inline uint32_t md5_I(uint32_t x, uint32_t y, uint32_t z) {
    return y ^ (x | (~z));
}

// ============================================================================
// Estructura de estado MD5
// ============================================================================

struct MD5State {
    uint32_t A;
    uint32_t B;
    uint32_t C;
    uint32_t D;
};

// ============================================================================
// Inicialización del estado MD5
// ============================================================================

__host__ __device__ inline MD5State md5_init() {
    MD5State state;
    state.A = 0x67452301;
    state.B = 0xefcdab89;
    state.C = 0x98badcfe;
    state.D = 0x10325476;
    return state;
}

// ============================================================================
// Procesamiento de un bloque de 512 bits (16 x 32 bits)
// ============================================================================

__host__ __device__ inline void md5_process_block(MD5State &state, const uint32_t *M) {
    uint32_t A = state.A;
    uint32_t B = state.B;
    uint32_t C = state.C;
    uint32_t D = state.D;
    
    // 64 rondas
    for (int i = 0; i < 64; i++) {
        uint32_t F_result;
        int g;
        
        // Seleccionar función y índice de entrada según ronda
        if (i < 16) {
            F_result = md5_F(B, C, D);
            g = i;
        } else if (i < 32) {
            F_result = md5_G(B, C, D);
            g = (5 * i + 1) % 16;
        } else if (i < 48) {
            F_result = md5_H(B, C, D);
            g = (3 * i + 5) % 16;
        } else {
            F_result = md5_I(B, C, D);
            g = (7 * i) % 16;
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
    
    state.A += A;
    state.B += B;
    state.C += C;
    state.D += D;
}

// ============================================================================
// Función pública: calcular MD5 de datos (máx 55 bytes para simplificar)
// Para este proyecto: máx 64 bytes de entrada (contrasenas de hasta ~64 caracteres)
// ============================================================================

__host__ __device__ inline MD5State md5_hash(const unsigned char *data, size_t len) {
    /*
     * Decisión de diseño: Usamos un enfoque simplificado que asume len <= 55 bytes.
     * Para datos más largos, se necesitaría padding múltiple y procesamiento de bloques.
     * Para contraseñas de fuerza bruta (típicamente < 20 caracteres), esto es suficiente.
     */
    
    MD5State state = md5_init();
    
    // Preparar bloque: datos + padding estándar MD5
    uint32_t M[16] = {0};
    
    // Copiar datos al bloque (little-endian)
    unsigned char *M_bytes = (unsigned char *)M;
    for (size_t i = 0; i < len; i++) {
        M_bytes[i] = data[i];
    }
    
    // Agregar bit de relleno (0x80 = 10000000 en binario)
    M_bytes[len] = 0x80;
    
    // Colocar la longitud en bits en los últimos 8 bytes (little-endian)
    uint64_t bit_length = len * 8;
    M[14] = (uint32_t)(bit_length & 0xFFFFFFFF);
    M[15] = (uint32_t)((bit_length >> 32) & 0xFFFFFFFF);
    
    // Procesar el bloque
    md5_process_block(state, M);
    
    return state;
}

// ============================================================================
// Comparación de digests MD5 (4 uint32_t)
// ============================================================================

__host__ __device__ inline bool md5_equals(const MD5State &state, 
                                            uint32_t target_A, uint32_t target_B,
                                            uint32_t target_C, uint32_t target_D) {
    return (state.A == target_A) && 
           (state.B == target_B) && 
           (state.C == target_C) && 
           (state.D == target_D);
}

// ============================================================================
// Función helper: convertir string hex a uint32_t
// Usada en host para parsear hash objetivo
// ============================================================================

__host__ inline uint32_t hex_to_uint32(const char *hex) {
    auto hex_digit = [](char c) -> uint32_t {
        if (c >= '0' && c <= '9') {
            return static_cast<uint32_t>(c - '0');
        }
        if (c >= 'a' && c <= 'f') {
            return static_cast<uint32_t>(c - 'a' + 10);
        }
        if (c >= 'A' && c <= 'F') {
            return static_cast<uint32_t>(c - 'A' + 10);
        }
        return 0xFFFFFFFFu;
    };

    uint32_t value = 0;
    for (int byte = 0; byte < 4; byte++) {
        uint32_t hi = hex_digit(hex[byte * 2]);
        uint32_t lo = hex_digit(hex[byte * 2 + 1]);
        if (hi == 0xFFFFFFFFu || lo == 0xFFFFFFFFu) {
            return 0;
        }

        value |= (hi << 4 | lo) << (byte * 8);
    }

    return value;
}

#endif // MD5_CUH
