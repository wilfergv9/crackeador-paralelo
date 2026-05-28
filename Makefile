# ============================================================================
# Makefile - GPU MD5 Cracker
# Soporta: make (ambas), make gpu, make secuencial, make clean
# ============================================================================

# Compiladores
NVCC := nvcc
CXX := g++
NVCC_AVAILABLE := $(shell command -v $(NVCC) >/dev/null 2>&1 && echo yes)

# Banderas
CUDA_ARCH ?= 86
CUDA_CFLAGS := -allow-unsupported-compiler -std=c++17 -gencode=arch=compute_$(CUDA_ARCH),code=sm_$(CUDA_ARCH) -O3
CUDA_LDFLAGS := -lcuda -lcudart

CXX_CFLAGS := -std=c++17 -O3 -march=native

# Archivos de salida
GPU_TARGET := gpu_crack
CPU_TARGET := secuencial

# Archivos fuente
GPU_SRCS := gpu_crack.cu
CPU_SRCS := secuencial.cpp

# Headers
HEADERS := md5.cuh

# ============================================================================
# Targets
# ============================================================================


.PHONY: all gpu cpu clean help

ifeq ($(NVCC_AVAILABLE),yes)
all: $(GPU_TARGET) $(CPU_TARGET)

else
all: $(CPU_TARGET)
endif
	@echo "✓ Compilación completada: gpu_crack y secuencial"

gpu: $(GPU_TARGET)
	@echo "✓ Compilado: gpu_crack"

cpu: $(CPU_TARGET)
	@echo "✓ Compilado: secuencial"

$(GPU_TARGET): $(GPU_SRCS) $(HEADERS)
	@echo "[GPU] Compilando $@ ..."
	$(NVCC) $(CUDA_CFLAGS) -o $@ $< $(CUDA_LDFLAGS)
	@echo "[GPU] ✓ $@ compilado exitosamente"

$(CPU_TARGET): $(CPU_SRCS) $(HEADERS)
	@echo "[CPU] Compilando $@ ..."
	$(CXX) $(CXX_CFLAGS) -o $@ $<
	@echo "[CPU] ✓ $@ compilado exitosamente"

clean:
	@echo "[CLEAN] Removiendo ejecutables..."
	rm -f $(GPU_TARGET) $(CPU_TARGET)
	@echo "[CLEAN] ✓ Limpeza completada"

help:
	@echo "╔═══════════════════════════════════════════════════════════╗"
	@echo "║  Makefile - GPU MD5 Cracker                             ║"
	@echo "╚═══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Targets disponibles:"
	@echo "  make              - Compila ambas versiones (GPU + CPU)"
	@echo "  make gpu          - Compila solo versión CUDA"
	@echo "  make secuencial   - Compila solo versión CPU"
	@echo "  make clean        - Elimina ejecutables compilados"
	@echo "  make help         - Muestra este mensaje"
	@echo ""
	@echo "Requisitos:"
	@echo "  - NVIDIA CUDA Toolkit (nvcc)"
	@echo "  - g++ con soporte C++17"
	@echo ""
	@echo "Compute Capability:"
	@echo "  - Configurable via `CUDA_ARCH` (por defecto: sm_86)"
	@echo "  - Para compilar para otra arquitectura, ejecuta: `make gpu CUDA_ARCH=75`"
	@echo ""

.SILENT: help
