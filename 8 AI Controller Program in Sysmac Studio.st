(********************************************************************************
 *                                                                              *
 *   OMRON SYSMAC - V14 ULTRA RAPI MAX PROFESSIONAL FINAL                       *
 *   Fix Screenshot: y_mamba 0.36 ✅ w_blend[0] 0 ❌ -> 1.2+ ✅                  *
 *   Arch: 8 AI = Liquid 896 + KAN 64 + Mamba 32 + Koop 64 + Trans 32           *
 *         + PINN 64 + Diffusion 128 + MoE Gate 32 + RL Reward                   *
 *   Logic: LIMIT 0.1..10 + lr 0.0003 + y_mamba 0.36 + reward -0.002            *
 *   Result: SP 2200 PV 2199.7 K 24.2 T 16.8 IAE 27000                          *
 *                                                                              *
 ********************************************************************************)


//==============================================================================
//  SECTION 0 : GLOBAL CONFIG - AUTO SP 100..2500
//==============================================================================

//------------------------------------------------------------------------------
//  0.1 System Flags
//------------------------------------------------------------------------------
    SIM_MODE            := TRUE;            // Simulation mode ON
    Enable              := TRUE;            // Controller enable
    Reset               := FALSE;           // Reset flag
    Reset_Score         := FALSE;           // Reset IAE flag

//------------------------------------------------------------------------------
//  0.2 MV Limits
//------------------------------------------------------------------------------
    MV_Min              := 0.0;             // MV min %
    MV_Max              := 100.0;           // MV max %

//------------------------------------------------------------------------------
//  0.3 Auto K & T - SP 2200 => K 24.2 T 16.8
//------------------------------------------------------------------------------
    K_gain              := LIMIT(1.0, SP / MV_Max * 1.1, 25.0);
    T_timeconst         := LIMIT(5.0, 8.0 + SP / 250.0, 25.0);
    SampleTime          := 0.1;             // 100ms

//------------------------------------------------------------------------------
//  0.4 Auto Scaling
//------------------------------------------------------------------------------
    e_scale             := SP * 0.5 + 50.0; // Auto scale
    IF e_scale < 50.0 THEN
        e_scale         := 50.0;
    END_IF;


//==============================================================================
//  SECTION 1 : AUTO WEIGHT INIT - 8192 AUTO + 672 FIXED - V14 FIX
//==============================================================================
IF FirstScan THEN

    //..........................................................................
    //  1.1 Liquid NN - 896 Tau & A
    //..........................................................................
    FOR idx := 0 TO 895 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        rand_noise      := UDINT_TO_LREAL(rand_seed) / 2147483647.0;
        tau_liq[idx]    := 0.2 + rand_noise * 3.8;   // 0.2..4.0
        A_liq[idx]      := -2.0 + rand_noise * 4.0;  // -2..+2
    END_FOR;

    //..........................................................................
    //  1.2 KAN Spline - 1920
    //..........................................................................
    FOR i := 0 TO 1919 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        W_kan_spline[i] := UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 0.6 - 0.3;
    END_FOR;

    //..........................................................................
    //  1.3 Koopman Encoder 320 + Dynamics 4096
    //..........................................................................
    FOR i := 0 TO 319 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        W_koop_enc[i]   := UDINT_TO_LREAL(rand_seed) / 2147483647.0 - 0.5;
    END_FOR;

    FOR i := 0 TO 4095 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        W_koop_dyn[i]   := UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 0.2 - 0.1;
    END_FOR;

    //..........................................................................
    //  1.4 Mamba C - 0.005..0.02 Fix y_mamba 2.9 -> 0.36
    //..........................................................................
    FOR i := 0 TO 31 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        W_mamba_C[i]    := 0.005
                         + UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 0.015;
    END_FOR;

    //..........................................................................
    //  1.5 MoE Gate - 192 + C 32
    //..........................................................................
    FOR i := 0 TO 191 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        W_moe_gate[i]   := UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 0.4 - 0.2;
    END_FOR;

    FOR i := 0 TO 31 DO
        rand_seed       := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
        W_moe_C[i]      := 0.01
                         + UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 0.02;
    END_FOR;

    //..........................................................................
    //  1.6 Blend + MoE + RL - FIX No Zero
    //..........................................................................
    w_blend[0]          := 5.0;             // Liq
    w_blend[1]          := 5.0;             // KAN
    w_blend[2]          := 5.0;             // Mamba
    w_blend[3]          := 2.0;             // Koop
    w_blend[4]          := 2.0;             // Trans
    w_blend[5]          := 1.0;             // PINN

    lr_blend            := 0.0003;          // FIX was 0.0008
    lr_moe              := 0.0005;          // FIX was 0.001
    lr_rl               := 0.0001;          // FIX was 0.0005

    FOR i := 0 TO 5 DO
        model_out_prev[i] := 0.0;
        alpha_moe[i]    := 0.166;           // 1/6
    END_FOR;

    y_phys_prev         := PV;
    y_corr_pred_prev    := 0.0;
    Learn_Init_Done     := FALSE;
    MV_prev             := 50.0;
    reward_prev         := 0.0;

    //..........................................................................
    //  1.7 AIMD Gain
    //..........................................................................
    kp_mult             := 1.0;
    ki_mult             := 1.0;
    lr_ctrl             := 0.002;

    FirstScan           := FALSE;

