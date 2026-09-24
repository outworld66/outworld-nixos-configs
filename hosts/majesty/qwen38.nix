{ pkgs, ... }:

let
  llama = pkgs.llama-cpp.override {
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
        --ctx-size 8192 \
        --n-gpu-layers 999 \
        --device ROCm0 \
        --flash-attn on \
        --parallel 1 \
        --jinja
    '';
  };
in
{
  environment.systemPackages = [
    llama
    qwen38
  ];
}
