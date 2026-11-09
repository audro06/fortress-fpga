// CPU (항상 P2) - 시뮬레이터 planCPU() / planDodge()
//
// [조준 계획] plan_aim 펄스
//   자기 전용 trajectory + collision 을 갖고, 각도 30~80 x 파워 1~8 (408가지)를
//   한 클럭에 반 틱씩 실제로 날려 보고 가장 가까이 떨어지는 조합을 골라요.
//   CPU도 상대의 "마지막으로 본 위치"(seen0)만 알아요.
//   점수 = 거리*64 + |각도-45|  (상대 직격이면 거리 0, 자기 직격이면 +100)
//   그다음 난수로 실수를 섞어요 (보통: 각도 ±2~5 또는 파워 ±1, 고수: 가끔 각도 ±1)
//   1 MHz에서 보통 수십 ms 안에 끝나요.
//
// [회피 계획] plan_dodge 펄스
//   이동할 칸 10~15 중 점수가 가장 큰 칸: 상대의 마지막 탄착에서 멀수록 +, 제자리 -2,
//   유성 예고 칸 -6, 용암 칸은 제외, 난수 0~3 더함
module cpu_ai (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] rnd,

    input  wire        plan_aim,
    input  wire        plan_dodge,
    input  wire        expert,          // DIP3
    input  wire        special_on,      // DIP1
    input  wire        move_on,         // DIP5
    input  wire signed [7:0] wind,
    input  wire [7:0]  grav,
    input  wire [3:0]  seen0,           // CPU가 기억하는 P1 위치
    input  wire [3:0]  my_pos,          // P2 몸통 칸
    input  wire [7:0]  my_hp,
    input  wire [7:0]  my_max,
    input  wire [5:0]  wall_hp,
    input  wire        wall2_col,
    input  wire [4:0]  lava0,
    input  wire [4:0]  lava1,
    input  wire [14:0] marks,
    input  wire        enemy_last_valid,
    input  wire [3:0]  enemy_last,

    output reg         aim_done,        // 1클럭
    output reg  [6:0]  aim_ang,
    output reg  [3:0]  aim_pow,
    output reg  [2:0]  aim_shell,
    output reg         dodge_done,      // 1클럭
    output reg  [3:0]  dodge_target
);
    `include "params.vh"

    // ================================================================ 조준 탐색
    localparam [2:0] A_IDLE = 3'd0, A_START = 3'd1, A_STEP = 3'd2, A_CHECK = 3'd3, A_FINISH = 3'd4;
    reg [2:0]  ast;
    reg [6:0]  a;
    reg [3:0]  p;
    reg [9:0]  age;
    reg signed [7:0] wg;
    reg        best_valid;
    reg [6:0]  best_a;
    reg [3:0]  best_p;
    reg [15:0] best_s;

    wire tr_start = (ast == A_START);
    wire tr_step  = (ast == A_STEP);
    wire tr_stop;
    wire tr_active, tr_ground, tr_out;
    wire signed [9:0] tr_px, tr_py;

    wire [6:0] pivot = (my_pos - 4'd1) * 5 + 3;          // P2 대포 칸 기준
    wire [6:0] aidx  = a - 7'd30;
    wire [2:0] pm1   = p[2:0] - 3'd1;                    // 파워 8 -> 7

    trajectory u_traj (
        .clk(clk), .rst(rst), .start(tr_start), .step(tr_step), .stop(tr_stop),
        .angle_idx(aidx[5:0]), .power_idx({pm1, 1'b1}), .dir(1'b1), .pivot_x(pivot),
        .start_x(20'sd0), .start_h(20'sd0), .start_vx(20'sd0), .start_vh(20'sd0), .use_raw(1'b0),
        .wind(wg), .grav(grav),
        .active(tr_active), .px(tr_px), .py(tr_py), .hit_ground(tr_ground), .out_of_map(tr_out)
    );

    wire c_hit, c_out, c_wall, c_direct, c_dpi, c_ground;
    wire [1:0] c_widx;
    collision u_col (
        .px(tr_px), .py(tr_py), .hit_ground(tr_ground), .out_of_map(tr_out),
        .owner_valid(1'b1), .owner(1'b1), .self_skip(age < SELF_SKIP),
        .p0_pos(seen0), .p1_pos(my_pos), .wall_hp(wall_hp), .wall2_col(wall2_col),
        .hit(c_hit), .is_out(c_out), .is_wall(c_wall), .wall_idx(c_widx),
        .is_direct(c_direct), .direct_pi(c_dpi), .is_ground(c_ground)
    );

    wire        done_one = (ast == A_CHECK) && (c_hit || age == MAX_FLIGHT - 1);
    assign      tr_stop  = done_one;
    wire        usable   = c_hit && !c_out;
    wire [7:0]  tx       = seen0 * 5 + 5;
    wire signed [10:0] dxs = tr_px - $signed({3'd0, tx});
    wire [9:0]  dabs     = dxs[10] ? -dxs : dxs;
    wire [9:0]  dist     = (c_direct && !c_dpi) ? 10'd0 : dabs + ((c_direct && c_dpi) ? 10'd100 : 10'd0);
    wire [6:0]  adev     = (a > 7'd45) ? a - 7'd45 : 7'd45 - a;
    wire [15:0] score    = {dist, 6'd0} + adev;

    // 마무리 계산 (난수 실수 + 포탄 고르기)
    wire [6:0]  base_a = best_valid ? best_a : 7'd45;
    wire [3:0]  base_p = best_valid ? best_p : 4'd6;
    wire [2:0]  e5   = rnd[7:0] % 5;
    wire        sgn  = rnd[8];
    wire [2:0]  big  = 3'd2 + rnd[10:9];               // 2~5
    wire [7:0]  a_err = !expert ? ((e5 < 3'd2) ? (sgn ? base_a + big : base_a - big) : base_a)
                                : ((rnd[12:11] == 2'd0) ? (sgn ? base_a + 7'd1 : base_a - 7'd1) : base_a);
    wire [4:0]  p_err = (!expert && e5 == 3'd2) ? (sgn ? base_p + 4'd1 : base_p - 4'd1) : base_p;
    wire [6:0]  a_fin = (a_err < MIN_ANG) ? MIN_ANG : (a_err > MAX_ANG) ? MAX_ANG : a_err[6:0];
    wire [3:0]  p_fin = (p_err < 5'd1) ? 4'd1 : (p_err > POW_MAX) ? POW_MAX : p_err[3:0];
    wire        sure  = best_valid && (best_s < 16'd192);  // 거리 < 3
    wire [3:0]  r10   = rnd[15:8] % 10;
    wire        low_hp = ({my_hp, 4'd0} + {my_hp, 2'd0}) <= (my_max * 9);   // hp*20 <= max*9
    reg  [2:0]  sh_pick;
    always @(*) begin
        if (!special_on)                   sh_pick = SH_NORMAL;
        else if (low_hp && sure)           sh_pick = SH_FIRE;
        else if (r10 < 4'd2)               sh_pick = SH_DOUBLE;
        else if (r10 < 4'd4 && !expert)    sh_pick = SH_WIDE;
        else if (r10 < 4'd5 && move_on)    sh_pick = SH_ICE;
        else if (r10 < 4'd6 && sure)       sh_pick = SH_FIRE;
        else                               sh_pick = SH_NORMAL;
    end

    always @(posedge clk) begin
        if (rst) begin
            ast <= A_IDLE; a <= 7'd30; p <= 4'd1; age <= 10'd0; wg <= 8'sd0;
            best_valid <= 1'b0; best_a <= 7'd45; best_p <= 4'd6; best_s <= 16'hFFFF;
            aim_done <= 1'b0; aim_ang <= 7'd45; aim_pow <= 4'd4; aim_shell <= SH_NORMAL;
        end else begin
            aim_done <= 1'b0;
            case (ast)
                A_IDLE: if (plan_aim) begin
                    a <= MIN_ANG; p <= 4'd1; best_valid <= 1'b0; best_s <= 16'hFFFF;
                    // 보통 CPU는 바람을 ±1 틀리게 읽음
                    wg  <= (expert || wind == 8'sd0) ? wind : wind + $signed({6'd0, rnd[1:0] % 3}) - 8'sd1;
                    ast <= A_START;
                end
                A_START: begin age <= 10'd0; ast <= A_STEP; end
                A_STEP:  ast <= A_CHECK;
                A_CHECK: begin
                    if (done_one) begin
                        if (usable && score < best_s) begin
                            best_valid <= 1'b1; best_s <= score; best_a <= a; best_p <= p;
                        end
                        if (p == POW_MAX) begin
                            p <= 4'd1;
                            if (a == CPU_MAX_ANG) ast <= A_FINISH;
                            else begin a <= a + 7'd1; ast <= A_START; end
                        end else begin
                            p <= p + 4'd1; ast <= A_START;
                        end
                    end else begin
                        age <= age + 10'd1;
                        ast <= A_STEP;
                    end
                end
                A_FINISH: begin
                    aim_ang <= a_fin; aim_pow <= p_fin; aim_shell <= sh_pick;
                    aim_done <= 1'b1;
                    ast <= A_IDLE;
                end
                default: ast <= A_IDLE;
            endcase
        end
    end

    // ================================================================ 회피 위치
    reg        dbusy;
    reg [3:0]  dc;
    reg signed [7:0] dbs;

    wire [3:0] cl = dc - 4'd1;                        // 탱크 칸 [c-1, c]
    function cell_in;                                  // {유효,칸} 이 cl 또는 dc 와 같음
        input [4:0] v;
        input [3:0] x0, x1;
        begin
            cell_in = v[4] && (v[3:0] == x0 || v[3:0] == x1);
        end
    endfunction
    wire on_lava  = cell_in(lava0, cl, dc) || cell_in(lava1, cl, dc);
    wire on_mark  = cell_in(marks[4:0], cl, dc) || cell_in(marks[9:5], cl, dc) || cell_in(marks[14:10], cl, dc);
    wire [3:0] ref_c = enemy_last_valid ? enemy_last : my_pos;
    wire [3:0] far   = (dc > ref_c) ? dc - ref_c : ref_c - dc;
    wire signed [7:0] dsc = $signed({4'd0, far}) + $signed({6'd0, rnd[1:0]})
                          - ((dc == my_pos) ? 8'sd2 : 8'sd0) - (on_mark ? 8'sd6 : 8'sd0);

    always @(posedge clk) begin
        if (rst) begin
            dbusy <= 1'b0; dc <= 4'd10; dbs <= -8'sd1; dodge_done <= 1'b0; dodge_target <= 4'd15;
        end else begin
            dodge_done <= 1'b0;
            if (plan_dodge) begin
                dbusy <= 1'b1; dc <= P2_MIN; dbs <= -8'sd1; dodge_target <= my_pos;
            end else if (dbusy) begin
                if (!on_lava && dsc > dbs) begin
                    dbs <= dsc; dodge_target <= dc;
                end
                if (dc == P2_MAX) begin
                    dbusy <= 1'b0; dodge_done <= 1'b1;
                end else begin
                    dc <= dc + 4'd1;
                end
            end
        end
    end
endmodule