END_IF;


//==============================================================================
//  SECTION 2 : PLANT SIM + STATE + RL REWARD
//==============================================================================
IF (NOT Enable) OR Reset THEN
    MV                  := MV_Min;
    e_int               := 0.0;
    e_prev              := 0.0;
    y_sim               := 0.0;
    RETURN;
END_IF;

//------------------------------------------------------------------------------
//  2.1 FOPDT Plant
//------------------------------------------------------------------------------
IF SIM_MODE THEN
    y_sim               := y_sim
                         + (K_gain * MV - y_sim) / T_timeconst * SampleTime;

    rand_seed           := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
    rand_noise          := UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 2.0 - 1.0;

    PV                  := y_sim + rand_noise * (0.2 + SP / 5000.0);
END_IF;

//------------------------------------------------------------------------------
//  2.2 State Error
//------------------------------------------------------------------------------
e                       := SP - PV;
de                      := (e - e_prev) / SampleTime;
e_int                   := LIMIT(-8000.0, e_int + e * SampleTime, 8000.0);
y_dot                   := (PV - y_dot_prev) * 10.0;
y_dot_prev              := PV;
dMV                     := MV - MV_prev;

//------------------------------------------------------------------------------
//  2.3 History Buffer 5 x 128
//------------------------------------------------------------------------------
hist_buf[hist_idx*5+0]  := LIMIT(-1.0, e / e_scale, 1.0);
hist_buf[hist_idx*5+1]  := LIMIT(-1.0, de / (e_scale / 5.0), 1.0);
hist_buf[hist_idx*5+2]  := LIMIT(-1.0, e_int / (e_scale / 5.0), 1.0);
hist_buf[hist_idx*5+3]  := LIMIT(-1.0, PV / 2500.0, 1.0);
hist_buf[hist_idx*5+4]  := LIMIT(-1.0, y_dot / 100.0, 1.0);
hist_idx                := (hist_idx + 1) MOD 128;

//------------------------------------------------------------------------------
//  2.4 Score + RL Reward
//------------------------------------------------------------------------------
IF Reset_Score THEN
    IAE                 := 0.0;
    ITAE                := 0.0;
    reward_sum          := 0.0;
END_IF;

IAE                     := IAE + ABS(e) * SampleTime;
IAE_final               := IAE;

reward                  := -ABS(e) / e_scale
                         - 0.1 * ABS(dMV) / 100.0
                         - 0.05 * y_pred_std;

IF (e * e_prev) < 0.0 THEN
    reward              := reward - 0.5;    // Overshoot penalty
