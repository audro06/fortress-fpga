// 대포 그림 ROM (rom/cannon_rom.mem): 각도 30~90° 마다 8행
//   P1 대포는 그대로, P2 대포는 좌우 반전(mirror = 1)해서 써요.
module cannon_rom (
    input  wire [6:0] ang,      // 30~90
    input  wire [2:0] row,
    input  wire       mirror,
    output wire [4:0] bits
);
    reg [4:0] mem [0:511];
    initial $readmemh("cannon_rom.mem", mem);

    wire [6:0] ai   = (ang < 7'd30) ? 7'd0 : (ang > 7'd90) ? 7'd60 : ang - 7'd30;
    wire [4:0] b    = mem[{ai[5:0], row}];
    assign bits = mirror ? {b[0], b[1], b[2], b[3], b[4]} : b;
endmodule
