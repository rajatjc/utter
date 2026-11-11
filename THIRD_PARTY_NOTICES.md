# Third-party notices

Utter's own code is proprietary (see [LICENSE](LICENSE)).

## Built into the app

| Component | Source | License |
|---|---|---|
| FluidAudio 0.17.7 | github.com/FluidInference/FluidAudio | Apache-2.0 (its license text ships in the app at `Contents/Resources/Licenses/FluidAudio-LICENSE.txt`) |

## Downloaded by the app

| Component | Source | License |
|---|---|---|
| NVIDIA Parakeet TDT 0.6B v3, Core ML conversion by FluidInference | huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml | CC-BY-4.0. Attribution: "Parakeet TDT 0.6B v3" by NVIDIA |

The components below are downloaded onto the user's Mac by the optional Whisper installer (`scripts/setup-whisper.sh`) from PyPI and Hugging Face, or are provided by Apple or Anthropic.

## Installed by the Whisper installer

| Component | Source | License |
|---|---|---|
| Whisper large-v3-turbo model weights (OpenAI), MLX conversion | huggingface.co/mlx-community/whisper-large-v3-turbo | MIT |
| mlx-whisper | github.com/ml-explore/mlx-examples | MIT |
| MLX | github.com/ml-explore/mlx | MIT |
| PyTorch (torch) | pytorch.org | BSD-3-Clause |
| NumPy | numpy.org | BSD-3-Clause |
| SciPy | scipy.org | BSD-3-Clause |
| Numba | numba.pydata.org | BSD-2-Clause |
| tiktoken | github.com/openai/tiktoken | MIT |
| huggingface_hub | github.com/huggingface/huggingface_hub | Apache-2.0 |
| tqdm | github.com/tqdm/tqdm | MIT and MPL-2.0 |
| more-itertools | github.com/more-itertools/more-itertools | MIT |

These packages pull in their own dependencies, each under its own license; `pip-licenses` run inside `~/Library/Application Support/Utter/whisper-env` lists them all. If a future version bundles any of these components inside the app, their license texts must ship with it.

## Platform services

- **Apple frameworks** (SwiftUI, AppKit, Speech, AVFoundation, FoundationModels): used under the Apple Developer Program terms.
- **Anthropic API** (optional, used only with the user's own API key): subject to Anthropic's terms of service.
