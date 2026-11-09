// 탄착 피해 계산 (조합회로). 시뮬레이터 impact() 의 피해 부분
//   직격이면 [직격] 피해, 아니면 탄착 x와 탱크 가운데 x의 거리 dx로
//   dx <= 근접범위 -> [근접],  dx <= 스침범위 -> [스침],  그 밖은 0
//   탱크 가운데 x: P1 = 5*pos + 5,  P2 = 5*pos   (몸통+대포 두 칸의 가운데)
//   얼음: 피해 대신 탄착 칸 ±1 안에 탱크 칸이 있으면 얼림
module impact_calc (
    input  wire [2:0] shell,         // SH_*
    input  wire       is_direct,
    input  wire       direct_pi,
    input  wire [6:0] ix,            // 탄착 x 픽셀 (0~79)
    input  wire [3:0] p0_pos,
    input  wire [3:0] p1_pos,
    input  wire       owner_valid,
    input  wire       owner,
    output wire [7:0] dmg0,
    output wire [7:0] dmg1,
    output wire       frz0,
    output wire       frz1,
    output wire       enemy_hit,     // 상대에게 피해를 줬음 (불 포탄 회복 조건)
    output wire       direct_enemy   // 상대 직격 (DIRECT! 메시지)
);
    `include "params.vh"

    reg [7:0] d0, d1, d2, r0, r1;
    always @(*) begin
        case (shell)
            SH_DOUBLE: begin d0 = DOUBLE_D0; d1 = DOUBLE_D1; d2 = DOUBLE_D2; r0 = DOUBLE_R0; r1 = DOUBLE_R1; end
            SH_WIDE:   begin d0 = WIDE_D0;   d1 = WIDE_D1;   d2 = WIDE_D2;   r0 = WIDE_R0;   r1 = WIDE_R1;   end
            SH_ICE:    begin d0 = 8'd0;      d1 = 8'd0;      d2 = 8'd0;      r0 = 8'd0;      r1 = 8'd0;      end
            SH_FIRE:   begin d0 = FIRE_D0;   d1 = FIRE_D1;   d2 = FIRE_D2;   r0 = FIRE_R0;   r1 = FIRE_R1;   end
            SH_METEOR: begin d0 = METEOR_D0; d1 = METEOR_D1; d2 = METEOR_D2; r0 = METEOR_R0; r1 = METEOR_R1; end
            default:   begin d0 = NORMAL_D0; d1 = NORMAL_D1; d2 = NORMAL_D2; r0 = NORMAL_R0; r1 = NORMAL_R1; end
        endcase
    end

    wire [7:0] cx0 = p0_pos * 5 + 5;
    wire [7:0] cx1 = p1_pos * 5;
    wire [7:0] dx0 = (ix > cx0) ? ix - cx0 : cx0 - ix;
    wire [7:0] dx1 = (ix > cx1) ? ix - cx1 : cx1 - ix;

    function [7:0] splash;
        input [7:0] dx, rr0, rr1, dd1, dd2;
        begin
            splash = (dx <= rr0) ? dd1 : (dx <= rr1) ? dd2 : 8'd0;
        end
    endfunction

    wire ice = (shell == SH_ICE);
    assign dmg0 = ice ? 8'd0 : (is_direct && direct_pi == 1'b0) ? d0 : splash(dx0, r0, r1, d1, d2);
    assign dmg1 = ice ? 8'd0 : (is_direct && direct_pi == 1'b1) ? d0 : splash(dx1, r0, r1, d1, d2);

    // 얼음: 탱크 칸 [lo, hi] 와 탄착 칸 c 가 1칸 이내
    wire [14:0] ixm = ix * 15'd205;
    wire [3:0]  c   = ixm[13:10];                      // ix / 5 (ix 0~79)
    wire [4:0] lo0 = p0_pos,         hi0 = p0_pos + 1;
    wire [4:0] lo1 = p1_pos - 1,     hi1 = p1_pos;
    assign frz0 = ice && (c + 1 >= lo0) && (c <= hi0 + 1);
    assign frz1 = ice && (c + 1 >= lo1) && (c <= hi1 + 1);

    assign enemy_hit    = owner_valid && (owner ? (dmg0 != 8'd0) : (dmg1 != 8'd0));
    assign direct_enemy = owner_valid && is_direct && (direct_pi != owner);
endmodule
