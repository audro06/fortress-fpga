// 3x4 키패드(버튼 12개, 핀이 하나씩 따로 있음) -> 논리 키 10개
//   key_raw 순서 = 보드 KEY01..KEY12 = '1','2','3','4','5','6','7','8','9','*','0','#'
//   출력 비트 번호는 params.vh 의 K_* 참고
//   key_level   : 지금 눌려 있음 (디바운스 후)
//   key_press   : 눌린 순간 1클럭 (수업 trigger 모듈 사용)
//   key_release : 뗀 순간 1클럭 (발사 버튼 5에 사용)
module keypad_ctrl #(
    parameter ACTIVE_LOW = 1'b0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_ms,
    input  wire [11:0] key_raw,
    output wire [9:0]  key_level,
    output wire [9:0]  key_press,
    output reg  [9:0]  key_release
);
    `include "params.vh"

    // 보드 버튼 -> 논리 키 연결표
    wire [9:0] raw_logic;
    assign raw_logic[K_FIRE]  = key_raw[4];   // '5'
    assign raw_logic[K_UP]    = key_raw[1];   // '2'
    assign raw_logic[K_DOWN]  = key_raw[7];   // '8'
    assign raw_logic[K_LEFT]  = key_raw[3];   // '4'
    assign raw_logic[K_RIGHT] = key_raw[5];   // '6'
    assign raw_logic[K_SH1]   = key_raw[0];   // '1'
    assign raw_logic[K_SH2]   = key_raw[2];   // '3'
    assign raw_logic[K_SH3]   = key_raw[6];   // '7'
    assign raw_logic[K_SH4]   = key_raw[8];   // '9'
    assign raw_logic[K_RESET] = key_raw[11];  // '#'

    reg [9:0] level_d;

    genvar i;
    generate
        for (i = 0; i < 10; i = i + 1) begin : g_key
            debounce #(.ACTIVE_LOW(ACTIVE_LOW)) u_db (
                .clk(clk), .rst(rst), .tick_ms(tick_ms),
                .din(raw_logic[i]), .dout(key_level[i])
            );
            trigger u_trig (
                .clk(clk), .rst(rst), .d_in(key_level[i]), .pulse(key_press[i])
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            level_d     <= 10'd0;
            key_release <= 10'd0;
        end else begin
            level_d     <= key_level;
            key_release <= level_d & ~key_level;
        end
    end
endmodule
