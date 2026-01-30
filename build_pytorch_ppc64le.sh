#!/bin/bash
set -e

# ==========================================
# PyTorch 2.5.1 PowerPC Ultimate Builder
# 功能: 源码清理 -> 补丁修复 -> 编译 Wheel 包 -> 安装
# 适用: 源码已存在于本地 (例如从 Windows 传输过来)
# ==========================================

# --- 配置区域 ---
# 自动定位当前目录
SRC_DIR=$(dirname "$0")
cd "$SRC_DIR"
SRC_DIR=$(pwd) # 转为绝对路径，防止逻辑混乱
# ----------------

echo " === 开始 PyTorch PowerPC 一键编译打包 ==="
echo " 源码目录: $SRC_DIR"


# 安全检查：确认用户真的把脚本放对位置了
if [ ! -f "setup.py" ] || [ ! -d "third_party" ]; then
    echo "错误: 未在当前目录下检测到 PyTorch 源码特征 (setup.py 或 third_party)。"
    echo "请务必将此脚本复制到 PyTorch 源码的【根目录】下运行！"
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 找不到目录 $SRC_DIR"
    exit 1
fi
cd "$SRC_DIR"

# ==========================================
# [Phase 1] 预处理: 格式与环境清洗
# ==========================================
echo " [1/5] 清洗环境与修复文件格式..."

# 1. 修复 Windows CRLF 换行符和权限 (防止脚本报错)
echo "   - 正在修复换行符 (CRLF -> LF)..."
find . -type f -not -path "./.git/*" -exec sed -i 's/\r$//' {} +
echo "   - 修复执行权限..."
find . -name "*.sh" -exec chmod +x {} +
find . -name "*.py" -exec chmod +x {} +
find . -name "configure" -exec chmod +x {} +

# 2. 清理环境变量
unset CFLAGS CXXFLAGS CMAKE_ARGS LDFLAGS CMAKE_INCLUDE_PATH CMAKE_LIBRARY_PATH

# 3. 物理屏蔽 Conda 的 FlatBuffers (防止版本冲突)
CONDA_INC="$CONDA_PREFIX/include"
if [ -d "$CONDA_INC/flatbuffers" ]; then
    echo "   - 临时屏蔽 Conda FlatBuffers..."
    mv "$CONDA_INC/flatbuffers" "$CONDA_INC/flatbuffers.bak"
fi

# ==========================================
# [Phase 2] 核心修补 (六大补丁)
# ==========================================
echo "[2/5] 应用核心补丁..."

# Patch 1: Gloo AVX 禁用 (PowerPC 必须)
GLOO_FILE="third_party/gloo/gloo/allreduce_shm.cc"
if [ -f "$GLOO_FILE" ] && ! grep -q "PATCHED_FOR_PPC" "$GLOO_FILE"; then
    sed -i '1i\// PATCHED_FOR_PPC\n#if defined(__x86_64__) || defined(_M_X64)' "$GLOO_FILE"
    echo "#endif" >> "$GLOO_FILE"
    echo "   [Gloo] AVX 已禁用"
fi

# Patch 2: Protobuf constinit 修复 (GCC 12 必须)
PROTO_FILE="third_party/protobuf/src/google/protobuf/port_def.inc"
if [ -f "$PROTO_FILE" ]; then
    sed -i '/FORCE_DISABLE_CONSTINIT/,$d' "$PROTO_FILE"
    cat >> "$PROTO_FILE" <<EOF

// FORCE_DISABLE_CONSTINIT
#ifdef PROTOBUF_CONSTINIT
#undef PROTOBUF_CONSTINIT
#endif
#define PROTOBUF_CONSTINIT
EOF
    echo "   [Protobuf] constinit 已修复"
fi

# Patch 3: FlatBuffers 版本检查屏蔽 (解决版本冲突)
FB_DIR="torch/csrc/jit/serialization"
if [ -d "$FB_DIR" ]; then
    # 将所有版本断言替换为 true
    grep -l "FLATBUFFERS_VERSION_" "$FB_DIR"/*.h | xargs sed -i 's/FLATBUFFERS_VERSION_[A-Z]* == [0-9]*/true/g'
    echo "   [FlatBuffers] 版本检查已屏蔽"
fi

# Patch 4 & 5: Kineto Shim 重写 + 符号补全 (解决 Switch 错误和链接丢失)
KINETO_FILE="torch/csrc/profiler/kineto_shim.cpp"
if [ -f "$KINETO_FILE" ]; then
    # 直接重写整个文件，包含安全的函数体和所有 Dummy 符号
    cat > "$KINETO_FILE" <<EOF
#include <torch/csrc/profiler/kineto_shim.h>
#include <string>