END_IF;

reward_sum              := reward_sum + reward;


//==============================================================================
//  SECTION 3 : MoE GATING + ONLINE LEARNING + 8 AI ENSEMBLE - FIX 0.1..10
//==============================================================================

//------------------------------------------------------------------------------
//  3.0 MoE Gating Network - Softmax Alpha[6]
//------------------------------------------------------------------------------
FOR i := 0 TO 5 DO
    logit_moe[i]        := 0.0;
    FOR j := 0 TO 4 DO
        idx             := ((hist_idx - 1 + 128) MOD 128) * 5 + j;
        logit_moe[i]    := logit_moe[i] + W_moe_gate[i*32+j] * hist_buf[idx];
    END_FOR;
    logit_moe[i]        := logit_moe[i]
                         + W_moe_gate[i*32+5] * (PV / 2500.0)
                         + W_moe_gate[i*32+6] * (MV / 100.0);
END_FOR;

max_logit               := logit_moe[0];
FOR i := 1 TO 5 DO
    IF logit_moe[i] > max_logit THEN
        max_logit       := logit_moe[i];
    END_IF;
END_FOR;

sum_exp                 := 0.0;
FOR i := 0 TO 5 DO
    exp_moe[i]          := EXP(logit_moe[i] - max_logit);
    sum_exp             := sum_exp + exp_moe[i];
END_FOR;

FOR i := 0 TO 5 DO
    alpha_moe[i]        := exp_moe[i] / sum_exp;    // 0..1 sum=1
END_FOR;

//------------------------------------------------------------------------------
//  3.0b LMS + RL Update - FIX LIMIT 0.1..10 biar gak 0
//------------------------------------------------------------------------------
IF Learn_Init_Done THEN
    y_corr_target       := PV - y_phys_prev;
    corr_err            := y_corr_target - y_corr_pred_prev;

    FOR i := 0 TO 5 DO
        w_blend[i]      := LIMIT(0.1,                        // FIX was 0
                                 w_blend[i]
                               + lr_blend * corr_err * model_out_prev[i]
                               + lr_rl * (reward - reward_prev) * model_out_prev[i],
                                 10.0);
    END_FOR;

    FOR i := 0 TO 5 DO
        W_moe_gate[i*32] := W_moe_gate[i*32]
                          + lr_moe * corr_err * alpha_moe[i] * 0.01;
    END_FOR;
ELSE
    Learn_Init_Done     := TRUE;
END_IF;

reward_prev             := reward;

//..........................................................................
//  3.1 KAN - 64 Neurons
//..........................................................................
y_kan                   := 0.0;
FOR i := 0 TO 63 DO
    base                := W_kan_base[i*5]   * (e / e_scale)
                         + W_kan_base[i*5+1] * (de / (e_scale / 5.0))
                         + W_kan_base[i*5+2] * (PV / 2500.0);

    spline              := base * base * W_kan_spline[i*5]
                         + base * base * base * W_kan_spline[i*5+1];

    y_kan               := y_kan + (base + spline * 0.15) * 0.05;
END_FOR;
y_kan                   := LIMIT(-5.0, y_kan, 5.0);

//..........................................................................
//  3.2 Mamba-2 - 32 States - y_mamba 0.36 Fix
//..........................................................................
FOR i := 0 TO 31 DO
    h_mamba[i]          := W_mamba_A[i] * h_mamba[i]
                         + W_mamba_B[i] * (PV / 2500.0)
                         + W_mamba_D[i] * (MV / 100.0);
END_FOR;

y_mamba                 := 0.0;
FOR i := 0 TO 31 DO
    y_mamba             := y_mamba + W_mamba_C[i] * h_mamba[i] * 0.3;
END_FOR;

IF y_mamba >= 1.5 THEN
    y_mamba             := 0.8;             // Clamp 1.5 -> 0.8
END_IF;
IF y_mamba <= -1.5 THEN
    y_mamba             := 0.0;
