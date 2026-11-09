// Full color LED 4개 (각각 R·G·B 핀, 10주차 자료의 r[3:0] g[3:0] b[3:0])
//   게임 중   : 차례 색 (P1 빨강, P2 파랑)
//   번쩍임    : flash_t > 0 이면 2틱 간격으로 flash_color 와 번갈아 표시 (발사·피격·얼음·이벤트)
//   타이틀    : 무지개가 천천히 흐름,  룰렛 도는 중: 빠르게 흐름
//   게임 끝   : 승자 색 깜빡임 (무승부는 흰색)
module rgb_ctrl (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_frame,
    input  wire       title,
    input  wire       over,
    input  wire       roulette,
    input  wire       turn,          // 0 = P1, 1 = P2
    input  wire [1:0] winner,        // 0 P1, 1 P2, 2 무승부
    input  wire [2:0] flash_color,   // {R,G,B}
    input  wire [5:0] flash_t,
    output wire [3:0] r,
    output wire [3:0] g,
    output wire [3:0] b
);
    `include "params.vh"

    reg [7:0] t;
    always @(posedge clk) begin
        if (rst)             t <= 8'd0;
        else if (tick_frame) t <= t + 8'd1;
    end

    function [2:0] rainbow;
        input [2:0] k;
        begin
            case (k)
                3'd0: rainbow = C_RED;
                3'd1: rainbow = C_YELLOW;
                3'd2: rainbow = C_GREEN;
                3'd3: rainbow = C_CYAN;
                3'd4: rainbow = C_BLUE;
                default: rainbow = C_MAGENTA;
            endcase
        end
    endfunction

    function [2:0] mod6;
        input [7:0] v;
        begin
            mod6 = v % 6;
        end
    endfunction

    reg [2:0] col [0:3];
    integer i;
    always @(*) begin
        for (i = 0; i < 4; i = i + 1) begin
            if (title)
                col[i] = rainbow(mod6({3'd0, t[7:3]} + i));
            else if (roulette)
                col[i] = rainbow(mod6(t + i));
            else if (over)
                col[i] = (winner == 2'd2) ? C_WHITE : (t[3] ? (winner[0] ? C_BLUE : C_RED) : C_OFF);
            else
                col[i] = turn ? C_BLUE : C_RED;
            if (!title && flash_t != 6'd0 && flash_t[1])
                col[i] = flash_color;
        end
    end

    assign r = {col[3][2], col[2][2], col[1][2], col[0][2]};
    assign g = {col[3][1], col[2][1], col[1][1], col[0][1]};
    assign b = {col[3][0], col[2][0], col[1][0], col[0][0]};
endmodule
