// CGRAM 슬롯 0~6 (+타이틀 7) 의 한 행 그림 (조합회로)
//   게임 화면: 0 P1 몸통, 1 P1 대포(각도), 2 P2 몸통, 3 P2 대포(반전), 4 금 간 벽, 5 잔해, 6 용암
//              (7 = 포탄/폭발 스프라이트는 lcd_renderer 가 따로 만듦 -> 여기선 0)
//   타이틀   : 0~3 같음(대포는 title_ang), 4~7 특수 포탄 아이콘
//   게임 끝  : 0 P1, 2 P2 (승자 몸통), 4 트로피
//   몸통 꾸밈: 얼음이면 테두리, 깜빡임이면 반전 (시뮬레이터 personRows)
module cgram_slot (
    input  wire [1:0] mode,        // 0 게임, 1 타이틀, 2 게임 끝
    input  wire [2:0] slot,
    input  wire [2:0] row,
    input  wire [6:0] p0_ang,
    input  wire [6:0] p1_ang,
    input  wire [6:0] title_ang,
    input  wire       p0_frz,
    input  wire       p1_frz,
    input  wire       p0_inv,
    input  wire       p1_inv,
    output reg  [4:0] bits
);
    `include "params.vh"
    `include "glyph_ids.vh"

    reg  [4:0] gid;
    wire [4:0] gbits;
    glyph_rom u_gly (.gid(gid), .row(row), .bits(gbits));

    wire       p2_side = (slot == SLOT_P2C);
    wire [6:0] c_ang   = (mode == 2'd1) ? title_ang : (p2_side ? p1_ang : p0_ang);
    wire [4:0] cbits;
    cannon_rom u_can (.ang(c_ang), .row(row), .mirror(p2_side), .bits(cbits));

    always @(*) begin
        case (mode)
            2'd1: case (slot)                          // 타이틀
                      3'd0: gid = GLY_P1;      3'd2: gid = GLY_P2;
                      3'd4: gid = GLY_SH_X2;   3'd5: gid = GLY_SH_WIDE;
                      3'd6: gid = GLY_SH_ICE;  default: gid = GLY_SH_FIRE;
                  endcase
            2'd2: case (slot)                          // 게임 끝
                      3'd0: gid = GLY_P1;      3'd2: gid = GLY_P2;
                      default: gid = GLY_CUP;
                  endcase
            default: case (slot)                       // 게임 화면
                      3'd0: gid = GLY_P1;      3'd2: gid = GLY_P2;
                      3'd4: gid = GLY_CRACK;   3'd5: gid = GLY_RUBBLE;
                      default: gid = GLY_LAVA;
                  endcase
        endcase
    end

    wire frz = (mode == 2'd0) && ((slot == SLOT_P1) ? p0_frz : p1_frz);
    wire inv = (mode == 2'd0) && ((slot == SLOT_P1) ? p0_inv : p1_inv);
    wire [4:0] body = (gbits | (frz ? ((row == 3'd0 || row == 3'd7) ? 5'h1F : 5'h11) : 5'h00)) ^ (inv ? 5'h1F : 5'h00);

    always @(*) begin
        if (slot == SLOT_P1C || slot == SLOT_P2C)
            bits = (mode == 2'd2) ? 5'd0 : cbits;
        else if (slot == SLOT_P1 || slot == SLOT_P2)
            bits = body;
        else if (mode == 2'd2)
            bits = (slot == 3'd4) ? gbits : 5'd0;
        else if (mode == 2'd0 && slot == SLOT_SPR)
            bits = 5'd0;
        else
            bits = gbits;
    end
endmodule
