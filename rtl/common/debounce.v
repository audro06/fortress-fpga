// 버튼 디바운서: 2단 동기화 후, 1 ms마다 샘플해서 STABLE_MS번 연속 같은 값이면 출력에 반영
module debounce #(
    parameter integer STABLE_MS = 8,
    parameter         ACTIVE_LOW = 1'b0     // 버튼이 눌렸을 때 0이 들어오는 보드면 1
) (
    input  wire clk,
    input  wire rst,
    input  wire tick_ms,
    input  wire din,          // 보드 버튼 (비동기)
    output reg  dout          // 눌림 = 1
);
    reg s0, s1;
    reg [3:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            s0 <= 1'b0; s1 <= 1'b0; cnt <= 4'd0; dout <= 1'b0;
        end else begin
            s0 <= din ^ ACTIVE_LOW;
            s1 <= s0;
            if (tick_ms) begin
                if (s1 == dout) begin
                    cnt <= 4'd0;
                end else if (cnt == STABLE_MS - 1) begin
                    cnt  <= 4'd0;
                    dout <= s1;
                end else begin
                    cnt <= cnt + 4'd1;
                end
            end
        end
    end
endmodule
