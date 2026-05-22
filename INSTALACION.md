# Guía de Instalación - GPU MD5 Cracker

## Requisitos del Sistema

### Hardware
- **GPU NVIDIA**: GeForce GTX 1050 o superior (compute capability 6.1+)
  - ✅ RTX 3050, RTX 4060 (recomendado)
  - ✅ GeForce GTX 1050, GTX 1080
  - ❌ GPU más antigua (< 2016)
- **RAM**: ≥ 4 GB
- **Espacio disco**: ≥ 500 MB (código fuente + ejecutables)

### Software (Linux)

#### Ubuntu 24.04 / Debian 12
```bash
# 1. Actualizar paquetes
sudo apt update
sudo apt upgrade -y

# 2. Instalar herramientas de compilación
sudo apt install -y build-essential git

# 3. Instalar CUDA Toolkit
sudo apt install -y nvidia-cuda-toolkit nvidia-utils

# 4. Instalar drivers NVIDIA (si no está instalado)
sudo apt install -y nvidia-driver-550

# 5. Reiniciar
sudo reboot

# 6. Verificar instalación
nvidia-smi
nvcc --version
gcc --version
```

#### Fedora 44
```bash
# 1. Actualizar paquetes
sudo dnf update -y

# 2. Instalar herramientas de compilación
sudo dnf install -y @development-tools git

# 3. Instalar CUDA Toolkit
sudo dnf install -y cuda-toolkit

# 4. Instalar drivers NVIDIA
sudo dnf install -y akmod-nvidia

# 5. Agregar rutas al PATH
echo 'export PATH="/usr/local/cuda/bin:$PATH"' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"' >> ~/.bashrc
source ~/.bashrc

# 6. Verificar
nvidia-smi
nvcc --version
```

#### Arch Linux
```bash
sudo pacman -S cuda gcc make
```

### Verificar Instalación

```bash
# Debe mostrar tu GPU
nvidia-smi

# Debe mostrar versión de CUDA (11.0+)
nvcc --version

# Debe mostrar versión de GCC (9.0+)
gcc --version
```

---

## Descarga y Configuración del Proyecto

### Opción 1: Desde Archivo ZIP

```bash
# Descargar archivo (proporcionado por el profesor)
unzip gpu-md5-cracker.zip
cd gpu-md5-cracker

# Compilar
make
```

### Opción 2: Clonar desde Git (si está en repositorio)

```bash
git clone https://github.com/tu-usuario/gpu-md5-cracker.git
cd gpu-md5-cracker
make
```

### Opción 3: Crear Manualmente los Archivos

```bash
# Crear directorio
mkdir gpu-md5-cracker
cd gpu-md5-cracker

# Copiar archivos (tendrás 9 archivos)
# md5.cuh
# gpu_crack.cu
# secuencial.cpp
# Makefile
# README.md
# TECHNICAL_ANALYSIS.md
# GUIA_PRACTICA.md
# generate_test_hashes.py
# test_examples.sh

# Hacer scripts ejecutables
chmod +x test_examples.sh generate_test_hashes.py
```

---

## Compilación

### Paso 1: Verificar Compute Capability

Tu GPU puede tener una compute capability diferente. Para verificar:

**Método 1: Herramienta online**
https://en.wikipedia.org/wiki/CUDA#GPU_Computing

**Método 2: Desde nvidia-smi**
```bash
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
# Output: 8.6 (para RTX 3050)
```

**Método 3: Tabla de referencia**
```
Compute Capability → sm_XX
3.5, 3.7 (Kepler)      → sm_35
5.0, 5.2 (Maxwell)     → sm_50
6.1, 6.2 (Pascal)      → sm_61  ← Default (RTX 3050)
7.0, 7.5 (Volta/Turing)→ sm_75
8.0, 8.6 (Ampere)      → sm_86  ← Para RTX 30 series
8.9, 9.0 (Ada)         → sm_89  ← Para RTX 40 series
```

### Paso 2: Actualizar Makefile (si es necesario)

**Si tu GPU NO es compute capability 6.1:**

```bash
# Abrir Makefile con tu editor favorito
nano Makefile
# o
gedit Makefile
```

Encontrar esta línea:
```makefile
CUDA_CFLAGS := -std=c++17 -arch=sm_61 -gencode=arch=compute_61,code=sm_61 -O3
```

Cambiar ambos `sm_61` por tu compute capability. Ejemplo para RTX 40 series (sm_89):
```makefile
CUDA_CFLAGS := -std=c++17 -arch=sm_89 -gencode=arch=compute_89,code=sm_89 -O3
```

Guardar y cerrar.

### Paso 3: Compilar

```bash
# Compilar ambas versiones
make

# O solo GPU
make gpu

# O solo CPU
make secuencial

# Ver opciones
make help
```

**Salida esperada:**
```
[GPU] Compilando gpu_crack ...
[GPU] ✓ gpu_crack compilado exitosamente
[CPU] Compilando secuencial ...
[CPU] ✓ secuencial compilado exitosamente
✓ Compilación completada: gpu_crack y secuencial
```

### Paso 4: Verificar Compilación

