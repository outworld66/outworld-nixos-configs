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
        --ctx-size 32768 \
        --n-gpu-layers 999 \
        --device ROCm0 \
        --cache-type-k q4_0 \
        --cache-type-v q4_0 \
        --flash-attn on \
        --parallel 1 \
        --spec-draft-hf Anbeeld/Qwen3.8-27B-DSpark-GGUF:Q4_K_M \
        --spec-type draft-dspark \
        --spec-draft-device ROCm0 \
        --spec-draft-ngl all \
        --spec-draft-n-max 4 \
        --jinja
    '';
  };
  qwen38Solstice = pkgs.writeShellApplication {
    name = "qwen38-solstice-mtp-server";
    runtimeInputs = [ llama ];
    text = ''
      exec llama-server \
        --hf-repo Solstice-AI/Qwen3.8-27B-TURBO-Fable-Cold-Fusion-735-882-Heretic-Uncensored-GGUF-UltraOptimised-DSpark-MTP \
        --hf-file Qwen3.8-27B-TurboFCFusion-735-882-Here-Uncen-NEO-CODER-MAX-MTP-Q4_K_M.gguf \
        --alias qwen3.8-27b-solstice \
        --host 127.0.0.1 \
        --port 8082 \
        --ctx-size 131072 \
        --n-gpu-layers 999 \
        --device ROCm0 \
        --cache-type-k q4_0 \
        --cache-type-v q4_0 \
        --flash-attn on \
        --parallel 1 \
        --spec-type draft-mtp \
        --spec-draft-n-max 2 \
        --jinja
    '';
  };
in
{
  environment.systemPackages = [
    llama
    qwen38
    qwen38Speculative
    qwen38Solstice
  ];
}
