# Force glslang's install option off before it is evaluated.
#
# Shaderc v2026.3 sets GLSLANG_ENABLE_INSTALL to the generator expression
# $<NOT:${SKIP_GLSLANG_INSTALL}> in third_party/CMakeLists.txt. option() stores
# that string as-is, and if() treats it as true, so glslang generates
# install(EXPORT) rules that reference SPIRV-Tools-opt. SPIRV-Tools is built as
# a sibling subproject and does not export that target, so CMake generation
# fails. EclipseNatives never installs anything; force the option off in
# glslang's own directory scope. No upstream file is modified.
set(GLSLANG_ENABLE_INSTALL OFF)