```bash
# Deben existir estos archivos ejecutables
ls -l gpu_crack secuencial

# Debe mostrar:
# -rwxr-xr-x gpu_crack
# -rwxr-xr-x secuencial
```

---

## Pruebas Iniciales

### Test 1: Función Básica

```bash
# Generar un hash conocido
echo -n "123" | md5sum
# Output: 202cb962ac59075b964b07152d234b70

# Intentar crackearlo
./gpu_crack 202cb962ac59075b964b07152d234b70 3 num brute
```

**Debe encontrar:** "123"

### Test 2: Suite de Tests

```bash
# Ejecutar todos los tests
chmod +x test_examples.sh
./test_examples.sh
```

---

## Configuración de Rutas (Ubuntu/Fedora sin CUDA global)

Si CUDA no está en /usr/local/cuda, actualizar rutas:

```bash
# Encontrar CUDA
find /opt -name cuda 2>/dev/null
find /usr -name cuda 2>/dev/null

# Agregar al PATH (reemplazar /ruta/a/cuda)
export CUDA_HOME=/ruta/a/cuda
export PATH="$CUDA_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

# Hacer permanente (agregar a ~/.bashrc)
echo 'export CUDA_HOME=/ruta/a/cuda' >> ~/.bashrc
echo 'export PATH="$CUDA_HOME/bin:$PATH"' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"' >> ~/.bashrc

source ~/.bashrc
```

---

## Troubleshooting de Instalación

### Error: "nvcc: command not found"

**Causa:** CUDA no instalado o no en PATH

**Solución:**
```bash
# Verificar instalación
which nvcc

# Si no existe, instalar
# Ubuntu:
sudo apt install nvidia-cuda-toolkit

# Fedora:
sudo dnf install cuda-toolkit

# Agregar PATH
export PATH="/usr/local/cuda/bin:$PATH"
```

### Error: "No NVIDIA GPU found"

**Causa:** GPU no detectada

**Solución:**
```bash
# Verificar GPU
lspci | grep -i nvidia

# Si no muestra nada:
# 1. Verificar en BIOS que está habilitada
# 2. Verificar conexión física
# 3. Instalar drivers

# Instalar drivers
ubuntu:
sudo ubuntu-drivers autoinstall

# Fedora:
sudo dnf install akmod-nvidia
```

### Error: "Compute capability not supported"

**Causa:** GPU muy antigua (< compute capability 6.1)

**Solución:**
GPU no es compatible. Se necesita:
- GeForce GTX 1050 o superior
- O cambiar a otra GPU
- O modificar código para compute capability más baja

### Error: "CUDA Out of Memory"

**Causa:** GPU memory insuficiente

**Solución:**
```bash
# Reducir BLOCK_SIZE en gpu_crack.cu
#define BLOCK_SIZE 128  # Cambiar de 256

# Recompilar
make clean && make gpu
```

### Error: "cc1plus: fatal error: cuda_runtime.h: No such file"

**Causa:** Headers CUDA no encontrados

**Solución:**
```bash
# Encontrar CUDA
find /usr -name cuda_runtime.h 2>/dev/null

# Agregar a compilador
export CFLAGS="-I/usr/local/cuda/include"
export LDFLAGS="-L/usr/local/cuda/lib64"

make clean && make
```

---

## Optimizaciones Opcionales

### 1. Habilitar Optimizaciones Avanzadas

Editar Makefile y cambiar:
```makefile
CUDA_CFLAGS := -std=c++17 -arch=sm_61 -gencode=arch=compute_61,code=sm_61 -O3
```

A:
```makefile
CUDA_CFLAGS := -std=c++17 -arch=sm_61 -gencode=arch=compute_61,code=sm_61 -O3 -maxrregcount=128
```

### 2. Compilación con Código Inline

```makefile
CUDA_CFLAGS := -std=c++17 -arch=sm_61 -gencode=arch=compute_61,code=sm_61 -O3 --inline-level=10
```

### 3. Debugging

Si necesitas debugging:
```makefile
CUDA_CFLAGS := -std=c++17 -arch=sm_61 -gencode=arch=compute_61,code=sm_61 -g -G  # Agregar -g -G
```

---

## Siguiente Paso: Usar el Programa

Una vez compilado, ver:
- **README.md** - Guía de uso
- **GUIA_PRACTICA.md** - Ejemplos paso-a-paso

Ejemplo rápido:
```bash
# Generar un hash
echo -n "password" | md5sum

# Crackearlo
./gpu_crack <tu_hash> 8 alnum brute
```

---

## Soporte

Si encuentras problemas:

1. **Verificar CUDA instalado:**
   ```bash
   nvidia-smi
   nvcc --version
   ```

2. **Revisar README.md troubleshooting section**

3. **Verificar compute capability:**
   ```bash
   nvidia-smi --query-gpu=compute_cap --format=csv,noheader
   ```

4. **Recompilar desde cero:**
   ```bash
   make clean
   make help
   make
   ```

---

**¡Listo para usar!** 🚀

Ve a GUIA_PRACTICA.md para ejemplos ejecutables.
