#!/bin/bash

# ============================================
# 环境变量验证脚本
# ============================================
# 用于验证 Sepolia 部署所需的环境变量
# 使用方法: source scripts/validate-env.sh
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 验证结果标志
VALIDATION_PASSED=true

# 打印错误信息
print_error() {
    echo -e "${RED}错误: $1${NC}"
    VALIDATION_PASSED=false
}

# 打印警告信息
print_warning() {
    echo -e "${YELLOW}警告: $1${NC}"
}

# 打印成功信息
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 验证私钥格式
validate_private_key() {
    local key="$1"
    
    # 检查是否为空
    if [ -z "$key" ]; then
        print_error "PRIVATE_KEY 未设置"
        echo "请在 .env 文件中设置 PRIVATE_KEY"
        echo "示例: PRIVATE_KEY=0xabcdef1234567890..."
        return 1
    fi
    
    # 移除 0x 前缀（如果存在）
    local clean_key="${key#0x}"
    
    # 检查长度（应为64个十六进制字符）
    if [ ${#clean_key} -ne 64 ]; then
        print_error "PRIVATE_KEY 格式错误: 长度应为64个十六进制字符"
        echo "当前长度: ${#clean_key}"
        return 1
    fi
    
    # 检查是否为有效的十六进制字符串
    if ! [[ "$clean_key" =~ ^[0-9a-fA-F]+$ ]]; then
        print_error "PRIVATE_KEY 格式错误: 包含非十六进制字符"
        return 1
    fi
    
    # 检查是否为示例私钥
    if [ "$clean_key" = "abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabca" ]; then
        print_error "PRIVATE_KEY 是示例值，请使用真实的测试私钥"
        return 1
    fi
    
    print_success "PRIVATE_KEY 格式验证通过"
    return 0
}

# 验证 RPC URL
validate_rpc_url() {
    local url="$1"
    local name="$2"
    
    # 检查是否为空
    if [ -z "$url" ]; then
        print_warning "$name 未设置，将使用默认值"
        return 0
    fi
    
    # 检查是否为有效的 URL 格式
    if ! [[ "$url" =~ ^https?:// ]]; then
        print_error "$name 格式错误: 应以 http:// 或 https:// 开头"
        return 1
    fi
    
    print_success "$name 格式验证通过: $url"
    return 0
}

# 主验证函数
validate_sepolia_env() {
    echo "======================================"
    echo "验证 Sepolia 部署环境变量"
    echo "======================================"
    echo ""
    
    # 加载 .env 文件（如果存在）
    if [ -f ".env" ]; then
        print_success "找到 .env 文件"
        # 使用 export 导出变量
        set -a
        source .env
        set +a
    else
        print_warning ".env 文件不存在"
        echo "请复制 .env.example 为 .env 并填写配置"
        echo "命令: cp .env.example .env"
        VALIDATION_PASSED=false
    fi
    
    echo ""
    
    # 验证 PRIVATE_KEY
    validate_private_key "$PRIVATE_KEY"
    
    echo ""
    
    # 验证 SEPOLIA_RPC_URL
    validate_rpc_url "$SEPOLIA_RPC_URL" "SEPOLIA_RPC_URL"
    
    echo ""
    echo "======================================"
    
    # 返回验证结果
    if [ "$VALIDATION_PASSED" = true ]; then
        print_success "所有必要的环境变量验证通过"
        echo "======================================"
        return 0
    else
        print_error "环境变量验证失败，请修复上述错误后重试"
        echo "======================================"
        return 1
    fi
}

# 如果直接运行此脚本（而非被 source），则执行验证
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_sepolia_env
    exit $?
fi
