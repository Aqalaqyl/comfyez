# comfyez

A single Bash script that installs [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
and [ComfyUI-Manager](https://github.com/Comfy-Org/ComfyUI-Manager) on Linux, inside
a Python virtual environment, in a folder of your choice.

## Requirements

- Linux
- `git`
- Python 3.13 with the `venv` module. The virtual environment is always created with
  Python 3.13; the script refuses to run with any other version.
  - Ubuntu/Debian: `sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt install python3.13 python3.13-venv`
  - Any distro via uv: `uv python install 3.13`, then run the script with `-p "$(uv python find 3.13)"`

On NVIDIA GPUs PyTorch is installed from the CUDA 13.2 (`cu132`) wheel index.

## Usage

```bash
chmod +x install_comfyui.sh
./install_comfyui.sh
```

The script will ask where to install (default: `~`) and which GPU backend to use
(auto-detected: `nvidia`, `amd`, `intel` or `cpu`). A `ComfyUI/` folder is created
inside the chosen directory, with the virtual environment at `ComfyUI/venv/` and
ComfyUI-Manager at `ComfyUI/custom_nodes/ComfyUI-Manager/`.

Non-interactive example:

```bash
./install_comfyui.sh -d /opt/ai -g nvidia -y
```

| Option | Description |
| --- | --- |
| `-d, --dir DIR` | Parent folder to install into |
| `-g, --gpu TYPE` | `nvidia`, `amd`, `intel` or `cpu` (default: auto-detect) |
| `-p, --python BIN` | Python 3.13 interpreter to use (default: `python3.13`) |
| `-y, --yes` | Non-interactive, accept defaults |
| `-h, --help` | Show help |

Set `TORCH_INDEX_URL` to use a custom PyTorch wheel index (default for NVIDIA is
`https://download.pytorch.org/whl/cu132`).

Re-running the script on an existing install pulls the latest ComfyUI and
ComfyUI-Manager and refreshes dependencies.

## Running ComfyUI

```bash
<install dir>/ComfyUI/run_comfyui.sh
```

Any extra arguments are passed to ComfyUI, e.g. `--listen 0.0.0.0`, `--cpu`, `--lowvram`.
Then open <http://127.0.0.1:8188>.
