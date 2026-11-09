// 8자리 7세그 스캔 표시기
//   chars = {자리0, 자리1, ..., 자리7} 각 5비트 (자리0 = 맨 왼쪽), dp[7:0] (dp[7] = 자리0)
//   1 ms마다 한 자리씩 켜요 (8자리 -> 125 Hz 새로고침)
//   seg_data = {a,b,c,d,e,f,g,dp} (1 = 켜짐), seg_com = 자리 선택 (0 = 선택, 4주차 자료)
//   보드에서 자리 순서가 반대로 나오면 REVERSE = 1
module seg8_ctrl #(
    parameter REVERSE = 1'b0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_ms,
    input  wire [39:0] chars,
    input  wire [7:0]  dp,
    output reg  [7:0]  seg_data,
    output reg  [7:0]  seg_com
);
    reg  [2:0] idx;
    wire [4:0] ch = chars[39 - idx*5 -: 5];
    wire [6:0] seg;

    seg_font u_font (.ch(ch), .seg(seg));

    always @(posedge clk) begin
        if (rst) begin
            idx      <= 3'd0;
            seg_data <= 8'h00;
            seg_com  <= 8'hFF;
        end else if (tick_ms) begin
            idx      <= idx + 3'd1;
            seg_data <= {seg, dp[7 - idx]};
            // seg_com[0] = 보드 AR_SEG_S0
            seg_com  <= ~(REVERSE ? (8'h80 >> idx) : (8'h01 << idx));
        end
    end
endmodule
