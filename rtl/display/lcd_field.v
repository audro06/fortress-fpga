// 전장 바닥 레이어: 칸 (r, c) 에 무엇이 있는지 (조합회로)
//   시뮬레이터 fieldFrame() 의 앞부분과 같은 순서로 쌓아요:
//   탱크 -> 벽 -> 용암 -> 유성 경고 '!' -> 숨은 상대 '?' -> 지난 탄착 '.'
//   code < 8 이면 CGRAM 슬롯, 아니면 LCD 내장 문자. empty = 아무것도 없음
//   (HUD 글자·폭발·포탄은 lcd_renderer 가 이 위에 얹어요.
//    폭발 칸 밑그림과 포탄 칸 검사에도 이 모듈을 하나씩 더 써요.)
module lcd_field (
    input  wire        r,
    input  wire [3:0]  c,
    input  wire        vis0,
    input  wire        vis1,
    input  wire [3:0]  p0_pos,
    input  wire [3:0]  p1_pos,
    input  wire [5:0]  wall_hp,
    input  wire        wall2_col,
    input  wire [4:0]  lava0,
    input  wire [4:0]  lava1,
    input  wire [14:0] marks,
    input  wire        mark_blink,
    input  wire        q_en,
    input  wire [3:0]  q_col,
    input  wire        m_en,
    input  wire [3:0]  m_col,
    output reg         empty,
    output reg  [7:0]  code
);
    `include "params.vh"

    function [8:0] wall_cell;           // {있음, 코드}
        input [1:0] hp;
        begin
            case (hp)
                2'd3:    wall_cell = {1'b1, CH_FULL};
                2'd2:    wall_cell = {1'b1, 5'd0, SLOT_CRACK};
                2'd1:    wall_cell = {1'b1, 5'd0, SLOT_RUBBLE};
                default: wall_cell = 9'd0;
            endcase
        end
    endfunction

    function mark_at;
        input [14:0] m;
        input [3:0]  cc;
        begin
            mark_at = (m[4] && m[3:0] == cc) || (m[9] && m[8:5] == cc) || (m[14] && m[13:10] == cc);
        end
    endfunction

    wire [3:0] w2c = wall2_col ? WALL_C1 : WALL_C0;
    reg  [8:0] w;

    always @(*) begin
        empty = 1'b1; code = CH_SPACE; w = 9'd0;
        if (r) begin
            // 아랫줄: 탱크
            if (vis0 && c == p0_pos)             begin empty = 1'b0; code = {5'd0, SLOT_P1};  end
            if (vis0 && c == p0_pos + 4'd1)      begin empty = 1'b0; code = {5'd0, SLOT_P1C}; end
            if (vis1 && c == p1_pos)             begin empty = 1'b0; code = {5'd0, SLOT_P2};  end
            if (vis1 && c == p1_pos - 4'd1)      begin empty = 1'b0; code = {5'd0, SLOT_P2C}; end
            // 벽 (블록0 = 7칸, 블록1 = 8칸)
            if (c == WALL_C0) w = wall_cell(wall_hp[1:0]);
            if (c == WALL_C1) w = wall_cell(wall_hp[3:2]);
            if (w[8])                            begin empty = 1'b0; code = w[7:0]; end
            // 용암
            if (empty && ((lava0[4] && lava0[3:0] == c) || (lava1[4] && lava1[3:0] == c)))
                                                 begin empty = 1'b0; code = {5'd0, SLOT_LAVA}; end
            // 숨은 상대 '?', 지난 탄착 '.'
            if (empty && q_en && c == q_col)     begin empty = 1'b0; code = CH_HIDE; end
            if (empty && m_en && c == m_col)     begin empty = 1'b0; code = CH_MARK; end
        end else begin
            // 윗줄: 2층 탑
            if (c == w2c) w = wall_cell(wall_hp[5:4]);
            if (w[8])                            begin empty = 1'b0; code = w[7:0]; end
            // 유성 경고 (깜빡임)
            if (empty && mark_blink && mark_at(marks, c))
                                                 begin empty = 1'b0; code = CH_WARN; end
        end
    end
endmodule
