// =====================================================================
// 포트리스 (FORTRESS) 최상위 모듈 - 4조 논리회로 설계 및 실험 텀프로젝트
//
//  [입력부]  keypad_ctrl ── 디바운스 + trigger(눌림 펄스) + 뗌 펄스
//  [제어부]  game_core   ── 메인 FSM + 플레이어·벽·이벤트·탄도·충돌·피해·CPU·연출 객체
//  [출력부]  lcd_ctrl + lcd_renderer (Text LCD)      scoreboard + seg8_ctrl (8자리 7세그)
//            seg_font (1자리 7세그: 포탄 번호)        led_gauge (LED 8개: 파워)
//            rgb_ctrl (Full color LED)                servo_ctrl (서보: 포신 각도)
//            stepper_ctrl (스텝모터: 이벤트 룰렛)      piezo_ctrl (효과음)
//  [공통]    reset_gen, tick_gen(30 Hz 프레임 / 1 kHz), lfsr(난수)
//
//  모든 모듈이 같은 clk 하나로 돌고, 느린 동작은 tick 펄스(enable)로 맞춰요.
//  보드 클럭은 수업처럼 1 MHz 기준이에요. 다르면 CLK_HZ만 바꾸면 돼요.
// =====================================================================
module fortress_top #(
    parameter integer CLK_HZ          = 1_000_000,
    parameter         KEY_ACTIVE_LOW  = 1'b0,    // 버튼 눌림 = 1 이면 0
    parameter         DIP_ACTIVE_LOW  = 1'b0,    // DIP ON = 1 이면 0
    parameter integer STEPS_PER_REV   = 200,     // 보드 스텝모터 1바퀴 스텝 수
    parameter         STEP_HOME_LEVEL = 1'b1,    // 원점 센서 감지 값
    parameter integer SERVO_MIN_US    = 700,
    parameter integer SERVO_MAX_US    = 2300,
    parameter         SERVO_MIRROR    = 1'b1     // 서보 좌우 뒤집기: P1·P2 포신 방향이 서로 바뀌어 보이면 반대로
) (
    input  wire        clk,
    input  wire [11:0] key,          // KEY01..KEY12 = 1 2 3 / 4 5 6 / 7 8 9 / * 0 #
    input  wire [7:0]  dip,          // DIP_SW1..8
    input  wire        step_sensor,

    output wire        lcd_e,
    output wire        lcd_rs,
    output wire        lcd_rw,
    output wire [7:0]  lcd_data,

    output wire [7:0]  seg_data,     // 8자리 7세그 {a,b,c,d,e,f,g,dp}
    output wire [7:0]  seg_com,      // AR_SEG_S0..S7 (0 = 선택)
    output wire [7:0]  seg1_data,    // 1자리 7세그 {a,b,c,d,e,f,g,dp}

    output wire [7:0]  led,
    output wire [3:0]  rgb_r,
    output wire [3:0]  rgb_g,
    output wire [3:0]  rgb_b,
    output wire        piezo,
    output wire        servo,
    output wire [3:0]  step_coil     // {A, B, /A, /B}
);
    `include "params.vh"

    // ------------------------------------------------------------ 공통
    wire rst;
    reset_gen #(.HOLD(CLK_HZ / 1000)) u_rst (.clk(clk), .rst(rst));

    wire tick_frame, tick_ms;
    tick_gen #(.CLK_HZ(CLK_HZ), .FRAME_HZ(30)) u_tick (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .tick_ms(tick_ms)
    );

    wire [15:0] rnd;
    lfsr u_lfsr (.clk(clk), .rst(rst), .q(rnd));

    // ------------------------------------------------------------ 입력
    wire [9:0] key_level, key_press, key_release;
    keypad_ctrl #(.ACTIVE_LOW(KEY_ACTIVE_LOW)) u_keys (
        .clk(clk), .rst(rst), .tick_ms(tick_ms), .key_raw(key),
        .key_level(key_level), .key_press(key_press), .key_release(key_release)
    );

    reg [7:0] dip_s0, dip_s;            // DIP 동기화
    always @(posedge clk) begin
        dip_s0 <= dip ^ {8{DIP_ACTIVE_LOW}};
        dip_s  <= dip_s0;
    end

    // ------------------------------------------------------------ 게임 본체
    wire        roul_busy, roul_tick, roul_home, roul_spin;
    // DIP7 OFF = 조용 모드: 효과음과 함께 서보·스텝모터 출력도 끄고, 룰렛은 바로 끝난 것으로 처리
    wire        motors_on = dip_s[6];
    wire        roul_busy_m, roul_tick_m, servo_m;
    wire [3:0]  step_coil_m;
    assign roul_busy = motors_on ? roul_busy_m : 1'b0;
    assign roul_tick = motors_on ? roul_tick_m : 1'b0;
    assign servo     = motors_on ? servo_m     : 1'b0;
    assign step_coil = motors_on ? step_coil_m : 4'b0000;
    wire [2:0]  roul_target;

    wire [3:0]  st;
    wire [7:0]  st_t, gt;
    wire        turn, setup, cpu_on;
    wire [1:0]  winner;
    wire [6:0]  title_ang;
    wire [2:0]  set_sel;
    wire [3:0]  p0_pos, p1_pos;
    wire [6:0]  p0_ang, p1_ang;
    wire [7:0]  p0_disp, p1_disp;
    wire        p0_frz, p1_frz, p0_inv, p1_inv, vis0, vis1, q_en, m_en, dmg_show;
    wire [3:0]  q_col, m_col;
    wire [7:0]  p0_dmg, p0_heal, p1_dmg, p1_heal;
    wire [5:0]  wall_hp;
    wire        wall2_col;
    wire [4:0]  lava0, lava1;
    wire [14:0] marks;
    wire signed [7:0] wind;
    wire        sh_draw, sh_trail_draw, sh_ice;
    wire signed [9:0] sh_px, sh_py;
    wire [31:0] trail;
    wire        fx_on, fx_row, fx_big, lcd_on;
    wire [4:0]  fx_t;
    wire [3:0]  fx_col;
    wire [1:0]  fx_kind, lcd_shift;
    wire [15:0] fw_cols;
    wire [19:0] fw_ages;
    wire [12:0] hud_a, hud_b, hud_c;
    wire [6:0]  cur_ang;
    wire [3:0]  cur_pow;
    wire [4:0]  seg_mid0, seg_mid1, shell_digit;
    wire [7:0]  servo_deg;
    wire [3:0]  led_power;
    wire        rgb_roulette;
    wire [2:0]  rgb_flash_color;
    wire [5:0]  rgb_flash_t;
    wire        sfx_req, charge_on;
    wire [4:0]  sfx_id;

    game_core u_game (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .rnd(rnd),
        .key_level(key_level), .key_press(key_press), .key_release(key_release), .dip(dip_s),
        .roul_busy(roul_busy), .roul_tick(roul_tick),
        .st(st), .st_t(st_t), .gt(gt), .turn(turn), .setup(setup), .cpu_on(cpu_on), .winner(winner), .title_ang(title_ang), .set_sel(set_sel),
        .p0_pos(p0_pos), .p1_pos(p1_pos), .p0_ang(p0_ang), .p1_ang(p1_ang), .p0_disp(p0_disp), .p1_disp(p1_disp),
        .p0_frz_show(p0_frz), .p1_frz_show(p1_frz), .p0_flash_inv(p0_inv), .p1_flash_inv(p1_inv),
        .vis0(vis0), .vis1(vis1), .q_en(q_en), .q_col(q_col), .m_en(m_en), .m_col(m_col),
        .p0_dmg(p0_dmg), .p0_heal(p0_heal), .p1_dmg(p1_dmg), .p1_heal(p1_heal), .dmg_show(dmg_show),
        .wall_hp(wall_hp), .wall2_col(wall2_col), .lava0(lava0), .lava1(lava1), .marks(marks), .wind(wind),
        .sh_draw(sh_draw), .sh_trail_draw(sh_trail_draw), .sh_px(sh_px), .sh_py(sh_py), .sh_ice(sh_ice), .trail(trail),
        .fx_on(fx_on), .fx_t(fx_t), .fx_col(fx_col), .fx_row(fx_row), .fx_kind(fx_kind), .fx_big(fx_big),
        .lcd_shift(lcd_shift), .lcd_on(lcd_on), .fw_cols(fw_cols), .fw_ages(fw_ages),
        .hud_a(hud_a), .hud_b(hud_b), .hud_c(hud_c), .cur_ang(cur_ang), .cur_pow(cur_pow),
        .seg_mid0(seg_mid0), .seg_mid1(seg_mid1), .shell_digit(shell_digit), .servo_deg(servo_deg),
        .led_power(led_power), .rgb_roulette(rgb_roulette), .rgb_flash_color(rgb_flash_color), .rgb_flash_t(rgb_flash_t),
        .sfx_req(sfx_req), .sfx_id(sfx_id), .charge_on(charge_on),
        .roul_home(roul_home), .roul_spin(roul_spin), .roul_target(roul_target)
    );

    // ------------------------------------------------------------ Text LCD
    wire [5:0] cg_addr;
    wire [4:0] cg_row, dd_addr;
    wire [7:0] dd_char;

    lcd_renderer u_render (
        .st(st), .st_t(st_t), .gt(gt), .cpu_on(cpu_on), .winner(winner), .title_ang(title_ang),
        .dip(dip_s), .set_sel(set_sel),
        .p0_pos(p0_pos), .p1_pos(p1_pos), .p0_ang(p0_ang), .p1_ang(p1_ang),
        .p0_frz(p0_frz), .p1_frz(p1_frz), .p0_inv(p0_inv), .p1_inv(p1_inv),
        .vis0(vis0), .vis1(vis1), .q_en(q_en), .q_col(q_col), .m_en(m_en), .m_col(m_col),
        .p0_dmg(p0_dmg), .p0_heal(p0_heal), .p1_dmg(p1_dmg), .p1_heal(p1_heal), .dmg_show(dmg_show),
        .wall_hp(wall_hp), .wall2_col(wall2_col), .lava0(lava0), .lava1(lava1), .marks(marks), .wind(wind),
        .sh_draw(sh_draw), .sh_trail_draw(sh_trail_draw), .sh_px(sh_px), .sh_py(sh_py), .sh_ice(sh_ice), .trail(trail),
        .fx_on(fx_on), .fx_t(fx_t), .fx_col(fx_col), .fx_row(fx_row), .fx_kind(fx_kind), .fx_big(fx_big),
        .fw_cols(fw_cols), .fw_ages(fw_ages),
        .hud_a(hud_a), .hud_b(hud_b), .hud_c(hud_c), .cur_ang(cur_ang), .cur_pow(cur_pow),
        .dd_addr(dd_addr), .dd_char(dd_char), .cg_addr(cg_addr), .cg_row(cg_row)
    );

    lcd_ctrl #(.CLK_HZ(CLK_HZ)) u_lcd (
        .clk(clk), .rst(rst),
        .cg_addr(cg_addr), .cg_row(cg_row), .dd_addr(dd_addr), .dd_char(dd_char),
        .want_shift(lcd_shift), .want_on(lcd_on),
        .lcd_e(lcd_e), .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_data(lcd_data)
    );

    // ------------------------------------------------------------ 7세그
    wire [39:0] seg_chars;
    wire [7:0]  seg_dp;
    scoreboard u_score (
        .title(st == ST_TITLE), .setup(st == ST_SETUP), .dip(dip_s), .blink(gt[4]), .hp0(p0_disp), .hp1(p1_disp),
        .mid0(seg_mid0), .mid1(seg_mid1), .chars(seg_chars), .dp(seg_dp)
    );
    seg8_ctrl u_seg8 (
        .clk(clk), .rst(rst), .tick_ms(tick_ms), .chars(seg_chars), .dp(seg_dp),
        .seg_data(seg_data), .seg_com(seg_com)
    );

    wire [6:0] seg1;
    seg_font u_seg1 (.ch(shell_digit), .seg(seg1));
    assign seg1_data = {seg1, 1'b0};

    // ------------------------------------------------------------ LED / Full color LED
    led_gauge u_led (
        .clk(clk), .rst(rst), .tick_frame(tick_frame),
        .title(st == ST_TITLE), .over(st == ST_OVER), .setup(st == ST_SETUP), .dip(dip_s),
        .power(led_power), .led(led)
    );

    rgb_ctrl u_rgb (
        .clk(clk), .rst(rst), .tick_frame(tick_frame),
        .title(st == ST_TITLE || st == ST_SETUP), .over(st == ST_OVER), .roulette(rgb_roulette), .turn(turn), .winner(winner),
        .flash_color(rgb_flash_color), .flash_t(rgb_flash_t), .r(rgb_r), .g(rgb_g), .b(rgb_b)
    );

    // ------------------------------------------------------------ 모터 / 소리
    // game_core 는 P1 = 각도, P2 = 180 - 각도로 보내요. 서보를 단 방향에 따라 좌우를 한 번 더 뒤집음
    wire [7:0] servo_target = SERVO_MIRROR ? 8'd180 - servo_deg : servo_deg;

    servo_ctrl #(.CLK_HZ(CLK_HZ), .MIN_US(SERVO_MIN_US), .MAX_US(SERVO_MAX_US)) u_servo (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .target_deg(servo_target), .cur_deg(), .servo(servo_m)
    );

    stepper_ctrl #(.STEPS_PER_REV(STEPS_PER_REV), .HOME_LEVEL(STEP_HOME_LEVEL)) u_step (
        .clk(clk), .rst(rst), .tick_ms(tick_ms), .home(roul_home), .spin(roul_spin), .target_sector(roul_target),
        .sensor(step_sensor), .busy(roul_busy_m), .sector_tick(roul_tick_m), .coil(step_coil_m)
    );

    piezo_ctrl #(.CLK_HZ(CLK_HZ)) u_piezo (
        .clk(clk), .rst(rst), .tick_ms(tick_ms), .enable(dip_s[6]),
        .sfx_req(sfx_req), .sfx_id(sfx_id), .charge_on(charge_on), .charge_pow(led_power),
        .rnd(rnd), .piezo(piezo)
    );
endmodule
