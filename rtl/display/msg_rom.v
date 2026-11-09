// 메시지 ROM (rom/msg_rom.mem 16바이트씩, rom/msg_len.mem 길이)
//   번호는 rtl/include/msg_ids.vh
module msg_rom (
    input  wire [5:0] id,
    input  wire [3:0] col,
    output wire [7:0] ch,
    output wire [4:0] len
);
    reg [7:0] mem  [0:1023];
    reg [7:0] lens [0:63];
    initial begin
        $readmemh("msg_rom.mem", mem);
        $readmemh("msg_len.mem", lens);
    end
    assign ch  = mem[{id, col}];
    assign len = lens[id][4:0];
endmodule
