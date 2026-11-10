// =====================================================================
// 게임 본체: 메인 FSM + 게임 객체들
//   이 모듈이 "지휘자"이고, 실제 상태는 아래 객체(서브모듈)가 각자 갖고 있어요.
//     player_unit x2  : 플레이어 (체력·위치·각도·포탄 ...)
//     wall_unit       : 가운데 벽
//     event_unit      : 3턴 이벤트
//     power_gauge     : 파워 게이지
//     trajectory      : 포탄 탄도 (시뮬레이터와 비트 단위로 같음)
//     collision       : 충돌 판정
//     impact_calc     : 피해 계산
//     cpu_ai          : CPU 조준·회피 계획
//     fx_unit         : 폭발·흔들림·LED 번쩍임·알림 문구·불꽃놀이
//   메인 FSM은 프레임 틱(30 Hz)마다 시뮬레이터 tick() 의 switch문과 같은 일을 하고,
//   키 입력은 틱이 아닌 클럭에 처리해요 (시뮬레이터 onKey()).
//   화면·주변장치에 필요한 값은 전부 출력 포트로 내보내요.
// =====================================================================
module game_core (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [15:0] rnd,
    input  wire [9:0]  key_level,
    input  wire [9:0]  key_press,
    input  wire [9:0]  key_release,
    input  wire [7:0]  dip,             // dip[0] = DIP1 ... dip[7] = DIP8
    input  wire        roul_busy,
    input  wire        roul_tick,

    // ---- 진행 상태
    output reg  [3:0]  st,
    output reg  [7:0]  st_t,
    output reg  [7:0]  gt,              // 전체 틱 카운터 (깜빡임용)
    output reg         turn,
    output reg         setup,
    output wire        cpu_on,
    output reg  [1:0]  winner,
    output reg  [6:0]  title_ang,

    // ---- 플레이어 (화면용)
    output wire [3:0]  p0_pos,
    output wire [3:0]  p1_pos,
    output wire [6:0]  p0_ang,
    output wire [6:0]  p1_ang,
    output wire [7:0]  p0_disp,
    output wire [7:0]  p1_disp,
    output wire        p0_frz_show,
    output wire        p1_frz_show,
    output wire        p0_flash_inv,
    output wire        p1_flash_inv,
    output wire        vis0,
    output wire        vis1,
    output wire        q_en,            // 숨은 상대 '?'
    output wire [3:0]  q_col,
    output wire        m_en,            // 지난 탄착 '.'
    output wire [3:0]  m_col,
    output wire [7:0]  p0_dmg,
    output wire [7:0]  p0_heal,
    output wire [7:0]  p1_dmg,
    output wire [7:0]  p1_heal,
    output wire        dmg_show,

    // ---- 벽·이벤트
    output wire [5:0]  wall_hp,
    output wire        wall2_col,
    output wire [4:0]  lava0,
    output wire [4:0]  lava1,
    output wire [14:0] marks,
    output wire signed [7:0] wind,

    // ---- 포탄
    output wire        sh_draw,
    output wire        sh_trail_draw,
    output wire signed [9:0] sh_px,
    output wire signed [9:0] sh_py,
    output wire        sh_ice,
    output reg  [31:0] trail,           // 지나온 칸 {윗줄 16, 아랫줄 16}: 비트 = 행*16 + 칸

    // ---- 연출
    output wire        fx_on,
    output wire [4:0]  fx_t,
    output wire [3:0]  fx_col,
    output wire        fx_row,
    output wire [1:0]  fx_kind,
    output wire        fx_big,
    output wire [1:0]  lcd_shift,
    output wire        lcd_on,
    output wire [15:0] fw_cols,
    output wire [19:0] fw_ages,

    // ---- 윗줄 HUD 글자 묶음 3개: {켜짐, 메시지번호[5:0], 정렬[1:0], 칸[3:0]}
    //      정렬 0 = 칸부터 왼쪽 정렬, 1 = 오른쪽 끝 정렬, 3 = 가운데
    //      메시지번호 60 = "45° P4" (조준값), 61 = "<3" 바람, 62 = "<<<" 바람 화살표
    output reg  [12:0] hud_a,
    output reg  [12:0] hud_b,
    output reg  [12:0] hud_c,
    output wire [6:0]  cur_ang,
    output wire [3:0]  cur_pow,

    // ---- 주변장치
    output reg  [4:0]  seg_mid0,
    output reg  [4:0]  seg_mid1,
    output wire [4:0]  shell_digit,     // 1자리 7세그 (seg_font 코드)
    output wire [7:0]  servo_deg,
    output wire [3:0]  led_power,
    output wire        rgb_roulette,
    output wire [2:0]  rgb_flash_color,
    output wire [5:0]  rgb_flash_t,
    output reg         sfx_req,
    output reg  [4:0]  sfx_id,
    output wire        charge_on,
    output reg         roul_home,
    output reg         roul_spin,
    output wire [2:0]  roul_target
);
    `include "params.vh"
    `include "msg_ids.vh"

    localparam [5:0] HUD_AIM = 6'd60, HUD_WIND2 = 6'd61, HUD_ARROWS = 6'd62;
    localparam [1:0] AL_LEFT = 2'd0, AL_RIGHT = 2'd1, AL_CENTER = 2'd3;

    // =================================================================
    // 설정 (게임 시작 때 DIP을 읽어 고정)
    // =================================================================
    reg cfg_special, cfg_cpu, cfg_expert, cfg_events, cfg_move, cfg_long, cfg_walls;
    assign cpu_on = cfg_cpu;

    // =================================================================
    // 명령 펄스 (매 클럭 기본 0)
    // =================================================================
    reg        c_pinit, c_acc_clr;
    reg [1:0]  c_turn_begin, c_ang_up, c_ang_dn, c_sh_toggle, c_sh_set, c_pos_inc, c_pos_dec, c_pos_set;
    reg [1:0]  c_dmg_en, c_heal_en, c_frz_set, c_frz_clr, c_flash_set, c_last_set, c_pow_set;
    reg        c_seen_set;
    reg [2:0]  c_sh_val;
    reg [3:0]  c_pos_val0, c_pos_val1, c_last_val, c_pow_val;
    reg [7:0]  c_dmg_val0, c_dmg_val1, c_heal_val;
    reg        c_wall_init, c_wall_hit, c_wall_quake;
    reg [1:0]  c_wall_idx, c_wall_layout;
    reg        c_ev_reset, c_ev_turn, c_ev_apply, c_ev_strike_clr;
    reg        c_pow_start;
    reg        c_tr_start, c_tr_step, c_tr_stop;
    reg        c_fx_clear, c_fx_explode, c_fx_shake, c_fx_rgb, c_fx_msg;
    reg [6:0]  c_ex_x;
    reg [3:0]  c_ex_y;
    reg [1:0]  c_ex_kind;
    reg        c_ex_big;
    reg [5:0]  c_shake_val, c_rgb_t, c_msg_id;
    reg [2:0]  c_rgb_color;
    reg        c_cpu_aim, c_cpu_dodge;

    // =================================================================
    // 객체들
    // =================================================================
    wire [7:0] p0_hp, p1_hp, p0_max, p1_max;
    wire [6:0] p0_ang_w, p1_ang_w;
    wire [2:0] p0_shell, p1_shell;
    wire [3:0] p0_pow, p1_pow, p0_seen, p1_seen, p0_last, p1_last;
    wire       p0_frozen, p1_frozen, p0_last_v, p1_last_v, p0_first, p1_first;

    wire [7:0] init_hp = cfg_long ? HP_LONG : HP_BASE;

    player_unit #(.PI(0)) u_p0 (
        .clk(clk), .rst(rst), .tick_frame(tick_frame),
        .init(c_pinit), .init_hp(init_hp), .turn_begin(c_turn_begin[0]), .acc_clr(c_acc_clr),
        .ang_up(c_ang_up[0]), .ang_dn(c_ang_dn[0]),
        .shell_toggle(c_sh_toggle[0]), .shell_set(c_sh_set[0]), .shell_val(c_sh_val),
        .pos_inc(c_pos_inc[0]), .pos_dec(c_pos_dec[0]), .pos_set(c_pos_set[0]), .pos_val(c_pos_val0),
        .dmg_en(c_dmg_en[0]), .dmg_val(c_dmg_val0), .heal_en(c_heal_en[0]), .heal_val(c_heal_val),
        .freeze_set(c_frz_set[0]), .freeze_clr(c_frz_clr[0]), .flash_set(c_flash_set[0]),
        .seen_set(c_seen_set), .seen_val(p1_pos), .last_set(c_last_set[0]), .last_val(c_last_val),
        .pow_set(c_pow_set[0]), .pow_val(c_pow_val),
        .hp(p0_hp), .max_hp(p0_max), .disp_hp(p0_disp), .pos(p0_pos), .ang(p0_ang_w), .shell(p0_shell),
        .pow(p0_pow), .frozen(p0_frozen), .flash_inv(p0_flash_inv), .seen(p0_seen),
        .last(p0_last), .last_valid(p0_last_v), .dmg_acc(p0_dmg), .heal_acc(p0_heal), .first_turn(p0_first)
    );

    player_unit #(.PI(1)) u_p1 (
        .clk(clk), .rst(rst), .tick_frame(tick_frame),
        .init(c_pinit), .init_hp(init_hp), .turn_begin(c_turn_begin[1]), .acc_clr(c_acc_clr),
        .ang_up(c_ang_up[1]), .ang_dn(c_ang_dn[1]),
        .shell_toggle(c_sh_toggle[1]), .shell_set(c_sh_set[1]), .shell_val(c_sh_val),
        .pos_inc(c_pos_inc[1]), .pos_dec(c_pos_dec[1]), .pos_set(c_pos_set[1]), .pos_val(c_pos_val1),
        .dmg_en(c_dmg_en[1]), .dmg_val(c_dmg_val1), .heal_en(c_heal_en[1]), .heal_val(c_heal_val),
        .freeze_set(c_frz_set[1]), .freeze_clr(c_frz_clr[1]), .flash_set(c_flash_set[1]),
        .seen_set(c_seen_set), .seen_val(p0_pos), .last_set(c_last_set[1]), .last_val(c_last_val),
        .pow_set(c_pow_set[1]), .pow_val(c_pow_val),
        .hp(p1_hp), .max_hp(p1_max), .disp_hp(p1_disp), .pos(p1_pos), .ang(p1_ang_w), .shell(p1_shell),
        .pow(p1_pow), .frozen(p1_frozen), .flash_inv(p1_flash_inv), .seen(p1_seen),
        .last(p1_last), .last_valid(p1_last_v), .dmg_acc(p1_dmg), .heal_acc(p1_heal), .first_turn(p1_first)
    );
    assign p0_ang = p0_ang_w;
    assign p1_ang = p1_ang_w;

    wall_unit u_wall (
        .clk(clk), .rst(rst), .init(c_wall_init), .enable(cfg_walls), .layout(c_wall_layout),
        .hit(c_wall_hit), .hit_idx(c_wall_idx), .quake(c_wall_quake),
        .wall_hp(wall_hp), .wall2_col(wall2_col)
    );

    wire       ev_active, ev_new, ev_strike;
    wire [2:0] ev_id, ev_idx;
    wire [1:0] ev_next_in;
    wire [14:0] strike_cells;
    wire [7:0] grav;
    wire [3:0] quake_p0, quake_p1;
    event_unit u_event (
        .clk(clk), .rst(rst), .rnd(rnd), .reset_game(c_ev_reset), .events_on(cfg_events),
        .turn_begin(c_ev_turn), .setup(setup), .apply(c_ev_apply), .strike_clr(c_ev_strike_clr),
        .p0_pos(p0_pos), .p1_pos(p1_pos),
        .ev_active(ev_active), .ev_id(ev_id), .ev_new(ev_new), .ev_idx(ev_idx), .next_in(ev_next_in),
        .lava0(lava0), .lava1(lava1), .marks(marks), .strike(ev_strike), .strike_cells(strike_cells),
        .wind(wind), .grav(grav), .quake_p0(quake_p0), .quake_p1(quake_p1)
    );

    wire [3:0] gauge_pow;
    wire       gauge_up;
    power_gauge u_gauge (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .start(c_pow_start), .run(st == ST_CHARGE),
        .pow(gauge_pow), .dir_up(gauge_up)
    );

    // ---- 포탄 (발사 값은 레지스터에 담아 두고 c_tr_start 다음 클럭에 읽힘)
    reg  [5:0]  l_aidx;
    reg  [3:0]  l_pidx;
    reg         l_dir;
    reg  [6:0]  l_pivot;
    reg         l_raw;
    reg  [19:0] l_x;
    wire        tr_active, tr_ground, tr_out;
    wire signed [9:0] tr_px, tr_py;
    trajectory u_traj (
        .clk(clk), .rst(rst), .start(c_tr_start), .step(c_tr_step), .stop(c_tr_stop),
        .angle_idx(l_aidx), .power_idx(l_pidx), .dir(l_dir), .pivot_x(l_pivot),
        .start_x(l_x), .start_h(METEOR_H0), .start_vx(20'sd0), .start_vh(METEOR_VH), .use_raw(l_raw),
        .wind(wind), .grav(grav),
        .active(tr_active), .px(tr_px), .py(tr_py), .hit_ground(tr_ground), .out_of_map(tr_out)
    );

    reg        sh_active, sh_owner_v, sh_owner;
    reg [2:0]  sh_type;
    reg [9:0]  sh_age;
    reg [1:0]  sh_phase;                 // 0 대기, 1 step 보냄, 2 충돌 검사

    wire c_hit, c_out, c_wall, c_direct, c_dpi, c_ground;
    wire [1:0] c_widx;
    collision u_col (
        .px(tr_px), .py(tr_py), .hit_ground(tr_ground), .out_of_map(tr_out),
        .owner_valid(sh_owner_v), .owner(sh_owner), .self_skip(sh_age < SELF_SKIP),
        .p0_pos(p0_pos), .p1_pos(p1_pos), .wall_hp(wall_hp), .wall2_col(wall2_col),
        .hit(c_hit), .is_out(c_out), .is_wall(c_wall), .wall_idx(c_widx),
        .is_direct(c_direct), .direct_pi(c_dpi), .is_ground(c_ground)
    );

    // 탄착 좌표 (화면 안으로 자름)
    wire [6:0] ix = tr_px[9] ? 7'd0 : (tr_px > 10'sd79) ? 7'd79 : tr_px[6:0];
    wire [3:0] iy = (c_direct || c_wall) ? (tr_py[9] ? 4'd0 : (tr_py > 10'sd15) ? 4'd15 : tr_py[3:0]) : 4'd15;
    wire [14:0] ixm = ix * 15'd205;
    wire [3:0] icol = ixm[13:10];

    wire [7:0] im_d0, im_d1;
    wire im_f0, im_f1, im_enemy, im_direct;
    impact_calc u_imp (
        .shell(sh_type), .is_direct(c_direct), .direct_pi(c_dpi), .ix(ix),
        .p0_pos(p0_pos), .p1_pos(p1_pos), .owner_valid(sh_owner_v), .owner(sh_owner),
        .dmg0(im_d0), .dmg1(im_d1), .frz0(im_f0), .frz1(im_f1),
        .enemy_hit(im_enemy), .direct_enemy(im_direct)
    );

    wire       cpu_aim_done, cpu_dodge_done;
    wire [6:0] cpu_a;
    wire [3:0] cpu_p, cpu_dodge_t;
    wire [2:0] cpu_sh;
    cpu_ai u_cpu (
        .clk(clk), .rst(rst), .rnd(rnd),
        .plan_aim(c_cpu_aim), .plan_dodge(c_cpu_dodge),
        .expert(cfg_expert), .special_on(cfg_special), .move_on(cfg_move),
        .wind(wind), .grav(grav), .seen0(p1_seen), .my_pos(p1_pos), .my_hp(p1_hp), .my_max(p1_max),
        .wall_hp(wall_hp), .wall2_col(wall2_col), .lava0(lava0), .lava1(lava1), .marks(marks),
        .enemy_last_valid(p0_last_v), .enemy_last(p0_last),
        .aim_done(cpu_aim_done), .aim_ang(cpu_a), .aim_pow(cpu_p), .aim_shell(cpu_sh),
        .dodge_done(cpu_dodge_done), .dodge_target(cpu_dodge_t)
    );

    wire msg_on, msg_owner;
    wire [5:0] msg_val;
    wire fw_spawn;
    fx_unit u_fx (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .rnd(rnd), .clear(c_fx_clear),
        .explode(c_fx_explode), .ex_x(c_ex_x), .ex_y(c_ex_y), .ex_kind(c_ex_kind), .ex_big(c_ex_big),
        .fx_on(fx_on), .fx_t(fx_t), .fx_col(fx_col), .fx_row(fx_row), .fx_kind(fx_kind), .fx_big(fx_big),
        .shake_set(c_fx_shake), .shake_val(c_shake_val), .shake(), .lcd_shift(lcd_shift),
        .rgb_set(c_fx_rgb), .rgb_color(c_rgb_color), .rgb_t(c_rgb_t),
        .rgb_flash_color(rgb_flash_color), .rgb_flash_t(rgb_flash_t),
        .msg_set(c_fx_msg), .msg_pi(turn), .msg_id(c_msg_id),
        .msg_on(msg_on), .msg_owner(msg_owner), .msg_val(msg_val),
        .fireworks(st == ST_OVER), .fw_cols(fw_cols), .fw_ages(fw_ages), .fw_spawn(fw_spawn)
    );

    // =================================================================
    // 현재 차례 플레이어 값
    // =================================================================
    wire [3:0] cpos    = turn ? p1_pos   : p0_pos;
    wire [6:0] cang    = turn ? p1_ang_w : p0_ang_w;
    wire [2:0] cshell  = turn ? p1_shell : p0_shell;
    wire       cfrozen = turn ? p1_frozen : p0_frozen;
    wire       human   = !(turn && cfg_cpu);
    wire [2:0] shell_eff = cfg_special ? cshell : SH_NORMAL;

    assign cur_ang = cang;
    assign cur_pow = (st == ST_CHARGE) ? gauge_pow : (turn ? p1_pow : p0_pow);

    // 이동 가능 검사: 진영 안 + 새 위치의 탱크 두 칸이 용암이 아님
    function lava_on;
        input [4:0] lv;
        input [3:0] a, b;
        begin
            lava_on = lv[4] && (lv[3:0] == a || lv[3:0] == b);
        end
    endfunction
    wire [3:0] np_l = cpos - 4'd1, np_r = cpos + 4'd1;
    wire [3:0] lo_l = turn ? np_l - 4'd1 : np_l, hi_l = turn ? np_l : np_l + 4'd1;
    wire [3:0] lo_r = turn ? np_r - 4'd1 : np_r, hi_r = turn ? np_r : np_r + 4'd1;
    wire lava_l = lava_on(lava0, lo_l, hi_l) || lava_on(lava1, lo_l, hi_l);
    wire lava_r = lava_on(lava0, lo_r, hi_r) || lava_on(lava1, lo_r, hi_r);
    wire range_l = turn ? (cpos > P2_MIN) : (cpos > P1_MIN);
    wire range_r = turn ? (cpos < P2_MAX) : (cpos < P1_MAX);
    wire ok_l = range_l && !lava_l;
    wire ok_r = range_r && !lava_r;

    // 결과 문구 (시뮬레이터 buildResult)
    wire [7:0] de = turn ? p0_dmg : p1_dmg;      // 상대가 받은 피해
    wire [7:0] ds = turn ? p1_dmg : p0_dmg;      // 내가 받은 피해
    reg  froze0, froze1, f_wall_hit, f_wall_broke, f_out, f_direct, mv_frozen;
    wire froze_e = turn ? froze0 : froze1;
    wire froze_s = turn ? froze1 : froze0;
    reg  [2:0] shot_type;
    reg  [5:0] res_msg_c;
    always @(*) begin
        if (shot_type == SH_ICE)
            res_msg_c = froze_e ? MSG_FROZEN_X : froze_s ? MSG_BRRR : f_wall_hit ? MSG_BLOCKED : f_out ? MSG_OUT_X : MSG_MISS;
        else if (shot_type == SH_FIRE && de == 8'd0)
            res_msg_c = MSG_BACKFIRE;
        else if (shot_type == SH_FIRE)
            res_msg_c = MSG_BURN_X;
        else
            res_msg_c = (de != 0) ? (f_direct ? MSG_DIRECT_X : MSG_HIT_X) : (ds != 0) ? MSG_OOPS_X
                      : f_wall_broke ? MSG_WALL_DOWN : f_wall_hit ? MSG_BLOCKED : f_out ? MSG_OUT_X : MSG_MISS;
    end

    // =================================================================
    // 메인 FSM 레지스터
    // =================================================================
    reg  [5:0] res_msg;
    reg        double_left;
    reg  [2:0] seq;                      // ST_START / ST_NEXT 안의 단계
    reg  [1:0] imp2;                     // 탄착 처리 2단계: 2 = 피해 반영 기다림, 1 = 처리
    reg        imp_enemy, imp_fire_own, imp_wide;
    reg  [1:0] met_idx;
    reg        ev_applied, roul_started;
    reg  [7:0] aux_t;
    reg  [1:0] cpu_phase;                // 0 계획 기다림, 1 각도 돌리기, 2 포탄 고르기, 3 충전
    reg  [7:0] cpu_w;
    reg  [6:0] cpu_ta;
    reg  [3:0] cpu_tp;
    reg  [2:0] cpu_ts;
    reg        mv_planned;
    reg  [3:0] mv_target;
    reg  [7:0] mv_w, mv_done;
    reg  [4:0] rep_up, rep_dn;
    reg        title_dir;
    reg  [9:0] pend;                     // 아직 처리 안 한 키 누름
    reg        pend_rel;                 // 발사 키 뗌
    reg        boot;
    wire [9:0] key1 = pend & (~pend + 10'd1);   // 밀린 키 중 번호가 가장 낮은 것 하나만 (한 클럭에 한 키씩 처리)

    wire [7:0] st_t_n = (st_t == 8'hFF) ? st_t : st_t + 8'd1;
    // 지금 맞은 벽 블록이 체력 1이면 무너짐
    wire [1:0] whp_sel = (c_widx == 2'd0) ? wall_hp[1:0] : (c_widx == 2'd1) ? wall_hp[3:2] : wall_hp[5:4];
    wire       wall_breaks_now = (whp_sel == 2'd1);
    // 유성 낙하 칸 -> 시작 x 픽셀 (칸*5 + 2)
    wire [3:0] met_cell = strike_cells[met_idx*5 +: 4];
    wire       met_valid = strike_cells[met_idx*5 + 4];
    wire [6:0] met_x = met_cell * 5 + 2;
    wire       disp_settled = (p0_disp == p0_hp) && (p1_disp == p1_hp);
    wire       anyone_dead  = (p0_hp == 8'd0) || (p1_hp == 8'd0);

    // 효과음 요청 (DIP7이 꺼져 있어도 요청은 보내고, piezo_ctrl 이 소리만 끔)
    task play;
        input [4:0] id;
        begin
            sfx_req <= 1'b1;
            sfx_id  <= id;
        end
    endtask

    task go;
        input [3:0] s;
        begin
            st   <= s;
            st_t <= 8'd0;
        end
    endtask

    // 발사 준비 (현재 플레이어의 각도·파워로)
    task launch_shell;
        input [3:0] pw;
        begin
            l_aidx  <= cang - 7'd30;
            l_pidx  <= {pw[2:0] - 3'd1, 1'b1};          // ROM 파워 = 파워*2
            l_dir   <= turn;
            l_pivot <= turn ? ((cpos - 4'd1) * 5 + 3) : ((cpos + 4'd1) * 5 + 1);
            l_raw   <= 1'b0;
            c_tr_start <= 1'b1;
            sh_active <= 1'b1; sh_owner_v <= 1'b1; sh_owner <= turn; sh_age <= 10'd0; sh_phase <= 2'd0;
            trail <= 32'd0;
        end
    endtask

    // 다음 턴으로
    task next_turn;
        begin
            st <= ST_NEXT; st_t <= 8'd0; seq <= 3'd0;
        end
    endtask

    task start_game;
        begin
            st <= ST_START; st_t <= 8'd0; seq <= 3'd0;
        end
    endtask

    task game_over;
        begin
            winner <= (p0_hp == 8'd0 && p1_hp == 8'd0) ? 2'd2 : (p0_hp == 8'd0) ? 2'd1 : 2'd0;
            if (p0_hp == 8'd0 && p1_hp != 8'd0 && cfg_cpu) play(SFX_LOSE);
            else                                           play(SFX_WIN);
            go(ST_OVER);
        end
    endtask

    // 사람 차례 발사
    task do_fire;
        begin
            shot_type   <= shell_eff;
            double_left <= (shell_eff == SH_DOUBLE);
            sh_type     <= shell_eff;
            launch_shell(gauge_pow);
            c_seen_set  <= 1'b1;                         // 발사 순간 서로 위치 공개
            c_pow_set[turn] <= 1'b1; c_pow_val <= gauge_pow;
            play(SFX_FIRE);
            c_fx_rgb <= 1'b1; c_rgb_t <= 6'd8;
            c_rgb_color <= (shell_eff == SH_ICE) ? C_CYAN : (shell_eff == SH_FIRE) ? C_RED : C_YELLOW;
            go(ST_FLIGHT);
        end
    endtask

    // 이동 한 칸
    task try_move;
        input right;
        begin
            if (right ? ok_r : ok_l) begin
                if (right) c_pos_inc[turn] <= 1'b1; else c_pos_dec[turn] <= 1'b1;
                play(SFX_MOVE);
            end else begin
                play(SFX_ERR);
                if (right ? (range_r && lava_r) : (range_l && lava_l)) begin
                    c_fx_msg <= 1'b1; c_msg_id <= MSG_LAVA_X;
                end
                if (!human) mv_target <= cpos;           // CPU: 못 가면 거기서 멈춤
            end
        end
    endtask

    // 메인 상태로 진입 (INTRO 다음)
    task begin_play;
        begin
            if (setup) begin
                go(ST_MOVE);
                if (!human) c_cpu_dodge <= 1'b1;
            end else begin
                go(ST_AIM);
                if (!human) c_cpu_aim <= 1'b1;
            end
            cpu_phase <= 2'd0; cpu_w <= 8'd0; mv_planned <= 1'b0; mv_w <= 8'd0; mv_done <= 8'd0;
            rep_up <= 5'd0; rep_dn <= 5'd0;
        end
    endtask

    always @(posedge clk) begin
        // ---- 명령 펄스 기본값
        c_pinit <= 1'b0; c_acc_clr <= 1'b0; c_turn_begin <= 2'b00; c_ang_up <= 2'b00; c_ang_dn <= 2'b00;
        c_sh_toggle <= 2'b00; c_sh_set <= 2'b00; c_pos_inc <= 2'b00; c_pos_dec <= 2'b00; c_pos_set <= 2'b00;
        c_dmg_en <= 2'b00; c_heal_en <= 2'b00; c_frz_set <= 2'b00; c_frz_clr <= 2'b00; c_flash_set <= 2'b00;
        c_last_set <= 2'b00; c_pow_set <= 2'b00; c_seen_set <= 1'b0;
        c_wall_init <= 1'b0; c_wall_hit <= 1'b0; c_wall_quake <= 1'b0;
        c_ev_reset <= 1'b0; c_ev_turn <= 1'b0; c_ev_apply <= 1'b0; c_ev_strike_clr <= 1'b0;
        c_pow_start <= 1'b0; c_tr_start <= 1'b0; c_tr_step <= 1'b0; c_tr_stop <= 1'b0;
        c_fx_clear <= 1'b0; c_fx_explode <= 1'b0; c_fx_shake <= 1'b0; c_fx_rgb <= 1'b0; c_fx_msg <= 1'b0;
        c_cpu_aim <= 1'b0; c_cpu_dodge <= 1'b0;
        sfx_req <= 1'b0; roul_home <= 1'b0; roul_spin <= 1'b0;

        if (rst) begin
            st <= ST_TITLE; st_t <= 8'd0; gt <= 8'd0; turn <= 1'b0; setup <= 1'b0; winner <= 2'd0;
            title_ang <= 7'd60; title_dir <= 1'b1;
            cfg_special <= 1'b1; cfg_cpu <= 1'b0; cfg_expert <= 1'b0; cfg_events <= 1'b0;
            cfg_move <= 1'b1; cfg_long <= 1'b0; cfg_walls <= 1'b1;
            shot_type <= SH_NORMAL; res_msg <= MSG_MISS; double_left <= 1'b0; seq <= 3'd0;
            imp2 <= 2'd0; imp_enemy <= 1'b0; imp_fire_own <= 1'b0; imp_wide <= 1'b0;
            froze0 <= 1'b0; froze1 <= 1'b0; f_wall_hit <= 1'b0; f_wall_broke <= 1'b0; f_out <= 1'b0;
            f_direct <= 1'b0; mv_frozen <= 1'b0;
            sh_active <= 1'b0; sh_owner_v <= 1'b0; sh_owner <= 1'b0; sh_type <= SH_NORMAL; sh_age <= 10'd0;
            sh_phase <= 2'd0; trail <= 32'd0; met_idx <= 2'd0;
            l_aidx <= 6'd15; l_pidx <= 4'd7; l_dir <= 1'b0; l_pivot <= 7'd6; l_raw <= 1'b0; l_x <= 20'd0;
            ev_applied <= 1'b0; roul_started <= 1'b0; aux_t <= 8'd0;
            cpu_phase <= 2'd0; cpu_w <= 8'd0; cpu_ta <= 7'd45; cpu_tp <= 4'd4; cpu_ts <= SH_NORMAL;
            mv_planned <= 1'b0; mv_target <= 4'd15; mv_w <= 8'd0; mv_done <= 8'd0;
            rep_up <= 5'd0; rep_dn <= 5'd0; pend <= 10'd0; pend_rel <= 1'b0;
            sfx_id <= SFX_NONE;
            boot <= 1'b1;
            // 명령에 딸린 값 (펄스가 나갈 때만 의미가 있지만, 시뮬레이션에서 X가 안 보이게 0으로 둠)
            c_sh_val <= SH_NORMAL; c_pos_val0 <= 4'd0; c_pos_val1 <= 4'd0; c_last_val <= 4'd0; c_pow_val <= 4'd0;
            c_dmg_val0 <= 8'd0; c_dmg_val1 <= 8'd0; c_heal_val <= 8'd0; c_wall_idx <= 2'd0; c_wall_layout <= 2'd0;
            c_ex_x <= 7'd0; c_ex_y <= 4'd0; c_ex_kind <= 2'd0; c_ex_big <= 1'b0;
            c_shake_val <= 6'd0; c_rgb_t <= 6'd0; c_rgb_color <= C_OFF; c_msg_id <= 6'd0;
        end else begin
            // ---- 키 입력 모으기
            pend     <= pend | key_press;
            pend_rel <= pend_rel | key_release[K_FIRE];
            if (boot) begin boot <= 1'b0; roul_home <= 1'b1; end   // 전원 켠 뒤 룰렛 원점 찾기

            // ---- CPU 계획 결과 받기
            if (cpu_aim_done) begin
                cpu_ta <= cpu_a; cpu_tp <= cpu_p; cpu_ts <= cpu_sh; cpu_phase <= 2'd1;
            end
            if (cpu_dodge_done) begin
                mv_target <= cpu_dodge_t; mv_planned <= 1'b1;
            end

            // ---- 룰렛 딸깍 소리
            if (roul_tick && st == ST_INTRO && ev_new && !ev_applied) play(SFX_ROUL);
            if (fw_spawn) play(SFX_SPARK);

            // =========================================================
            // 1) 탄착 처리 2단계 (불 포탄 회복/역화, 흔들림, 소리)
            // =========================================================
            if (imp2 == 2'd2) begin
                imp2 <= 2'd1;                       // 1단계 피해 명령이 player_unit 에 반영될 때까지 한 클럭
            end else if (imp2 == 2'd1) begin
                imp2 <= 2'd0;
                if (imp_fire_own) begin
                    if (imp_enemy) begin
                        c_heal_en[sh_owner] <= 1'b1; c_heal_val <= FIRE_HEAL;
                        play(SFX_HEAL);
                    end else begin
                        c_dmg_en[sh_owner] <= 1'b1;
                        if (sh_owner) c_dmg_val1 <= FIRE_BACK; else c_dmg_val0 <= FIRE_BACK;
                        play(SFX_BURN);
                    end
                end else begin
                    play(imp_wide ? SFX_BOOM_BIG : SFX_BOOM);
                end
                c_fx_shake <= 1'b1;
                c_shake_val <= imp_wide ? 6'd18 : ((p0_dmg != 0) || (p1_dmg != 0) || (imp_fire_own && !imp_enemy)) ? 6'd12 : 6'd6;
                c_fx_rgb <= 1'b1;
                if (imp_fire_own) begin
                    c_rgb_color <= C_RED; c_rgb_t <= 6'd24;
                end else if ((p0_dmg != 0) || (p1_dmg != 0)) begin
                    c_rgb_color <= C_WHITE; c_rgb_t <= 6'd24;
                end else begin
                    c_rgb_color <= C_YELLOW; c_rgb_t <= 6'd12;
                end
                if (st == ST_FLIGHT) go(ST_IMPACT);
            end

            // =========================================================
            // 2) 포탄 비행: 틱마다 step -> 다음 클럭 대기 -> 충돌 검사
            // =========================================================
            else if (sh_phase == 2'd1) begin
                c_tr_step <= 1'b1;
                sh_phase  <= 2'd2;
            end else if (sh_phase == 2'd2 && !c_tr_step) begin
                sh_phase <= 2'd0;
                if (c_hit || sh_age == MAX_FLIGHT) begin
                    // ---------------- 탄착 1단계 ----------------
                    c_tr_stop <= 1'b1;
                    sh_active <= 1'b0;
                    if (c_out || !c_hit) begin
                        f_out <= 1'b1;
                        if (sh_type == SH_FIRE && sh_owner_v) begin
                            c_dmg_en[sh_owner] <= 1'b1;
                            if (sh_owner) c_dmg_val1 <= FIRE_BACK; else c_dmg_val0 <= FIRE_BACK;
                            play(SFX_BURN);
                        end else begin
                            play(SFX_OUT);
                        end
                        if (st == ST_FLIGHT) go(ST_IMPACT);
                    end else begin
                        if (c_wall) begin
                            f_wall_hit <= 1'b1;
                            if (sh_type != SH_ICE) begin
                                c_wall_hit <= 1'b1; c_wall_idx <= c_widx;
                                if (wall_breaks_now) f_wall_broke <= 1'b1;
                            end
                        end
                        if (sh_owner_v) begin
                            c_last_set[sh_owner] <= 1'b1; c_last_val <= icol;
                        end
                        c_fx_explode <= 1'b1; c_ex_x <= ix; c_ex_y <= iy;
                        c_ex_kind <= (sh_type == SH_ICE) ? 2'd1 : (sh_type == SH_FIRE) ? 2'd2 : 2'd0;
                        c_ex_big  <= (sh_type == SH_WIDE) || (sh_type == SH_ICE) || (sh_type == SH_FIRE) || (sh_type == SH_METEOR);
                        if (sh_type == SH_ICE) begin
                            if (im_f0) begin c_frz_set[0] <= 1'b1; c_flash_set[0] <= 1'b1; froze0 <= 1'b1; end
                            if (im_f1) begin c_frz_set[1] <= 1'b1; c_flash_set[1] <= 1'b1; froze1 <= 1'b1; end
                            play(SFX_FREEZE);
                            c_fx_shake <= 1'b1; c_shake_val <= 6'd6;
                            c_fx_rgb <= 1'b1; c_rgb_color <= C_CYAN; c_rgb_t <= 6'd24;
                            if (st == ST_FLIGHT) go(ST_IMPACT);
                        end else begin
                            if (im_d0 != 8'd0) begin c_dmg_en[0] <= 1'b1; c_dmg_val0 <= im_d0; end
                            if (im_d1 != 8'd0) begin c_dmg_en[1] <= 1'b1; c_dmg_val1 <= im_d1; end
                            if (im_direct) f_direct <= 1'b1;
                            imp_enemy    <= im_enemy;
                            imp_fire_own <= (sh_type == SH_FIRE) && sh_owner_v;
                            imp_wide     <= (sh_type == SH_WIDE);
                            imp2         <= 2'd2;
                        end
                    end
                end else begin
                    // 계속 날아감: 지나온 칸 기록
                    sh_age <= sh_age + 10'd1;
                    if (!tr_px[9] && tr_px <= 10'sd79 && !tr_py[9] && tr_py <= 10'sd15)
                        trail[{tr_py[3], icol}] <= 1'b1;
                end
            end

            // =========================================================
            // 3) 프레임 틱: 상태별 진행 (시뮬레이터 tick)
            // =========================================================
            else if (tick_frame) begin
                gt   <= gt + 8'd1;
                st_t <= st_t_n;
                aux_t <= (aux_t == 8'hFF) ? aux_t : aux_t + 8'd1;
                if (sh_active && tr_active) sh_phase <= 2'd1;     // 이번 틱에 포탄 한 걸음

                case (st)
                    ST_TITLE: begin
                        if (title_dir) begin
                            if (title_ang >= 7'd88) title_dir <= 1'b0;
                            title_ang <= title_ang + 7'd2;
                        end else begin
                            if (title_ang <= 7'd32) title_dir <= 1'b1;
                            title_ang <= title_ang - 7'd2;
                        end
                    end

                    ST_INTRO: begin
                        if (ev_new) begin
                            if (!roul_started) begin
                                roul_spin <= 1'b1; roul_started <= 1'b1;
                            end else if (!ev_applied && st_t_n >= 8'd70 && !roul_busy) begin
                                c_ev_apply <= 1'b1; ev_applied <= 1'b1; aux_t <= 8'd0;
                                c_fx_rgb <= 1'b1; c_rgb_color <= C_MAGENTA; c_rgb_t <= 6'd30;
                                if (ev_idx == EV_QUAKE) begin
                                    c_pos_set <= 2'b11; c_pos_val0 <= quake_p0; c_pos_val1 <= quake_p1;
                                    c_wall_quake <= 1'b1;
                                    c_fx_shake <= 1'b1; c_shake_val <= 6'd36;
                                    play(SFX_QUAKE);
                                end else begin
                                    play(SFX_FANFARE);
                                end
                            end else if (ev_applied && aux_t >= 8'd40) begin
                                begin_play;
                            end
                        end else if (st_t_n >= 8'd45) begin
                            begin_play;
                        end
                    end

                    ST_AIM: begin
                        if (human) begin
                            // 2/8 길게 누르면 반복 (10틱 뒤부터 2틱마다)
                            if (key_level[K_UP]) begin
                                rep_up <= (rep_up == 5'd31) ? 5'd30 : rep_up + 5'd1;
                                if (rep_up >= 5'd9 && rep_up[0]) c_ang_up[turn] <= 1'b1;
                            end else rep_up <= 5'd0;
                            if (key_level[K_DOWN]) begin
                                rep_dn <= (rep_dn == 5'd31) ? 5'd30 : rep_dn + 5'd1;
                                if (rep_dn >= 5'd9 && rep_dn[0]) c_ang_dn[turn] <= 1'b1;
                            end else rep_dn <= 5'd0;
                        end else begin
                            // CPU 조준 연출 (cpuAim)
                            if (cpu_phase == 2'd1) begin
                                if (st_t_n >= 8'd10) begin
                                    if (cang < cpu_ta) begin
                                        c_ang_up[1] <= 1'b1; if (cang[0]) play(SFX_TICK);
                                    end else if (cang > cpu_ta) begin
                                        c_ang_dn[1] <= 1'b1; if (cang[0]) play(SFX_TICK);
                                    end else begin
                                        cpu_phase <= 2'd2; cpu_w <= 8'd0;
                                    end
                                end
                            end else if (cpu_phase == 2'd2) begin
                                cpu_w <= cpu_w + 8'd1;
                                if (cpu_w == 8'd9 && cshell != cpu_ts) begin
                                    c_sh_set[1] <= 1'b1; c_sh_val <= cpu_ts; play(SFX_ARM);
                                end
                                if (cpu_w >= 8'd25) begin
                                    cpu_phase <= 2'd3; c_pow_start <= 1'b1; go(ST_CHARGE);
                                end
                            end
                        end
                    end

                    ST_CHARGE: begin
                        if (!human && cpu_phase == 2'd3 && st_t_n > 8'd3 &&
                            gauge_pow == cpu_tp && (gauge_up || gauge_pow == POW_MAX))
                            do_fire;
                    end

                    ST_IMPACT: begin
                        if (st_t_n >= 8'd28 && !fx_on) begin
                            if (double_left && !anyone_dead) begin
                                // 두 발: 둘째 탄은 파워 ±1 (첫 발로 이미 끝났으면 안 쏨)
                                double_left <= 1'b0;
                                launch_shell((rnd[1:0] == 2'd0 && gauge_pow > 4'd1) ? gauge_pow - 4'd1 :
                                             (rnd[1:0] == 2'd1 && gauge_pow < POW_MAX) ? gauge_pow + 4'd1 : gauge_pow);
                                play(SFX_FIRE);
                                go(ST_FLIGHT);
                            end else begin
                                res_msg <= res_msg_c;
                                if (de != 8'd0 || froze_e) play(SFX_HIT); else play(SFX_MISS);
                                go(ST_RESULT);
                            end
                        end
                    end

                    ST_RESULT: begin
                        if (st_t_n >= 8'd50 && disp_settled) begin
                            if (anyone_dead) game_over;
                            else if (cfg_move) begin
                                go(ST_MOVE); play(SFX_ARM);
                                mv_planned <= 1'b0; mv_w <= 8'd0; mv_done <= 8'd0;
                                if (cfrozen) begin
                                    mv_frozen <= 1'b1; c_frz_clr[turn] <= 1'b1; play(SFX_FREEZE);
                                end else if (!human) begin
                                    c_cpu_dodge <= 1'b1;
                                end
                            end else next_turn;
                        end
                    end

                    ST_MOVE: begin
                        if (mv_frozen) begin
                            if (st_t_n >= 8'd60) next_turn;
                        end else if (!human && mv_planned) begin
                            // CPU 회피 이동 (cpuMove): 18틱 기다린 뒤 5틱마다 한 칸
                            mv_w <= mv_w + 8'd1;
                            if (mv_w >= 8'd17) begin
                                if (cpos != mv_target) begin
                                    if (mv_w % 5 == 4) try_move(cpos < mv_target);
                                end else begin
                                    mv_done <= mv_done + 8'd1;
                                    if (mv_done >= 8'd15) next_turn;
                                end
                            end
                        end
                    end

                    ST_METEOR: begin
                        if (st_t_n == 8'd1) begin
                            play(SFX_METEOR); met_idx <= 2'd0;
                        end else if (!sh_active && imp2 == 2'd0) begin
                            if (met_idx != 2'd3) begin
                                if (st_t_n >= 8'd1 + 8'd40 * met_idx) begin
                                    met_idx <= met_idx + 2'd1;
                                    if (met_valid) begin
                                        l_raw   <= 1'b1;
                                        l_x     <= {5'd0, met_x, 8'd0};
                                        c_tr_start <= 1'b1;
                                        sh_active <= 1'b1; sh_owner_v <= 1'b0; sh_type <= SH_METEOR;
                                        sh_age <= 10'd99; sh_phase <= 2'd0; trail <= 32'd0;
                                    end
                                end
                            end else if (st_t_n > 8'd30 && !fx_on && disp_settled) begin
                                c_ev_strike_clr <= 1'b1;
                                if (anyone_dead) game_over;
                                else begin c_acc_clr <= 1'b1; go(ST_INTRO); end
                            end
                        end
                    end

                    default: ;
                endcase
            end

            // =========================================================
            // 4) 새 게임 / 다음 턴 준비 (클럭 단위 단계)
            // =========================================================
            else if (st == ST_START) begin
                case (seq)
                    3'd0: begin
                        cfg_special <= dip[0]; cfg_cpu <= dip[1]; cfg_expert <= dip[2]; cfg_events <= dip[3];
                        cfg_move <= dip[4]; cfg_long <= dip[5]; cfg_walls <= dip[7];
                        seq <= 3'd1;
                    end
                    3'd1: begin
                        c_pinit <= 1'b1;
                        c_wall_init <= 1'b1; c_wall_layout <= (rnd[7:0] % 3);
                        c_ev_reset <= 1'b1; c_fx_clear <= 1'b1;
                        sh_active <= 1'b0; trail <= 32'd0; double_left <= 1'b0; mv_frozen <= 1'b0;
                        turn <= 1'b1;                     // next_turn 에서 P1으로 바뀜
                        play(SFX_START);
                        next_turn;
                    end
                    default: seq <= 3'd0;
                endcase
            end else if (st == ST_NEXT) begin
                case (seq)
                    3'd0: begin
                        turn <= ~turn;
                        c_acc_clr <= 1'b1;
                        froze0 <= 1'b0; froze1 <= 1'b0; f_wall_hit <= 1'b0; f_wall_broke <= 1'b0;
                        f_out <= 1'b0; f_direct <= 1'b0; mv_frozen <= 1'b0;
                        ev_applied <= 1'b0; roul_started <= 1'b0;
                        cpu_phase <= 2'd0; mv_planned <= 1'b0;
                        seq <= 3'd1;
                    end
                    3'd1: begin c_turn_begin[turn] <= 1'b1; seq <= 3'd2; end
                    3'd2: seq <= 3'd3;                        // player_unit 이 턴 수를 올릴 때까지 한 클럭
                    3'd3: begin setup <= cfg_move && (turn ? p1_first : p0_first); seq <= 3'd4; end
                    3'd4: begin c_ev_turn <= 1'b1; seq <= 3'd5; end
                    3'd5: seq <= 3'd6;                        // event_unit 이 반영될 때까지 한 클럭
                    3'd6: begin
                        if (!(turn == 1'b0 && p0_first)) play(SFX_TURN);
                        if (ev_strike) go(ST_METEOR); else go(ST_INTRO);
                        aux_t <= 8'd0;
                    end
                    default: seq <= 3'd0;
                endcase
            end

            // =========================================================
            // 5) 키 처리 (시뮬레이터 onKey). 한 클럭에 한 키씩
            // =========================================================
            else if (pend != 10'd0 || pend_rel) begin
                if (pend[K_RESET]) begin
                    pend <= 10'd0; pend_rel <= 1'b0;
                    c_tr_stop <= 1'b1; sh_active <= 1'b0; sh_phase <= 2'd0; c_fx_clear <= 1'b1;
                    roul_home <= 1'b1;
                    go(ST_TITLE);
                end else if (pend_rel && !pend[K_FIRE]) begin
                    pend_rel <= key_release[K_FIRE];
                    if (st == ST_CHARGE && human) do_fire;
                end else begin
                    // 밀린 키 중 하나(key1)만 처리하고 지움
                    pend <= (pend & ~key1) | key_press;
                    if (key1[K_FIRE]) begin
                        if (st == ST_TITLE) start_game;
                        else if (st == ST_OVER && st_t > 8'd40) start_game;
                        else if (human && st == ST_AIM) begin
                            c_pow_start <= 1'b1; go(ST_CHARGE);
                        end else if (human && st == ST_MOVE) next_turn;
                    end else if (human && st == ST_AIM) begin
                        if (key1[K_UP]) begin
                            c_ang_up[turn] <= 1'b1; rep_up <= 5'd1; play(SFX_TICK);
                        end else if (key1[K_DOWN]) begin
                            c_ang_dn[turn] <= 1'b1; rep_dn <= 5'd1; play(SFX_TICK);
                        end else if (key1[K_LEFT] || key1[K_RIGHT]) begin
                            play(SFX_ERR); c_fx_msg <= 1'b1; c_msg_id <= cfg_move ? MSG_FIRE_1ST : MSG_NO_MOVE;
                        end else if (key1[K_SH1] || key1[K_SH2] || key1[K_SH3] || key1[K_SH4]) begin
                            if (!cfg_special) begin
                                play(SFX_ERR); c_fx_msg <= 1'b1; c_msg_id <= MSG_NORM_ONLY;
                            end else begin
                                c_sh_toggle[turn] <= 1'b1;
                                c_sh_val <= key1[K_SH1] ? SH_DOUBLE : key1[K_SH2] ? SH_WIDE : key1[K_SH3] ? SH_ICE : SH_FIRE;
                                play(SFX_ARM);
                            end
                        end
                    end else if (human && st == ST_MOVE) begin
                        if (key1[K_LEFT] || key1[K_RIGHT]) begin
                            if (mv_frozen) play(SFX_ERR);
                            else try_move(key1[K_RIGHT]);
                        end
                    end
                end
            end
        end
    end

    // =================================================================
    // 화면에 넘길 값들 (조합회로)
    // =================================================================
    wire revealed = (st == ST_FLIGHT) || (st == ST_IMPACT) || (st == ST_RESULT) || (st == ST_METEOR) ||
                    (st == ST_MOVE && !setup);
    assign vis0 = cfg_cpu ? 1'b1 : (turn == 1'b0) || revealed;
    assign vis1 = cfg_cpu ? (revealed && !(st == ST_MOVE && turn == 1'b1)) : (turn == 1'b1) || revealed;

    wire viewer = cfg_cpu ? 1'b0 : turn;
    assign q_en  = viewer ? !vis0 : !vis1;
    assign q_col = viewer ? p1_seen : p0_seen;
    wire Lsel = (st == ST_MOVE) ? ~turn : turn;
    assign m_en  = Lsel ? p1_last_v : p0_last_v;
    assign m_col = Lsel ? p1_last : p0_last;

    assign p0_frz_show = p0_frozen || (mv_frozen && turn == 1'b0 && st == ST_MOVE);
    assign p1_frz_show = p1_frozen || (mv_frozen && turn == 1'b1 && st == ST_MOVE);
    assign dmg_show    = (st == ST_RESULT) || (st == ST_METEOR);

    wire fog = ev_active && (ev_id == EV_FOG);
    assign sh_draw       = sh_active && tr_active && ((st == ST_FLIGHT) || (st == ST_METEOR)) && !(fog && sh_owner_v);
    assign sh_trail_draw = sh_draw && sh_owner_v;
    assign sh_px  = tr_px;
    assign sh_py  = tr_py;
    assign sh_ice = (sh_type == SH_ICE);

    assign lcd_on = !((st == ST_OVER) && (st_t < 8'd42) && (((st_t / 7) % 2) == 1));

    // ---- HUD
    wire [5:0] name_msg = setup ? (turn ? (cfg_cpu ? MSG_CPU_MOVE : MSG_P2_MOVE) : MSG_P1_MOVE)
                                : (turn ? (cfg_cpu ? MSG_CPU_TURN : MSG_P2_TURN) : MSG_P1_TURN);
    wire own_al = turn ? AL_RIGHT : AL_LEFT;           // 내 쪽 정렬
    wire opp_r  = !turn;                               // 상대 쪽이 오른쪽인가
    always @(*) begin
        hud_a = 13'd0; hud_b = 13'd0; hud_c = 13'd0;
        case (st)
            ST_INTRO: begin
                if (ev_new && !ev_applied)      hud_a = {gt[2], MSG_EVENT_X, 1'b0, own_al, 4'd0};
                else if (ev_new && aux_t < 30)  hud_a = {1'b1, MSG_LAVA_X + {3'd0, ev_idx}, 1'b0, own_al, 4'd0};
                else                            hud_a = {1'b1, name_msg, 1'b0, own_al, 4'd0};
            end
            ST_AIM, ST_CHARGE: begin
                hud_a = {1'b1, MSG_NORM + {3'd0, shell_eff}, 1'b0, own_al, 4'd0};
                if (wind != 8'sd0) hud_b = {1'b1, HUD_WIND2, AL_LEFT, turn ? 4'd9 : 4'd5};
                hud_c = {1'b1, (msg_on && msg_owner == turn) ? msg_val : HUD_AIM, 1'b0, opp_r, 4'd0};
            end
            ST_RESULT: hud_a = {1'b1, res_msg, 1'b0, own_al, 4'd0};
            ST_METEOR: hud_a = {1'b1, MSG_METEOR_X, AL_LEFT, 4'd0};
            ST_MOVE: begin
                hud_a = {1'b1, mv_frozen ? MSG_FROZEN : (human || setup) ? MSG_MOVE : MSG_DODGE, 1'b0, own_al, 4'd0};
                hud_c = {human && gt[4], MSG_5_END, 1'b0, opp_r, 4'd0};
            end
            ST_FLIGHT, ST_IMPACT: if (wind != 8'sd0) hud_a = {1'b1, HUD_ARROWS, AL_CENTER, 4'd0};
            default: ;
        endcase
    end

    // ---- 7세그 가운데 두 자리 (seg_font 코드)
    always @(*) begin
        if (!cfg_events)                      begin seg_mid0 = 5'd11; seg_mid1 = 5'd11; end          // --
        else if (ev_active)                   begin seg_mid0 = 5'd16; seg_mid1 = {2'd0, ev_id} + 5'd1; end // E1~E6
        else if (ev_new && st == ST_INTRO && !ev_applied)
                                              begin seg_mid0 = gt[2] ? 5'd16 : 5'd10; seg_mid1 = gt[2] ? 5'd16 : 5'd10; end
        else                                  begin seg_mid0 = 5'd10; seg_mid1 = {3'd0, ev_next_in}; end
    end

    assign shell_digit  = (st == ST_TITLE || st == ST_OVER) ? 5'd11 : {2'd0, shell_eff};
    assign servo_deg    = (st == ST_TITLE) ? {1'b0, title_ang} : (turn ? 8'd180 - cang : {1'b0, cang});
    assign led_power    = cur_pow;
    assign rgb_roulette = (st == ST_INTRO) && ev_new && !ev_applied;
    assign charge_on    = (st == ST_CHARGE);
    assign roul_target  = ev_idx;
endmodule
