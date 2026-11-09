// 전원 켤 때 리셋: 처음 HOLD 클럭 동안 rst = 1
// (보드에 따로 리셋 버튼을 안 쓰고, 게임 리셋은 키패드 #으로 해요)
module reset_gen #(
    parameter integer HOLD = 1000          // 1 MHz 기준 1 ms
) (
    input  wire clk,
    output reg  rst = 1'b1
);
    reg [15:0] cnt = 16'd0;
    always @(posedge clk) begin
        if (cnt < HOLD) begin
            cnt <= cnt + 16'd1;
            rst <= 1'b1;
        end else begin
            rst <= 1'b0;
        end
    end
endmodule
