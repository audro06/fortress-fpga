// 직접 만든 문자 그림 ROM (rom/glyph_rom.mem, 28개 x 8행, 5비트)
//   주소 = {그림 번호(GLY_*), 행[2:0]},  bit4 = 왼쪽 픽셀
module glyph_rom (
    input  wire [4:0] gid,
    input  wire [2:0] row,
    output wire [4:0] bits
);
    reg [4:0] mem [0:255];
    initial $readmemh("glyph_rom.mem", mem);
    assign bits = mem[{gid, row}];
endmodule
