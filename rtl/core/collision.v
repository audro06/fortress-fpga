// 포탄 충돌 판정 (조합회로). 시뮬레이터 collide()와 같은 순서:
//   맵 밖 -> 벽 -> 탱크 직격 (py >= HIT_Y, 발사 직후 SELF_SKIP틱은 자기 탱크 제외) -> 땅 (h <= 0)
//   칸 번호 c = floor(px / 5)
module collision (
    input  wire signed [9:0] px,
    input  wire signed [9:0] py,
    input  wire              hit_ground,
    input  wire              out_of_map,
    input  wire              owner_valid,   // 0 = 유성 (주인 없음)
    input  wire              owner,         // 0 = P1, 1 = P2
    input  wire              self_skip,     // 1 = 아직 자기 탱크 판정 제외 시간
    input  wire [3:0]        p0_pos,        // P1 몸통 칸 (대포는 +1)
    input  wire [3:0]        p1_pos,        // P2 몸통 칸 (대포는 -1)
    input  wire [5:0]        wall_hp,       // {블록2, 블록1, 블록0} 각 2비트
    input  wire              wall2_col,     // 블록2(윗층) 칸: 0 = 7, 1 = 8
    output wire              hit,
    output wire              is_out,
    output wire              is_wall,
    output wire [1:0]        wall_idx,
    output wire              is_direct,
    output wire              direct_pi,
    output wire              is_ground
);
    `include "params.vh"

    // floor(px/5): px 0~127 은 (px*205)>>10 과 같음 (tools에서 확인), 음수는 -1
    wire [6:0]  pxu   = px[6:0];
    wire [14:0] prod  = pxu * 15'd205;
    wire signed [5:0] c = px[9] ? -6'sd1 : {1'b0, prod[14:10]};

    // ---- 벽: 블록 i 의 (행, 칸), 맨 위 y = 행*8 + (hp >= 2 ? 0 : 4)
    wire [1:0] hp0 = wall_hp[1:0], hp1 = wall_hp[3:2], hp2 = wall_hp[5:4];
    wire w0 = (hp0 != 2'd0) && (c == WALL_C0) && (py >= ((hp0 >= 2'd2) ? 8 : 12)) && (py < 16);
    wire w1 = (hp1 != 2'd0) && (c == WALL_C1) && (py >= ((hp1 >= 2'd2) ? 8 : 12)) && (py < 16);
    wire w2 = (hp2 != 2'd0) && (c == (wall2_col ? WALL_C1 : WALL_C0)) && (py >= ((hp2 >= 2'd2) ? 0 : 4)) && (py < 8);

    // ---- 탱크 직격
    wire low  = (py >= HIT_Y);
    wire t0   = low && !(owner_valid && owner == 1'b0 && self_skip) && (c == p0_pos || c == p0_pos + 1);
    wire t1   = low && !(owner_valid && owner == 1'b1 && self_skip) && (c == p1_pos || c == p1_pos - 1);

    assign is_out    = out_of_map;
    assign is_wall   = !is_out && (w0 || w1 || w2);
    assign wall_idx  = w0 ? 2'd0 : w1 ? 2'd1 : 2'd2;
    assign is_direct = !is_out && !is_wall && (t0 || t1);
    assign direct_pi = !t0;                 // P1 먼저 검사 (시뮬레이터 순서)
    assign is_ground = !is_out && !is_wall && !is_direct && hit_ground;
    assign hit       = is_out || is_wall || is_direct || is_ground;
endmodule
