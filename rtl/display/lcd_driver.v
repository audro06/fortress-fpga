// Text LCD (HD44780 호환, 8비트 버스) 한 바이트 쓰기
//   start 펄스 -> RS·데이터를 올리고 -> E를 잠깐 1 -> E를 0 -> 명령 실행 시간만큼 기다림 -> done 펄스
//   RW는 항상 0 (쓰기만 함, busy flag 안 읽음 = 시간으로 기다림)
//   long = 1 이면 Clear·초기화 명령처럼 오래 걸리는 명령 (5 ms 대기)
module lcd_driver #(
    parameter integer CLK_HZ  = 1_000_000,
    parameter integer EXEC_US = 100          // 보통 명령 실행 대기 (HD44780 은 37 us, 여유 있게)
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       rs,          // 0 명령, 1 데이터
    input  wire [7:0] data,
    input  wire       long,
    output wire       busy,
    output reg        done,
    output reg        lcd_e,
    output reg        lcd_rs,
    output wire       lcd_rw,
    output reg  [7:0] lcd_data
);
    localparam integer US     = (CLK_HZ / 1_000_000 < 1) ? 1 : CLK_HZ / 1_000_000;
    localparam integer T_SET  = 1 * US;      // 주소 셋업 (>= 40 ns)
    localparam integer T_E    = 1 * US;      // E 펄스 폭 (>= 230 ns)
    localparam integer T_EXEC = EXEC_US * US;
    localparam integer T_LONG = 5000 * US;   // Clear / 초기화 명령 (1.52 ms, 첫 Function set은 4.1 ms)

    localparam [1:0] S_IDLE = 2'd0, S_SET = 2'd1, S_EHI = 2'd2, S_WAIT = 2'd3;
    reg [1:0]  st;
    reg [23:0] cnt;
    reg        is_long;

    assign busy   = (st != S_IDLE) || start;
    assign lcd_rw = 1'b0;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            st <= S_IDLE; cnt <= 24'd0; is_long <= 1'b0;
            lcd_e <= 1'b0; lcd_rs <= 1'b0; lcd_data <= 8'h00;
        end else begin
            case (st)
                S_IDLE: if (start) begin
                    lcd_rs <= rs; lcd_data <= data; is_long <= long;
                    lcd_e <= 1'b0; cnt <= 24'd0; st <= S_SET;
                end
                S_SET: if (cnt + 24'd1 >= T_SET) begin
                    cnt <= 24'd0; lcd_e <= 1'b1; st <= S_EHI;
                end else cnt <= cnt + 24'd1;
                S_EHI: if (cnt + 24'd1 >= T_E) begin
                    cnt <= 24'd0; lcd_e <= 1'b0; st <= S_WAIT;   // E 하강 에지에서 LCD가 읽음
                end else cnt <= cnt + 24'd1;
                S_WAIT: if (cnt + 24'd1 >= (is_long ? T_LONG : T_EXEC)) begin
                    cnt <= 24'd0; st <= S_IDLE; done <= 1'b1;
                end else cnt <= cnt + 24'd1;
            endcase
        end
    end
endmodule
