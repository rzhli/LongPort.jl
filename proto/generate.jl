#!/usr/bin/env julia

using ProtoBuf

# 生成Julia代码从proto文件
function generate_julia_code()
    proto_dir = @__DIR__
    src_dir = joinpath(dirname(proto_dir), "src", "Proto")

    # 确保输出目录存在
    mkpath(src_dir)

    # 生成各个proto文件的Julia代码
    proto_files = ("api.proto", "control.proto", "error.proto", "subscribe.proto")

    for proto_file in proto_files
        proto_path = joinpath(proto_dir, proto_file)
        if isfile(proto_path)
            println("生成 ", proto_file, " 的 Julia 代码...")

            # 生成代码
            julia_file = replace(proto_file, ".proto" => "_pb.jl")
            output_path = joinpath(src_dir, julia_file)

            try
                # 使用ProtoBuf.jl生成Julia代码
                run(`protoc --julia_out=$src_dir $proto_path`)
                println("✓ 生成成功: ", output_path)
            catch e
                println("✗ 生成失败: ", proto_file, " - ", e)
            end
        end
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    generate_julia_code()
end
