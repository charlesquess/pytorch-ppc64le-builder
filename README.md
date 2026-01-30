# PyTorch 2.5.1 Builder for PowerPC (ppc64le)
# PyTorch 2.5.1 PowerPC (ppc64le) 一键编译脚本

This repository provides a reliable shell script to build PyTorch from source on IBM PowerPC architecture. It automatically patches known issues regarding GCC 12 compatibility, Gloo/AVX conflicts, and FlatBuffers version mismatches.

本仓库提供了一个在 IBM PowerPC 架构上从源码编译 PyTorch 的可靠脚本。它自动修补了 GCC 12 兼容性、Gloo/AVX 指令集冲突以及 FlatBuffers 版本不匹配等已知问题。

## 🖥️ Build Environment / 编译环境

Tested successfully under the following configuration:
该脚本已在以下配置中验证通过：

| Component (组件) | Version / Details (版本/详情) | Note (备注) |
| :--- | :--- | :--- |
| **PyTorch Source** | `v2.5.1` (Alpha/Source) | Compiled from source |
| **Architecture** | `ppc64le` (IBM Power) | Little Endian |
| **OS** | Linux (Debian/Ubuntu/RHEL) | |
| **Compiler** | **GCC 12+** | Requires patches (Included) |
| **CUDA Toolkit** | 12.1 | *Verify with `nvcc --version`* |
| **Python** | 3.9 | Conda environment recommended |
| **GPU Hardware** | NVIDIA Tesla V100 (SXM2) | Supports multi-GPU (NCCL) |
| **Build System** | Ninja + CMake | |

---

## 🚀 Key Features / 主要功能

It automatically applies patches for the following known issues:
脚本自动修复了以下已知的高难度编译问题：

1.  **Gloo AVX Error**: Disables AVX instructions in `allreduce_shm.cc` which are incompatible with PowerPC.
    * *修复 Gloo 库强制调用 Intel AVX 指令集导致在 PowerPC 上报错的问题。*
2.  **GCC 12 `constinit` Compatibility**: Fixes `Protobuf` and `ONNX` build failures caused by C++20 strict checks.
    * *修复 GCC 12 严格检查 `constinit` 关键字导致 Protobuf/ONNX 编译失败的问题。*
3.  **FlatBuffers Version Mismatch**: Bypasses the strict version check (`static_assert`) between PyTorch source (v2.5) and system/conda headers.
    * *暴力解决 FlatBuffers 版本冲突（如 v3 vs v26），屏蔽所有版本检查断言。*
4.  **Kineto/Profiler Issues**: Rewrites `kineto_shim.cpp` to fix missing symbols (`profilerStep`, `addMetadataJson`) and syntax errors.
    * *重写 Kineto Shim 文件，补全缺失的符号链接，修复 switch 语法错误。*
5.  **ProcessGroupGloo Type Mismatch**: Fixes pointer/reference mismatch in `ProcessGroupGloo.cpp`.
    * *修复 Gloo 进程组中的指针类型不匹配错误。*

---

## 📋 Prerequisites / 环境要求

* **OS**: Linux (Debian/Ubuntu/CentOS/RHEL) on ppc64le
* **Architecture**: IBM Power (ppc64le)
* **GPU**: NVIDIA Tesla V100/A100 (Verified on V100)
* **Environment**: Conda (Python 3.9 recommended)
* **Compiler**: GCC 12+

---

## 🛠️ Usage / 使用方法

### 1. Download PyTorch Source / 下载源码
Clone the PyTorch repository (recursive is important):
首先下载 PyTorch 源码（注意必须包含子模块）：

```bash
git clone --recursive --branch v2.5.1 [https://github.com/pytorch/pytorch.git](https://github.com/pytorch/pytorch.git)
cd pytorch
```
### 2. Download the Script / 下载脚本
Download `build_pytorch_ppc64le.sh` and place it **inside the root of your PyTorch source directory**.
下载 `build_pytorch_ppc64le.sh` 并将其**放入 PyTorch 源码的根目录中**。

> **Why?** The script relies on relative paths to apply patches correctly.
> **为什么？** 脚本依赖相对路径来精准应用补丁，放入根目录最为稳妥。

Structure should look like this:
目录结构应该像这样：
```text
pytorch/
├── .git/
├── torch/
├── third_party/
├── setup.py
└── build_pytorch_ppc64le.sh  <-- Put it here (放这里)
```
### 3. Run Build / 开始编译
Make sure you are in the conda environment. 确保你已经激活了 Conda 环境。
```bash
cd pytorch
chmod +x build_pytorch_ppc64le.sh
./build_pytorch_ppc64le.sh
```
### 4. Install / 安装
After a successful build, the script will generate a .whl file in the dist/ folder and try to install it automatically. 编译成功后，脚本会在 dist/ 目录下生成 .whl 安装包并尝试自动安装。

You can also install it manually: 你也可以手动安装：

```bash
pip install dist/torch-2.5.0*.whl
```
## 🔍 Verification / 验证
Run the following python code to verify CUDA support: 运行以下代码验证 CUDA 支持：

```python
import torch
print(f"PyTorch: {torch.__version__}")
print(f"CUDA Available: {torch.cuda.is_available()}")
print(f"Device Count: {torch.cuda.device_count()}")

# Test Tensor Calculation
x = torch.rand(5, 3).cuda()
print(x)
```
## Notes / 注意事项
* Environment Variables: The script automatically sets CMAKE_PREFIX_PATH based on your current Conda environment.环境变量: 脚本会根据当前的 Conda 环境自动设置 CMAKE_PREFIX_PATH。
* Windows to Linux: If you downloaded the source on Windows and transferred it to Linux, run this script directly. It includes a fix for CRLF line endings and file permissions.文件格式: 如果你的源码是从 Windows 传输过来的，脚本内置了 CRLF 转 LF 的修复功能，直接运行即可。
* FlatBuffers: The script might rename your Conda's include/flatbuffers to flatbuffers.bak temporarily to avoid conflicts. It restores it after compilation (if successful).关于 FlatBuffers: 为了防止冲突，脚本可能会临时将 Conda 环境中的 flatbuffers 头文件目录重命名为 .bak，编译结束后会尝试恢复。

## Contributing / 贡献
If you find this script helpful or encounter new issues on other PowerPC machines, feel free to open an issue or PR. 如果你觉得这个脚本有帮助，或者在其他 PowerPC 机器上遇到了新问题，欢迎提交 Issue 或 PR。