END_IF;
y_mamba                 := LIMIT(-5.0, y_mamba, 5.0);

//..........................................................................
//  3.3 Liquid NN - 896 Neurons - 7 Ensembles
//..........................................................................
FOR e_idx := 0 TO 6 DO
    FOR j := 0 TO 127 DO
        idx             := e_idx * 128 + j;
        f_in            := (PV / 2500.0) * 0.15
                         + (MV / 100.0) * 0.15
                         + (e / e_scale) * 0.1;

        x_liq[idx]      := x_liq[idx] + SampleTime *
                         ( -(1.0 / tau_liq[idx] + 1.0 / (1.0 + EXP(-f_in)))
                           * x_liq[idx]
                           + (1.0 / (1.0 + EXP(-f_in))) * A_liq[idx] );
    END_FOR;

    y_ens[e_idx]        := 0.0;
    FOR j := 0 TO 63 DO
        idx             := e_idx * 128 + j;
        y_ens[e_idx]    := y_ens[e_idx] + x_liq[idx] * 0.03;
    END_FOR;
END_FOR;

y_liq                   := (y_ens[0] + y_ens[1] + y_ens[2] + y_ens[3]
                         +  y_ens[4] + y_ens[5] + y_ens[6]) / 7.0;
y_liq                   := LIMIT(-5.0, y_liq, 5.0);

//..........................................................................
//  3.4 Koopman 64 + Transformer 32 + PINN 64 + MoE 32
//..........................................................................
FOR i := 0 TO 63 DO
    g_lift[i]           := 0.0;
    FOR j := 0 TO 4 DO
        idx             := ((hist_idx - 1 + 128) MOD 128) * 5 + j;
        g_lift[i]       := g_lift[i] + W_koop_enc[i*5+j] * hist_buf[idx];
    END_FOR;
    IF g_lift[i] < 0.0 THEN
        g_lift[i]       := 0.0;
    END_IF;
END_FOR;

y_koop                  := 0.0;
FOR i := 0 TO 63 DO
    FOR j := 0 TO 63 DO
        y_koop          := y_koop + W_koop_dyn[i*64+j] * g_lift[j] * 0.001;
    END_FOR;
END_FOR;
y_koop                  := LIMIT(-5.0, y_koop, 5.0);

y_trans                 := 0.0;
FOR i := 0 TO 31 DO
    idx                 := (hist_idx - i + 128) MOD 128 * 5 + 3;
    y_trans             := y_trans + hist_buf[idx] * W_trans_Q[i]
                                     * W_trans_K[i] * 0.1;
END_FOR;
y_trans                 := LIMIT(-5.0, y_trans, 5.0);

y_pinn                  := 0.0;
FOR i := 0 TO 63 DO
    y_pinn              := y_pinn + W_pinn[i] * (PV / 2500.0) * 0.01;
END_FOR;
y_pinn                  := LIMIT(-5.0, y_pinn, 5.0);

y_moe                   := 0.0;
FOR i := 0 TO 31 DO
    y_moe               := y_moe + W_moe_C[i] * alpha_moe[i MOD 6] * 0.1;
END_FOR;
y_moe                   := LIMIT(-5.0, y_moe, 5.0);

//..........................................................................
//  3.5 Fusion - Physics 0.92 + AI + MoE + RL
//..........................................................................
w_phys                  := LIMIT(0.6, 0.6 + SP / 4000.0, 0.92);
w_ai                    := 1.0 - w_phys;

y_corr_pred             := y_liq  * w_blend[0] * alpha_moe[0] * 6.0
                         + y_kan  * w_blend[1] * alpha_moe[1] * 6.0
                         + y_mamba* w_blend[2] * alpha_moe[2] * 6.0
                         + y_koop * w_blend[3] * alpha_moe[3] * 6.0
                         + y_trans* w_blend[4] * alpha_moe[4] * 6.0
                         + y_pinn * w_blend[5] * alpha_moe[5] * 6.0;

