// 7세그 글자 -> 세그먼트 (조합회로)
//   출력 = {a, b, c, d, e, f, g}  (1 = 켜짐, 4주차 자료처럼 '1' = 0110000)
//   글자 코드: 0~9 숫자, 10 빈칸, 11 '-', 12 'P', 13 'L', 14 'A', 15 'y', 16 'E'
module seg_font (
    input  wire [4:0] ch,
    output reg  [6:0] seg
);
    always @(*) begin
        case (ch)
            5'd0:  seg = 7'b1111110;
            5'd1:  seg = 7'b0110000;
            5'd2:  seg = 7'b1101101;
            5'd3:  seg = 7'b1111001;
            5'd4:  seg = 7'b0110011;
            5'd5:  seg = 7'b1011011;
            5'd6:  seg = 7'b1011111;
            5'd7:  seg = 7'b1110000;
            5'd8:  seg = 7'b1111111;
            5'd9:  seg = 7'b1111011;
            5'd11: seg = 7'b0000001;   // -
            5'd12: seg = 7'b1100111;   // P
            5'd13: seg = 7'b0001110;   // L
            5'd14: seg = 7'b1110111;   // A
            5'd15: seg = 7'b0111011;   // y
            5'd16: seg = 7'b1001111;   // E
            default: seg = 7'b0000000; // 빈칸
        endcase
    end
endmodule
