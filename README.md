# Sysmac V14 Ultra Rapi MAX PRO – 8‑AI Ensemble Controller

> **OMRON SYSMAC Structured Text** – Advanced process control integrating 8 AI architectures (Liquid, KAN, Mamba, Koopman, Transformer, PINN, MoE, Diffusion) with online Reinforcement Learning.

## ✨ Key Features
- **8 AI ensembles** fused in a single PLC control loop.
- **Online learning** (LMS + RL reward) with weight bounds `0.1..10`.
- **Adaptive AIMD gain** and **safety logic** for robust stability.
- **Built‑in FOPDT plant simulation** for offline testing.
- **Auto‑scaling** of parameters based on setpoint (SP).

## 📊 Test Results (SP = 2200)
| Metric        | Value   |
|---------------|---------|
| Final PV      | 2199.7  |
| K_gain        | 24.2    |
| T_timeconst   | 16.8    |
| IAE           | 27000   |
| y_mamba       | 0.36    |
| reward        | -0.002  |

## 🧠 AI Architecture (~8192 parameters total)
| Component            | Size          | Description                              |
|----------------------|---------------|------------------------------------------|
| Liquid NN            | 896           | 7 ensembles × 128 neurons, tau 0.2–4.0  |
| KAN                  | 1920 splines  | Kolmogorov–Arnold Network                |
| Mamba‑2              | 32 states     | State‑space with C 0.005–0.02           |
| Koopman              | 64 encoder + 4096 dynamics | Observable linear dynamics      |
| Transformer          | 32            | Self‑attention over history              |
| PINN                 | 64            | Physics‑Informed Neural Network          |
| MoE Gate             | 192 + 32 C    | Mixture of Experts (6 experts)           |
| Diffusion Policy     | 128 + 3 denoise steps | Stochastic action smoothing        |

## ⚙️ Key Parameters
- `SampleTime` = 0.1 s
- `MV_Min` / `MV_Max` = 0 – 100%
- `lr_blend` = 0.0003, `lr_moe` = 0.0005, `lr_rl` = 0.0001
- Initial `w_blend[0..5]` = [5.0, 5.0, 5.0, 2.0, 2.0, 1.0]
- Weight bounds: `LIMIT(0.1, ..., 10.0)` – **never zero**

## 🚀 How to Use
1. Open the project in **Sysmac Studio** (V14 or newer).
2. Import `src/Sysmac_V14_Ultra_Rapi_MAX_PRO_FINAL.st` into a POU.
3. Set `SP` (setpoint) as needed (default 2200).
4. Enable `Enable` and set `SIM_MODE` to `TRUE` for simulation.
5. Run the PLC and monitor `PV`, `MV`, and `IAE`.

> **Note:** Safety clamps prevent wind‑up and extreme predictions.

## 📄 License
MIT – free to use and modify with attribution.

## 🙏 Contributing
Pull requests and issues are welcome. For major architecture changes, please include comparative test results.
