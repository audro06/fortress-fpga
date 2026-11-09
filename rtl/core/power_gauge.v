// 파워 게이지: 5를 누르는 동안 2틱마다 1~POW_MAX 사이를 왕복 (시뮬레이터 CHARGE)
module power_gauge (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_frame,
    input  wire       start,        // 충전 시작 (파워 1, 올라가는 방향)
    input  wire       run,          // CHARGE 상태일 때 1
    output reg  [3:0] pow,
    output reg        dir_up
);
    `include "params.vh"

    reg half;   // 2틱에 한 번

    always @(posedge clk) begin
        if (rst) begin
            pow <= 4'd1; dir_up <= 1'b1; half <= 1'b0;
        end else if (start) begin
            pow <= 4'd1; dir_up <= 1'b1; half <= 1'b0;
        end else if (tick_frame && run) begin
            half <= ~half;
            if (half) begin
                if (dir_up) begin
                    if (pow >= POW_MAX - 1) begin pow <= POW_MAX; dir_up <= 1'b0; end
                    else pow <= pow + 4'd1;
                end else begin
                    if (pow <= 4'd2) begin pow <= 4'd1; dir_up <= 1'b1; end
                    else pow <= pow - 4'd1;
                end
            end
        end
    end
endmodule
