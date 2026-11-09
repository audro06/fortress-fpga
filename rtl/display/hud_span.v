// 글자 묶음(span) 하나에서 칸 c의 글자 뽑기 (조합회로)
//   span = {켜짐, 메시지번호[5:0], 정렬[1:0], 칸[3:0]}
//     정렬 0 = 칸부터 왼쪽 정렬,  1 = 오른쪽 끝(16 - 길이),  3 = 가운데(8 - 길이/2)
//     메시지번호 60 = 조준값 "45° P4",  61 = 바람 "<3",  62 = 바람 화살표 "<<<"
//   빈칸 글자는 hit = 0 (시뮬레이터 hudText처럼 빈칸은 안 덮음)
module hud_span (
    input  wire [12:0] span,
    input  wire [3:0]  c,
    input  wire [6:0]  aim_ang,
    input  wire [3:0]  aim_pow,
    input  wire signed [7:0] wind,
    output wire        hit,
    output reg  [7:0]  ch
);
    `include "params.vh"

    wire       en    = span[12];
    wire [5:0] id    = span[11:6];
    wire [1:0] align = span[5:4];
    wire [3:0] col   = span[3:0];

    wire [3:0] wabs  = wind[7] ? -wind[3:0] : wind[3:0];

    wire [7:0] rom_ch;
    wire [4:0] rom_len;
    reg  [3:0] k;
    msg_rom u_msg (.id(id), .col(k), .ch(rom_ch), .len(rom_len));

    wire [4:0] len = (id == 6'd60) ? 5'd6 : (id == 6'd61) ? 5'd2 : (id == 6'd62) ? {1'b0, wabs} : rom_len;
    wire [4:0] start = (align == 2'd1) ? 5'd16 - len : (align == 2'd3) ? 5'd8 - {1'b0, len[4:1]} : {1'b0, col};
    wire       inside = en && ({1'b0, c} >= start) && ({1'b0, c} < start + len);

    wire [6:0] tens = aim_ang / 10;
    wire [6:0] ones = aim_ang % 10;

    always @(*) begin
        k = c - start[3:0];
        case (id)
            6'd60: case (k)
                       4'd0: ch = 8'h30 + {1'b0, tens};
                       4'd1: ch = 8'h30 + {1'b0, ones};
                       4'd2: ch = CH_DEG;
                       4'd3: ch = CH_SPACE;
                       4'd4: ch = CH_P;
                       default: ch = 8'h30 + {4'd0, aim_pow};
                   endcase
            6'd61: ch = (k == 4'd0) ? (wind[7] ? CH_LT : CH_GT) : 8'h30 + {4'd0, wabs};
            6'd62: ch = wind[7] ? CH_LT : CH_GT;
            default: ch = rom_ch;
        endcase
    end

    assign hit = inside && (ch != CH_SPACE);
endmodule
