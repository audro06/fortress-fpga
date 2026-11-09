// 시스템 클럭으로 1클럭짜리 펄스(enable)를 만드는 분주기
//   tick_frame : 게임 프레임 틱 (기본 30 Hz) - 게임 로직·애니메이션 기준
//   tick_ms    : 1 kHz - 효과음 길이, 7세그 스캔, 디바운스, 스텝모터
// 모든 모듈은 같은 clk을 쓰고 이 펄스로 "언제 움직일지"만 정해요 (클럭 도메인이 하나라 안전)
module tick_gen #(
    parameter integer CLK_HZ   = 1_000_000,
    parameter integer FRAME_HZ = 30
) (
    input  wire clk,
    input  wire rst,
    output reg  tick_frame,
    output reg  tick_ms
);
    localparam integer FRAME_DIV = CLK_HZ / FRAME_HZ;
    localparam integer MS_DIV    = CLK_HZ / 1000;

    reg [23:0] frame_cnt;
    reg [15:0] ms_cnt;

    always @(posedge clk) begin
        if (rst) begin
            frame_cnt  <= 24'd0;
            ms_cnt     <= 16'd0;
            tick_frame <= 1'b0;
            tick_ms    <= 1'b0;
        end else begin
            if (frame_cnt == FRAME_DIV - 1) begin
                frame_cnt  <= 24'd0;
                tick_frame <= 1'b1;
            end else begin
                frame_cnt  <= frame_cnt + 24'd1;
                tick_frame <= 1'b0;
            end
            if (ms_cnt == MS_DIV - 1) begin
                ms_cnt  <= 16'd0;
                tick_ms <= 1'b1;
            end else begin
                ms_cnt  <= ms_cnt + 16'd1;
                tick_ms <= 1'b0;
            end
        end
    end
endmodule
