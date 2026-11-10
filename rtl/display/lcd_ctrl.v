// Text LCD 제어기: 초기화 후 화면 전체를 계속 다시 써요
//   전원 대기 50 ms -> 0x38 x3 (8비트, 2줄) -> 0x0C (표시 ON) -> 0x01 (지우기) -> 0x06 (오른쪽으로 진행)
//   반복: CGRAM 8칸 x 8행 (0x40 + 64바이트) -> 윗줄 (0x80 + 16바이트) -> 아랫줄 (0xC0 + 16바이트)
//         -> 흔들림(표시 이동 0x18/0x1C)과 깜빡임(표시 ON/OFF 0x0C/0x08) 맞추기
//   한 바퀴 98바이트 x 약 103 us = 약 10 ms (게임 프레임 33 ms 안에 충분)
//   쓸 내용은 lcd_renderer 에 주소를 주고 바로 받아와요 (조합회로).
module lcd_ctrl #(
    parameter integer CLK_HZ  = 1_000_000,
    parameter integer EXEC_US = 100          // 글자 하나 쓰고 기다리는 시간 (LCD가 글자를 빠뜨리면 늘리세요)
) (
    input  wire       clk,
    input  wire       rst,
    output reg  [5:0] cg_addr,       // {슬롯[2:0], 행[2:0]}
    input  wire [4:0] cg_row,
    output reg  [4:0] dd_addr,       // {줄, 칸[3:0]}
    input  wire [7:0] dd_char,
    input  wire [1:0] want_shift,    // 0 그대로, 1 오른쪽 한 칸, 2 왼쪽 한 칸
    input  wire       want_on,
    output wire       lcd_e,
    output wire       lcd_rs,
    output wire       lcd_rw,
    output wire [7:0] lcd_data
);
    localparam integer US      = (CLK_HZ / 1_000_000 < 1) ? 1 : CLK_HZ / 1_000_000;
    localparam integer T_POWER = 50_000 * US;

    localparam [3:0] S_POWER = 4'd0, S_INIT = 4'd1, S_CG_CMD = 4'd2, S_CG = 4'd3,
                     S_D0_CMD = 4'd4, S_D0 = 4'd5, S_D1_CMD = 4'd6, S_D1 = 4'd7,
                     S_SHIFT = 4'd8, S_ONOFF = 4'd9, S_WAIT = 4'd10;

    reg  [3:0]  st, st_after;        // S_WAIT 다음에 갈 상태
    reg  [23:0] cnt;
    reg  [2:0]  init_i;
    reg  [6:0]  idx;
    reg  signed [1:0] cur_shift;
    reg         cur_on;

    reg         d_start, d_rs, d_long;
    reg  [7:0]  d_data;
    wire        d_busy, d_done;

    lcd_driver #(.CLK_HZ(CLK_HZ), .EXEC_US(EXEC_US)) u_drv (
        .clk(clk), .rst(rst), .start(d_start), .rs(d_rs), .data(d_data), .long(d_long),
        .busy(d_busy), .done(d_done),
        .lcd_e(lcd_e), .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_data(lcd_data)
    );

    wire init_long = (init_i <= 3'd4);            // 0x38 x3, 0x0C, 0x01 은 넉넉히 기다림
    wire signed [1:0] want_s = (want_shift == 2'd1) ? 2'sd1 : (want_shift == 2'd2) ? -2'sd1 : 2'sd0;

    function [7:0] init_cmd;
        input [2:0] i;
        begin
            case (i)
                3'd0, 3'd1, 3'd2: init_cmd = 8'h38;   // Function set: 8비트, 2줄, 5x8
                3'd3:             init_cmd = 8'h0C;   // 표시 ON, 커서 OFF
                3'd4:             init_cmd = 8'h01;   // 지우기
                default:          init_cmd = 8'h06;   // 입력 모드: 주소 증가, 화면 이동 없음
            endcase
        end
    endfunction

    // 한 바이트 보내고 끝나면 nxt 로
    task send;
        input       rs;
        input [7:0] dat;
        input       lng;
        input [3:0] nxt;
        begin
            d_start <= 1'b1; d_rs <= rs; d_data <= dat; d_long <= lng;
            st_after <= nxt; st <= S_WAIT;
        end
    endtask

    always @(posedge clk) begin
        d_start <= 1'b0;
        if (rst) begin
            st <= S_POWER; st_after <= S_POWER; cnt <= 24'd0; init_i <= 3'd0; idx <= 7'd0;
            cur_shift <= 2'sd0; cur_on <= 1'b1; d_rs <= 1'b0; d_data <= 8'h00; d_long <= 1'b0;
            cg_addr <= 6'd0; dd_addr <= 5'd0;
        end else begin
            case (st)
                S_POWER: if (cnt + 24'd1 >= T_POWER) begin cnt <= 24'd0; st <= S_INIT; end
                         else cnt <= cnt + 24'd1;
                S_INIT: begin
                    init_i <= init_i + 3'd1;
                    send(1'b0, init_cmd(init_i), init_long, (init_i == 3'd5) ? S_CG_CMD : S_INIT);
                end
                S_CG_CMD: begin idx <= 7'd0; cg_addr <= 6'd0; send(1'b0, 8'h40, 1'b0, S_CG); end
                S_CG: begin
                    send(1'b1, {3'b000, cg_row}, 1'b0, (idx == 7'd63) ? S_D0_CMD : S_CG);
                    idx <= idx + 7'd1; cg_addr <= idx[5:0] + 6'd1;
                end
                S_D0_CMD: begin idx <= 7'd0; dd_addr <= 5'd0; send(1'b0, 8'h80, 1'b0, S_D0); end
                S_D0: begin
                    send(1'b1, dd_char, 1'b0, (idx == 7'd15) ? S_D1_CMD : S_D0);
                    idx <= idx + 7'd1; dd_addr <= {1'b0, idx[3:0] + 4'd1};
                end
                S_D1_CMD: begin idx <= 7'd0; dd_addr <= 5'd16; send(1'b0, 8'hC0, 1'b0, S_D1); end
                S_D1: begin
                    send(1'b1, dd_char, 1'b0, (idx == 7'd15) ? S_SHIFT : S_D1);
                    idx <= idx + 7'd1; dd_addr <= {1'b1, idx[3:0] + 4'd1};
                end
                S_SHIFT: begin
                    if (want_s > cur_shift) begin
                        cur_shift <= cur_shift + 2'sd1; send(1'b0, 8'h1C, 1'b0, S_SHIFT);   // 표시 오른쪽으로
                    end else if (want_s < cur_shift) begin
                        cur_shift <= cur_shift - 2'sd1; send(1'b0, 8'h18, 1'b0, S_SHIFT);   // 표시 왼쪽으로
                    end else st <= S_ONOFF;
                end
                S_ONOFF: begin
                    if (want_on != cur_on) begin
                        cur_on <= want_on; send(1'b0, want_on ? 8'h0C : 8'h08, 1'b0, S_CG_CMD);
                    end else st <= S_CG_CMD;
                end
                S_WAIT: if (d_done) st <= st_after;
                default: st <= S_POWER;
            endcase
        end
    end
endmodule