namespace torch {
namespace autograd {
namespace profiler {

// Patch 4: Safe deviceTypeFromActivity without switch
c10::DeviceType deviceTypeFromActivity(libkineto::ActivityType activity_type) {
  int type = (int)activity_type;
  // 2=CUDA_RUNTIME, 3=CUDA_DRIVER
  if (type == 2 || type == 3) return c10::DeviceType::CUDA;
  return c10::DeviceType::CPU;
}

// Patch 5: Missing symbols dummies
void addMetadataJson(const std::string& key, const std::string& value) {}
void profilerStep() {}

} // namespace profiler
} // namespace autograd
} // namespace torch
EOF
    echo "   [Kineto] Shim 重写与符号补全完成"
fi

# Patch 6: ProcessGroupGloo 类型修复 (*store_ -> store_)
PG_FILE="torch/csrc/distributed/c10d/ProcessGroupGloo.cpp"
if [ -f "$PG_FILE" ]; then
    # 恢复原样的解引用符(如果之前被误删)，这里我们确保它是正确的解引用状态
    # 注意：根据最终成功的经验，如果之前是 unique_ptr，这里通常需要保持原码。
    # 如果遇到 "no known conversion... unique_ptr to Store&"，说明需要解引用 (*)。
    # 只要确保代码里是 PrefixStore(..., *store_) 即可。
    if grep -q "PrefixStore(std::to_string(i), store_)" "$PG_FILE"; then
         sed -i 's/PrefixStore(std::to_string(i), store_)/PrefixStore(std::to_string(i), *store_)/g' "$PG_FILE"
         echo "   [Gloo] Store 类型解引用已修复"
    fi
fi

# ==========================================
# [Phase 3] 准备工具链
# ==========================================
echo "[3/5] 检查构建依赖..."
conda install -y cmake ninja pyyaml numpy typing_extensions wheel || pip install cmake ninja pyyaml numpy typing_extensions wheel

# ==========================================
# [Phase 4] 编译 Wheel 包
# ==========================================
echo "[4/5] 开始编译 Wheel 包 (这需要一段时间)..."

# 关键环境变量
export CMAKE_PREFIX_PATH=${CONDA_PREFIX:-"$(dirname $(which conda))/../"}
export CUDA_HOME=/usr/local/cuda
export USE_CUDA=1
export USE_CUDNN=1
export USE_DISTRIBUTED=1
export USE_NCCL=1
export USE_SYSTEM_NCCL=0
export USE_GLOO=1
export USE_TENSORPIPE=1
export USE_OPENCV=1
# 禁用不稳定组件
export USE_KINETO=0
export USE_FBGEMM=0
export USE_VULKAN=0
export USE_FBJNI=0
export USE_ITT=0
export USE_IDEEP=0
export USE_MIMALLOC=0
export USE_NNPACK=0
export USE_XNNPACK=0
export USE_MKLDNN=0
export USE_QNNPACK=0
export BUILD_TEST=0
export BUILD_CAFFE2=0
export OpenBLAS_HOME=$CONDA_PREFIX
export OpenBLAS_DIR=$CONDA_PREFIX
export BLAS=OpenBLAS

# 编译器参数
COMPILER_FLAGS="-Dconstinit= -Wno-deprecated-declarations -std=gnu++17 -DNO_WARN_X86_INTRINSICS"
export CFLAGS="${COMPILER_FLAGS}"
export CXXFLAGS="${COMPILER_FLAGS}"
export CMAKE_ARGS="-DCMAKE_CXX_FLAGS='${COMPILER_FLAGS}' -DCMAKE_C_FLAGS='${COMPILER_FLAGS}'"
export MAX_JOBS=8

# 使用 bdist_wheel 生成 .whl 文件
python setup.py bdist_wheel 2>&1 | tee build_wheel.log

# ==========================================
# [Phase 5] 安装与收尾
# ==========================================
echo "[5/5] 安装生成的 Wheel 包..."

WHEEL_FILE=$(ls dist/*.whl | head -n 1)
if [ -f "$WHEEL_FILE" ]; then
    echo "   发现安装包: $WHEEL_FILE"
    pip install "$WHEEL_FILE" --force-reinstall
    
    echo " 恢复环境..."
    if [ -d "$CONDA_INC/flatbuffers.bak" ]; then
        mv "$CONDA_INC/flatbuffers.bak" "$CONDA_INC/flatbuffers"
    fi
    
    echo "全部完成！"
    echo "Wheel 包位置: $SRC_DIR/$WHEEL_FILE"
    echo "你可以将这个 .whl 文件复制到其他同样环境的机器上直接 pip install，无需再次编译。"
    echo "验证命令: python -c 'import torch; print(torch.cuda.is_available())'"
else
    echo "❌ 编译似乎完成了，但在 dist/ 目录下没找到 .whl 文件。"
    exit 1
fi