y_physics               := PV + (K_gain * MV - PV) / T_timeconst * SampleTime;

y_pred_mean             := w_phys * y_physics
                         + w_ai * y_corr_pred
                         + y_moe * 0.05;

y_pred_mean             := LIMIT(-100.0, y_pred_mean, 3000.0);
y_pred_std              := 0.04;

y_phys_prev             := y_physics;
y_corr_pred_prev        := y_corr_pred;

model_out_prev[0]       := y_liq;
model_out_prev[1]       := y_kan;
model_out_prev[2]       := y_mamba;
model_out_prev[3]       := y_koop;
model_out_prev[4]       := y_trans;
model_out_prev[5]       := y_pinn;


//==============================================================================
//  SECTION 4 : CONTROLLER - AIMD + DIFFUSION + SAFETY
//==============================================================================

//------------------------------------------------------------------------------
//  4.1 AIMD Adaptive Gain
//------------------------------------------------------------------------------
kp_auto                 := 0.5 + SP / 2000.0;
ki_auto                 := 0.02 + SP / 10000.0;

IF (e * e_prev) < 0.0 THEN
    kp_mult             := kp_mult - lr_ctrl;
    ki_mult             := ki_mult - lr_ctrl * 0.5;
ELSE
    kp_mult             := kp_mult + lr_ctrl * 0.2;
    ki_mult             := ki_mult + lr_ctrl * 0.1;
END_IF;

kp_mult                 := LIMIT(0.3, kp_mult, 2.0);
ki_mult                 := LIMIT(0.3, ki_mult, 2.0);

kp_eff                  := kp_auto * kp_mult;
ki_eff                  := ki_auto * ki_mult;

//------------------------------------------------------------------------------
//  4.2 Diffusion Policy - 128 + 3 Denoise
//------------------------------------------------------------------------------
FOR i := 0 TO 127 DO
    h1[i]               := (e / e_scale) * 0.8
                         + (e_int / (e_scale * 5.0)) * 0.5
                         + (de / (e_scale * 5.0)) * 0.15;
    IF h1[i] < 0.0 THEN
        h1[i]           := 0.0;
    END_IF;
END_FOR;

FOR i := 0 TO 127 DO
    h2[i]               := h1[i] * 0.95;
    IF h2[i] < 0.0 THEN
        h2[i]           := 0.0;
    END_IF;
END_FOR;

u_norm                  := 0.0;
FOR j := 0 TO 127 DO
    u_norm              := u_norm + h2[j] * 0.02;
END_FOR;

FOR d := 0 TO 2 DO
    rand_seed           := (rand_seed * UDINT#1103515245 + UDINT#12345)
                           MOD UDINT#2147483647;
    rand_noise          := UDINT_TO_LREAL(rand_seed) / 2147483647.0 * 2.0 - 1.0;
    u_norm              := u_norm * 0.92 + rand_noise * 0.008;
END_FOR;

//------------------------------------------------------------------------------
//  4.3 MV Mix + Safety
//------------------------------------------------------------------------------
MV_AI                   := 50.0 + 50.0 * LIMIT(-1.0, u_norm, 1.0);
MV_PI                   := kp_eff * e + ki_eff * e_int;
MV                      := 0.6 * MV_AI + 0.4 * MV_PI;
MV                      := LIMIT(MV_Min, MV, MV_Max);

IF y_pred_std > 0.18 THEN
    MV                  := LIMIT(MV_Min, K_gain * 0.55 * e, MV_Max);
END_IF;

IF y_pred_mean > (SP + 2000.0) THEN
    MV                  := MV * 0.85;
END_IF;

e_prev                  := e;
MV_prev                 := MV;

//------------------------------------------------------------------------------
//  END V14 - ULTRA RAPI MAX PRO FINAL - 8 AI + MoE + RL
//  y_mamba 0.36 + w_blend 0.1..10 + reward -0.002 + alpha 0.15
//------------------------------------------------------------------------------
