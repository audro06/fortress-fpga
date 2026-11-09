// 플레이어 한 명의 상태 (P1·P2에 하나씩 인스턴스 = "객체")
//   체력·위치·각도·포탄·얼음·깜빡임·마지막으로 본 상대 위치·마지막 탄착 칸·이번 턴 피해/회복 합계
//   game_core가 1클럭 명령 펄스를 보내면 그 값만 바꿔요.
module player_unit #(
    parameter PI = 0                       // 0 = P1(왼쪽), 1 = P2(오른쪽)
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_frame,

    // 명령
    input  wire       init,                // 새 게임
    input  wire [7:0] init_hp,
    input  wire       turn_begin,          // 이 플레이어 차례 시작 (턴 수 +1)
    input  wire       acc_clr,             // 피해/회복 합계 지우기
    input  wire       ang_up,
    input  wire       ang_dn,
    input  wire       shell_toggle,        // 사람: 같은 키 다시 누르면 일반으로
    input  wire       shell_set,           // CPU: 바로 지정
    input  wire [2:0] shell_val,
    input  wire       pos_inc,
    input  wire       pos_dec,
    input  wire       pos_set,             // 지진
    input  wire [3:0] pos_val,
    input  wire       dmg_en,
    input  wire [7:0] dmg_val,
    input  wire       heal_en,
    input  wire [7:0] heal_val,
    input  wire       freeze_set,
    input  wire       freeze_clr,
    input  wire       flash_set,           // 얼음 맞았을 때 깜빡임
    input  wire       seen_set,            // 발사 순간 상대 위치 기억
    input  wire [3:0] seen_val,
    input  wire       last_set,            // 내 포탄의 마지막 탄착 칸
    input  wire [3:0] last_val,
    input  wire       pow_set,
    input  wire [3:0] pow_val,

    // 상태
    output reg  [7:0] hp,
    output reg  [7:0] max_hp,
    output reg  [7:0] disp_hp,             // 7세그 표시용 (1틱에 1씩 따라감)
    output reg  [3:0] pos,
    output reg  [6:0] ang,
    output reg  [2:0] shell,
    output reg  [3:0] pow,
    output reg        frozen,
    output wire       flash_inv,           // 1이면 몸통 그림 반전 (깜빡임)
    output reg  [3:0] seen,
    output reg  [3:0] last,
    output reg        last_valid,
    output reg  [7:0] dmg_acc,
    output reg  [7:0] heal_acc,
    output wire       first_turn           // 이번이 이 플레이어의 첫 턴
);
    `include "params.vh"

    reg [4:0] flash;
    reg [1:0] turns;                        // 0, 1, 2(이상)

    assign flash_inv  = (flash != 5'd0) && (flash[2] == 1'b0);   // (flash>>2)%2 == 0
    assign first_turn = (turns == 2'd1);

    wire [8:0] hp_heal = hp + heal_val;

    always @(posedge clk) begin
        if (rst) begin
            hp <= 8'd0; max_hp <= 8'd0; disp_hp <= 8'd0; pos <= PI ? 4'd15 : 4'd0;
            ang <= 7'd45; shell <= SH_NORMAL; pow <= 4'd4; frozen <= 1'b0; flash <= 5'd0;
            seen <= 4'd0; last <= 4'd0; last_valid <= 1'b0; dmg_acc <= 8'd0; heal_acc <= 8'd0; turns <= 2'd0;
        end else if (init) begin
            hp <= init_hp; max_hp <= init_hp; disp_hp <= init_hp; pos <= PI ? 4'd15 : 4'd0;
            ang <= 7'd45; shell <= SH_NORMAL; pow <= 4'd4; frozen <= 1'b0; flash <= 5'd0;
            seen <= PI ? 4'd0 : 4'd15;      // 상대 시작 위치
            last <= 4'd0; last_valid <= 1'b0; dmg_acc <= 8'd0; heal_acc <= 8'd0; turns <= 2'd0;
        end else begin
            if (turn_begin && turns != 2'd2) turns <= turns + 2'd1;

            if (ang_up && ang < MAX_ANG) ang <= ang + 7'd1;
            else if (ang_dn && ang > MIN_ANG) ang <= ang - 7'd1;

            if (shell_set)         shell <= shell_val;
            else if (shell_toggle) shell <= (shell == shell_val) ? SH_NORMAL : shell_val;

            if (pos_set)      pos <= pos_val;
            else if (pos_inc) pos <= pos + 4'd1;
            else if (pos_dec) pos <= pos - 4'd1;

            if (pow_set) pow <= pow_val;

            if (acc_clr) begin
                dmg_acc <= 8'd0; heal_acc <= 8'd0;
            end else if (dmg_en) begin
                dmg_acc <= dmg_acc + dmg_val;
            end else if (heal_en) begin
                heal_acc <= heal_acc + ((hp_heal > max_hp) ? (max_hp - hp) : heal_val);
            end

            if (dmg_en)       hp <= (dmg_val >= hp) ? 8'd0 : hp - dmg_val;
            else if (heal_en) hp <= (hp_heal > max_hp) ? max_hp : hp_heal[7:0];

            if (freeze_set)      frozen <= 1'b1;
            else if (freeze_clr) frozen <= 1'b0;

            if (seen_set) seen <= seen_val;
            if (last_set) begin last <= last_val; last_valid <= 1'b1; end

            // 깜빡임 타이머: 피해 26틱, 얼음 20틱 (시뮬레이터)
            if (dmg_en && dmg_val != 8'd0) flash <= 5'd26;
            else if (flash_set)            flash <= 5'd20;
            else if (tick_frame && flash != 5'd0) flash <= flash - 5'd1;

            // 표시 체력은 1틱에 1씩 실제 체력을 따라감
            if (tick_frame) begin
                if (disp_hp > hp)      disp_hp <= disp_hp - 8'd1;
                else if (disp_hp < hp) disp_hp <= disp_hp + 8'd1;
            end
        end
    end
endmodule
