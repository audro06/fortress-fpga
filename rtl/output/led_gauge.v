// LED 8개
//   게임 중 : 파워 게이지 (파워 p면 LED p개 켜짐)
//   타이틀  : 한 칸이 왕복하는 불빛
//   게임 끝 : 번갈아 깜빡임
module led_gauge (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_frame,
    input  wire       title,
    input  wire       over,
    input  wire [3:0] power,        // 1~8 (0이면 다 꺼짐)
    output reg  [7:0] led           // led[0] = LED_D1
);
    reg [7:0] t;
    reg [1:0] div3;
    reg [3:0] scan;                 // 0~13 왕복 위치

    always @(posedge clk) begin
        if (rst) begin
            t <= 8'd0; div3 <= 2'd0; scan <= 4'd0;
        end else if (tick_frame) begin
            t <= t + 8'd1;
            if (div3 == 2'd2) begin // 3틱마다 한 칸 (시뮬레이터 t/3)
                div3 <= 2'd0;
                scan <= (scan == 4'd13) ? 4'd0 : scan + 4'd1;
            end else begin
                div3 <= div3 + 2'd1;
            end
        end
    end

    wire [3:0] pos = (scan < 4'd8) ? scan : 4'd14 - scan;

    always @(*) begin
        if (title)
            led = 8'h01 << pos;
        else if (over)
            led = t[2] ? 8'b1010_1010 : 8'b0101_0101;
        else if (power >= 4'd8)
            led = 8'hFF;
        else
            led = (8'h01 << power) - 8'h01;
    end
endmodule
