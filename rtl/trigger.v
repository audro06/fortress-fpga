module trigger(clk, rst, d_in, pulse);

input clk, rst, d_in;
output pulse;

reg s0, s1;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        s0 <= 1'b0;
        s1 <= 1'b0;
    end else begin
        s0 <= d_in;
        s1 <= s0;
    end
end

assign pulse = s0 & ~s1;

endmodule
