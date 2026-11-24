// 8자리 7세그에 보낼 글자 만들기 (조합회로)
//   게임 중: [P1 체력 3자리][가운데 2자리][P2 체력 3자리], 점은 자리2·자리4 (시뮬레이터와 같음)
//   타이틀 : "  PLAy  " <-> "--------" 깜빡임
//   설정   : DIP 상태 그대로 (켜진 스위치는 번호, 꺼진 스위치는 '-'), 예: "12-4-678"
module scoreboard (
    input  wire        title,
    input  wire        setup,
    input  wire [7:0]  dip,
    input  wire        blink,       // 타이틀 깜빡임 위상
    input  wire [7:0]  hp0,         // P1 표시 체력 (0~255)
    input  wire [7:0]  hp1,
    input  wire [4:0]  mid0,        // 가운데 글자 (seg_font 코드)
    input  wire [4:0]  mid1,
    output reg  [39:0] chars,
    output reg  [7:0]  dp
);
    localparam [4:0] BL = 5'd10, DASH = 5'd11, LP = 5'd12, LL = 5'd13, LA = 5'd14, LY = 5'd15;

    function [14:0] hp3;               // 앞자리 0은 빈칸
        input [7:0] v;
        reg [3:0] h, t, o;
        begin
            h = v / 100;
            t = (v / 10) % 10;
            o = v % 10;
            hp3 = {(h == 0) ? BL : {1'b0, h},
                   (h == 0 && t == 0) ? BL : {1'b0, t},
                   {1'b0, o}};
        end
    endfunction

    function [4:0] dipc;               // DIP i 자리 글자
        input       on;
        input [3:0] num;
        begin
            dipc = on ? {1'b0, num} : DASH;
        end
    endfunction

    always @(*) begin
        if (setup) begin
            chars = {dipc(dip[0], 4'd1), dipc(dip[1], 4'd2), dipc(dip[2], 4'd3), dipc(dip[3], 4'd4),
                     dipc(dip[4], 4'd5), dipc(dip[5], 4'd6), dipc(dip[6], 4'd7), dipc(dip[7], 4'd8)};
            dp    = 8'h00;
        end else if (title) begin
            chars = blink ? {BL, BL, LP, LL, LA, LY, BL, BL}
                          : {DASH, DASH, DASH, DASH, DASH, DASH, DASH, DASH};
            dp    = 8'h00;
        end else begin
            chars = {hp3(hp0), mid0, mid1, hp3(hp1)};
            dp    = 8'b0010_1000;          // 자리2, 자리4
        end
    end
endmodule
