cmake_minimum_required(VERSION 3.20)
project(dec_probe LANGUAGES CXX)
# CLM-001/002 夹具：分别用 VS 生成器与 Ninja 生成器配置，
# 验证 CMAKE_EXPORT_COMPILE_COMMANDS=ON 时 compile_commands.json 是否产出。
add_executable(probe main.cpp)
