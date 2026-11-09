// 16비트 Galois LFSR 난수기 (x^16 + x^14 + x^13 + x^11 + 1, 주기 65535)
// 매 클럭 한 칸씩 돌아가요. 사람이 버튼을 누르는 시점이 매번 달라서 실제로는 예측이 안 돼요.
// 시뮬레이터는 8비트 LFSR(x^8+x^6+x^5+x^4+1)을 썼는데, 한 클럭에 여러 난수를 뽑아야 해서 16비트로 늘렸어요.
module lfsr #(
    parameter [15:0] SEED = 16'hACE1
) (
    input  wire        clk,
    input  wire        rst,
    output reg  [15:0] q
);
    always @(posedge clk) begin
        if (rst)
            q <= SEED;
        else
            q <= {1'b0, q[15:1]} ^ (q[0] ? 16'hB400 : 16'h0000);
    end
endmodule
