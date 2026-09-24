{
  inputs,
  pkgs,
  system,
  ...
}:

let
  llama =
    (import inputs.llama-cpp-nixpkgs {
      inherit system;
      inherit (pkgs) config;
    }).llama-cpp.override
      {
        rocmSupport = true;
        rocmGpuTargets = [ "gfx1100" ];
      };
  qwen38 = pkgs.writeShellApplication {
    name = "qwen38-server";
    runtimeInputs = [ llama ];
    text = ''
      exec llama-server \
        -hf ggml-org/Qwen3.8-27B-GGUF:Q4_K_M \
        --alias qwen3.8-27b \
        --host 127.0.0.1 \
        --port 8080 \
        --ctx-size 32768 \
        --n-gpu-layers 999 \
        --device ROCm0 \
        --flash-attn on \
        --parallel 1 \
        --jinja
    '';
  };
  qwen38Speculative = pkgs.writeShellApplication {
    name = "qwen38-speculative-server";
    runtimeInputs = [ llama ];
    text = ''
      exec llama-server \
        -hf ggml-org/Qwen3.8-27B-GGUF:Q4_K_M \
        --alias qwen3.8-27b-speculative \
        --host 127.0.0.1 \
        --port 8081 \
        --ctx-size 262144 \
        --n-gpu-layers 999 \
        --device ROCm0 \
        --no-kv-offload \
        --cache-type-k q4_0 \
        --cache-type-v q4_0 \
        --flash-attn on \
        --parallel 1 \
        --spec-draft-hf Anbeeld/Qwen3.8-27B-DSpark-GGUF:Q4_K_M \
        --spec-type draft-dspark \
        --spec-draft-device ROCm0 \
        --spec-draft-ngl all \
        --spec-draft-n-max 7 \
        --jinja
    '';
  };
in
{
  environment.systemPackages = [
    llama
    qwen38
    qwen38Speculative
  ];
}
