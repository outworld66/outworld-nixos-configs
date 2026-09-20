{
  pkgs,
  user,
  ...
}:

let
  stateDir = "/var/lib/airllm";
  venv = "${stateDir}/venv";
  python = pkgs.python3.withPackages (ps: [ ps.torchWithRocm ]);
  setup = pkgs.writeShellApplication {
    name = "airllm-setup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.uv
    ];
    text = ''
      set -eu
      mkdir -p ${stateDir}
      if [ ! -x ${venv}/bin/python ]; then
        uv venv --system-site-packages ${venv} --python ${python.interpreter}
      fi
      uv pip install --python ${venv}/bin/python \
        airllm \
        "transformers @ git+https://github.com/huggingface/transformers.git"
      ${venv}/bin/python -c 'import torch; assert torch.cuda.is_available(), torch.__version__; print(torch.cuda.get_device_name(0))'
    '';
  };
  run = pkgs.writeShellApplication {
    name = "airllm-qwen38";
    text = ''
      export HF_HOME=${stateDir}/huggingface
      export TRANSFORMERS_CACHE=${stateDir}/huggingface
      export PYTORCH_ALLOC_CONF=expandable_segments:True
      exec ${venv}/bin/python ${pkgs.writeText "airllm-qwen38.py" ''
        import os
        import torch
        from airllm import AutoModel

        assert torch.cuda.is_available(), "ROCm/PyTorch cannot see the GPU"
        model = AutoModel.from_pretrained(
            "Qwen/Qwen3.8-Flash-Next",
            delete_original=True,
            layer_shards_saving_path="/var/lib/airllm/layers",
        )
        tokens = model.tokenizer(
            [os.environ.get("AIRLLM_PROMPT", "Say hello in Russian.")],
            return_tensors="pt",
            return_attention_mask=False,
            truncation=True,
            max_length=128,
            padding=False,
        )
        output = model.generate(
            tokens["input_ids"].cuda(),
            max_new_tokens=128,
            use_cache=True,
            return_dict_in_generate=True,
        )
        print(model.tokenizer.decode(output.sequences[0]))
      ''}
    '';
  };
in
{
  environment.systemPackages = [
    setup
    run
    pkgs.rocmPackages.rocminfo
  ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 ${user} users -"
    "d ${stateDir}/layers 0755 ${user} users -"
  ];

  # Manual experiment only; enable only after the ROCm/PyTorch check.
  # systemd.services.airllm-qwen38 = { ... };
}
